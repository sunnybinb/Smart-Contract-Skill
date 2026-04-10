# Governance Attack Vectors

Security patterns for on-chain voting and governance systems.

---

## Flash Loan Governance Attack

An attacker can borrow a large token supply in a flash loan, use it to pass a malicious proposal (or meet quorum), then return the tokens — all in one transaction. This is only possible if vote weight is based on **current** token balance.

**Vulnerable pattern:**
```solidity
// ❌ Reads live balance — exploitable via flash loan
function castVote(uint256 proposalId) external {
    uint256 votes = token.balanceOf(msg.sender);
    _recordVote(proposalId, msg.sender, votes);
}
```

**Secure pattern — use snapshots:**
```solidity
// ✅ Vote weight frozen at proposal creation block
function castVote(uint256 proposalId) external {
    uint256 snapshotBlock = proposals[proposalId].snapshotBlock;
    uint256 votes = token.getPastVotes(msg.sender, snapshotBlock);
    _recordVote(proposalId, msg.sender, votes);
}
```

Use OpenZeppelin's `ERC20Votes` + `Governor` — these handle snapshotting correctly out of the box.

---

## Snapshot Timing

- Take the snapshot at proposal **creation** time, not at voting time or execution time
- Never use `block.number - 1` as a snapshot — it allows same-block manipulation
- Use a voting delay (e.g. 1–2 days) between proposal creation and vote start, giving token holders time to acquire voting power legitimately before the snapshot closes

---

## Quorum Must Use Past Supply

Quorum is typically expressed as a percentage of total supply. If you use live `totalSupply()`, an attacker can flash-mint (if the token supports it) to artificially lower the quorum percentage:

```solidity
// ❌ Live supply — manipulable
uint256 quorum = token.totalSupply() * QUORUM_BPS / 10_000;

// ✅ Past supply at snapshot block
uint256 quorum = token.getPastTotalSupply(snapshotBlock) * QUORUM_BPS / 10_000;
```

---

## Timelock Between Proposal and Execution

Always enforce a timelock between a proposal passing and it being executable. This gives users time to exit the protocol or prepare a counter-proposal if a malicious governance action passes:

- Minimum recommended timelock: 24–48 hours for high-value protocols
- Immutable critical parameters (e.g. token supply cap) should require a longer timelock or be non-governable
- Emergency pause functions may bypass the timelock — ensure emergency roles are still multi-sig gated

---

## Vote Delegation Double-Counting

When using delegation (e.g. `ERC20Votes.delegate()`), verify the implementation does not allow delegated voting power to be double-counted. OpenZeppelin's implementation is correct; custom delegation logic is a common source of bugs:

- Delegating to yourself should not increase your voting power
- Delegating to another address should fully transfer your power, not copy it
- Re-delegating mid-vote should not affect already-cast votes for the current proposal

---

## Proposal Spam / DoS

- Require a non-trivial token deposit or threshold to create proposals — prevents spam attacks that clog the governance queue
- Proposals that don't reach quorum should refund the deposit; malicious proposals that are defeated should slash or forfeit it
- Limit active proposals per address to prevent griefing via queue flooding
