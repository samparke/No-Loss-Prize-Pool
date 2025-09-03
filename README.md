## No-Loss-Prize-Pool

**Deposit ETH, you get WIN 1:1. Contract accrues simple interest, and pick a weighted winner via Chainlink VRF who gets the interest pot.**

Features:

- deposit() mints WIN to the depositor; withdraw(amount) returns ETH and transfers WIN back (full withdraw removes you).
- Fixed-rate interest (~5% APR, ~0.00000005/sec) accrues into s_poolBalance (separate from raw ETH balance).
- Weighted draw using Chainlink VRF v2+: requestRandomWords() then selectWinner() after fulfillment; winner paid from s_poolBalance.
- Participants tracked in an array with O(1) add/remove; per-user deposits stored for withdraw checks.
- WIN is an ERC20 with AccessControl; Pool must have MINT_AND_BURN_ROLE on WinToken to mint/return tokens.
- Events for key actions: Deposit, RequestSent/ Fulfilled, WinnerSelected, WinnerPaid.
- View helpers: getPoolBalance(), getIsUserParticipant(addr), getRequestStatus(id).
- Basic reverts for bad calls (no ETH on deposit, withdraw too much, randomness not ready, etc).
- Update VRF config (coordinator, keyHash, subId, gas limits) for your network before you run it.
