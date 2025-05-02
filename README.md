# Farpot

A **configurable‑share fundraising raffle** smart‑contract built with **Solady** and **Chainlink VRF V2 Plus**. Participants buy \$1 USDC “tickets”; when the deadline passes an on‑chain RNG picks a winner and the contract splits the pot between three parties **in whatever proportions the pot creator specifies**:

> Unlike a classic **50 / 50 raffle**—where exactly half the pot goes to the beneficiary and half to the winner—**Farpot supports *any* split whose parts add up to 100 %**. This flexibility lets creators run 60/30/10 raffles, 70/25/5, or any other combination to fit their campaign.

---

## ✨ Core flow

1. **`create`** – anyone opens a new pot, setting `goal` (optional), `deadline`, `beneficiaryShare`, `winnerShare`, `referralShare`, `beneficiary`, and metadata strings.
2. **`enter`** – users buy `n` tickets; a *first‑time* referral address can be attached to their wallet.
3. **`startResolve`** – callable by anyone once the deadline passes; triggers a Chainlink VRF request.
4. **`fulfillRandomWords`** – VRF wrapper callback stores the random `seed` and marks the pot *seeded*.
5. **`finishResolve`** – calculates the winning ticket (pot.tickets[`seed % tickets.length`]), transfers funds according to the configured shares.
6. **`emergencyRecovery`** – owner safeguard: after `deadline + 100 days`, sweep funds to a rescue address if the pot is still unresolved.

---

## 🗄️ Storage layout

```solidity
struct Pot {
    bool    resolved;
    bool    seeded;
    uint16  winnerShare;          // y
    uint16  beneficiaryShare;     // x
    uint16  referralShare;        // z
    uint40  deadline;
    uint152 goal;
    uint256 seed;                 // VRF result
    address creator;
    address beneficiary;
    string  title;
    string  description;
    string  longDescription;
    address[] tickets;            // each ticket = entrant address
}
```

---

## Disclaimer

*These smart contracts and testing suite are being provided as is. No guarantee, representation or warranty is being made, express or implied, as to the safety or correctness of anything provided herein or through related user interfaces. This repository and related code have not been audited and as such there can be no assurance anything will work as intended, and users may experience delays, failures, errors, omissions, loss of transmitted information or loss of funds. The creators are not liable for any of the foregoing. Users should proceed with caution and use at their own risk.*