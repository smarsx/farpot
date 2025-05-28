// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "solady/auth/Ownable.sol";
import {ERC20} from "solady/tokens/ERC20.sol";
import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";
import {VRFV2PlusWrapperConsumerBase} from "./utils/vrf/VRFV2PlusWrapperConsumerBase.sol";

/// @title Farpot: a configurable fundraising raffle.
/// @dev Modeled on classic 50-50 raffles, Farpot adds an optional referral slice and lets creators configure any pot split they want.
/// @author @smarsx
/// @notice experimental unaudited test-in-prod software.
contract Farpot is Ownable, VRFV2PlusWrapperConsumerBase {
    struct Pot {
        bool resolved;
        bool seeded;
        uint16 fundraiserShare;
        uint16 raffleShare;
        uint16 referralShare;
        uint40 deadline;
        uint152 goal;
        uint256 seed;
        address creator;
        address fundraiser;
        string title;
        string description;
        string longDescription;
        address[] tickets;
        address[] referrals;
    }

    error InvalidFee();
    error InvalidParams();
    error InvalidPot();
    error InvalidWinner();
    error ExistingPot();
    error PotNotExist();
    error PotClosed();
    error PotOpen();
    error NoTickets();
    error SeedExists();
    error PotResolved();
    error SeedNotExists();

    event CreatedPot(
        uint256 indexed id,
        uint256 deadline,
        uint256 fundraiserShare,
        uint256 raffleShare,
        uint256 referralShare,
        address beneficiary,
        string title
    );
    event NewTicket(uint256 indexed potID, uint256 numTickets, address user, address referral);
    event PreSeeded(uint256 indexed potID, uint256 indexed requestID);
    event Seeded(uint256 indexed potID, uint256 indexed seed);
    event Resolved(uint256 indexed potID, uint256 totalPot, address winner, address referrer);
    event EmergencyResolved(uint256 indexed potID, uint256 totalPot, address to);
    event UpdatedVault(address vault);

    uint256 public constant TICKET_PRICE = 1e6; // $1
    uint256 public constant FEE_NUMERATOR = 100;
    uint256 public constant FEE_DENOMINATOR = 10000;
    uint256 public constant MINIMUM_NUMERATOR = 100;
    uint256 public constant EMERGENCY_RECOVERY_PERIOD = 100 days;
    uint256 public constant MAX_TIMEFRAME = 30 days;

    ERC20 public immutable usdc;
    address public vault;
    uint256 public nextID;

    mapping(uint256 potID => Pot) public pots;
    mapping(uint256 => uint256) public vrfRequests;

    constructor(address _usdc, address _vault) VRFV2PlusWrapperConsumerBase(0xb0407dbe851f8318bd31404A49e658143C982F23) {
        _initializeOwner(msg.sender);
        vault = _vault;
        usdc = ERC20(_usdc);
    }

    function create(
        uint256 _goal,
        uint256 _fundraiserShare,
        uint256 _raffleShare,
        uint256 _referralShare,
        uint256 _deadline,
        address _fundraiser,
        string calldata _title,
        string calldata _description,
        string calldata _longDescription
    ) external returns (uint256 id) {
        id = nextID++;

        if (_fundraiser == address(0)) revert InvalidParams();
        if (_deadline <= block.timestamp || _deadline > block.timestamp + MAX_TIMEFRAME) revert InvalidParams();
        if (_fundraiserShare + _raffleShare + _referralShare + FEE_NUMERATOR != FEE_DENOMINATOR) revert InvalidParams();
        if (_fundraiserShare < MINIMUM_NUMERATOR || _raffleShare < MINIMUM_NUMERATOR || _referralShare < MINIMUM_NUMERATOR) revert InvalidParams();

        address[] memory tickets;

        pots[id] = Pot({
            resolved: false,
            seeded: false,
            fundraiserShare: uint16(_fundraiserShare),
            raffleShare: uint16(_raffleShare),
            referralShare: uint16(_referralShare),
            deadline: uint40(_deadline),
            goal: uint152(_goal),
            seed: 0,
            creator: msg.sender,
            fundraiser: _fundraiser,
            title: _title,
            description: _description,
            longDescription: _longDescription,
            tickets: tickets,
            referrals: tickets
        });

        emit CreatedPot(id, _deadline, _fundraiserShare, _raffleShare, _referralShare, _fundraiser, _title);
    }

    function enter(uint256 _potID, uint256 _numTickets, address _referral) external {
        _enter(_potID, _numTickets, _referral, msg.sender);
    }

    function enterFor(uint256 _potID, uint256 _numTickets, address _referral, address _purchaser) external {
        _enter(_potID, _numTickets, _referral, _purchaser);
    }

    function _enter(uint256 _potID, uint256 _numTickets, address _referral, address _purchaser) internal {
        if (pots[_potID].deadline == 0) revert PotNotExist();
        if (block.timestamp >= pots[_potID].deadline) revert PotClosed();
        if (_numTickets == 0) revert InvalidParams();

        if (_referral != address(0) && _referral != _purchaser) {
            pots[_potID].referrals.push(_referral);
        }

        for (uint256 i; i < _numTickets; i++) {
            pots[_potID].tickets.push(_purchaser);
        }

        emit NewTicket(_potID, _numTickets, _purchaser, _referral);
        usdc.transferFrom(msg.sender, address(this), _numTickets * TICKET_PRICE);
    }

    function startResolve(uint256 _potID) external {
        if (pots[_potID].deadline == 0) revert PotNotExist();
        if (block.timestamp <= pots[_potID].deadline) revert PotOpen();
        if (pots[_potID].seeded) revert SeedExists();
        if (pots[_potID].tickets.length == 0) revert NoTickets();

        (uint256 requestID, ) = requestRandomness(200000, 1, 1, bytes(""));
        vrfRequests[requestID] = _potID;
        emit PreSeeded(_potID, requestID);
    }

    function fulfillRandomWords(uint256 _requestId, uint256[] memory _randomWords) internal override {
        uint256 potID = vrfRequests[_requestId];
        if (pots[potID].seeded) revert SeedExists();
        pots[potID].seed = _randomWords[0];
        pots[potID].seeded = true;
        emit Seeded(potID, _randomWords[0]);
    }

    function finishResolve(uint256 _potID) external {
        if (pots[_potID].resolved) revert PotResolved();
        if (!pots[_potID].seeded) revert SeedNotExists();
        pots[_potID].resolved = true;

        uint256 pot = pots[_potID].tickets.length * TICKET_PRICE;
        address winner = pots[_potID].tickets[pots[_potID].seed % pots[_potID].tickets.length];

        // if len(referrals) > 0: pick random referral else beneficiary gets referral pot
        address referral = pots[_potID].referrals.length > 0
            ? pots[_potID].referrals[pots[_potID].seed % pots[_potID].referrals.length]
            : pots[_potID].fundraiser;

        uint256 fundraiserPot = FixedPointMathLib.mulDiv(pot, pots[_potID].fundraiserShare, FEE_DENOMINATOR);
        uint256 rafflePot = FixedPointMathLib.mulDiv(pot, pots[_potID].raffleShare, FEE_DENOMINATOR);
        uint256 referralPot = FixedPointMathLib.mulDiv(pot, pots[_potID].referralShare, FEE_DENOMINATOR);
        uint256 feePot = pot - (fundraiserPot + rafflePot + referralPot); // clean-up rounding

        usdc.transfer(pots[_potID].fundraiser, fundraiserPot);
        usdc.transfer(winner, rafflePot);
        usdc.transfer(referral, referralPot);
        usdc.transfer(vault, feePot);

        emit Resolved(_potID, pot, winner, referral);
    }

    /*//////////////////////////////////////////////////////////////
                                PUBLIC
    //////////////////////////////////////////////////////////////*/

    function getTickets(uint256 _potID) public view returns (address[] memory tickets) {
        tickets = pots[_potID].tickets;
    }

    function getReferrals(uint256 _potID) public view returns (address[] memory referrals) {
        referrals = pots[_potID].referrals;
    }

    /*//////////////////////////////////////////////////////////////
                                ADMIN
    //////////////////////////////////////////////////////////////*/

    function emergencyRecovery(uint256 _potID, address _to) external onlyOwner {
        if (!pots[_potID].resolved && block.timestamp > pots[_potID].deadline + EMERGENCY_RECOVERY_PERIOD && pots[_potID].tickets.length > 0) {
            pots[_potID].resolved = true;
            uint256 pot = pots[_potID].tickets.length * TICKET_PRICE;
            usdc.transfer(_to, pot);
            emit EmergencyResolved(_potID, pot, _to);
        }
    }

    function updateVault(address _vault) external onlyOwner {
        vault = _vault;
        emit UpdatedVault(_vault);
    }

    function withdrawalNonUsdc(address _token, address _to, uint256 _amt) external onlyOwner {
        if (_token == address(usdc)) revert();
        ERC20(_token).transfer(_to, _amt);
    }
}
