// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {Farpot} from "../src/Farpot.sol";

contract Deploy is Script {
    address public immutable usdc = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;

    function run() public {
        address deployer = vm.envAddress("DEPLOYER_ADDRESS");
        address vault = vm.envAddress("VAULT_ADDRESS");
        if (deployer == address(0) || vault == address(0)) revert();

        vm.startBroadcast(deployer);
        new Farpot(usdc, vault);
        vm.stopBroadcast();
    }
}
