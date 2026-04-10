---
name: solidity-security
description: "Audit, review, or harden Solidity smart contracts against known vulnerability patterns. Use when asked to audit a contract, find vulnerabilities, review security, prepare for an audit, or when implementing patterns that require security awareness: reentrancy, oracle manipulation, flash loans, signature replay, DoS, upgradeable storage collisions, access control exploits, ERC20/721/1155 token safety, logic correctness, multi-chain issues. Also triggers for pre-audit checklists, static analysis, and security-focused code review."
---

# Solidity Security Patterns

Vulnerability patterns and hardening techniques for production smart contracts. For code
standards and library-first patterns see the `develop-solidity` skill. For testing see
the `solidity-test` skill.

---

## Reentrancy

- Follow CEI (Checks → Effects → Interactions) on every state-changing function
- Add `nonReentrant` to any function that sends ETH or calls an untrusted contract
- Prefer `ReentrancyGuardTransient` (EIP-1153) — same protection, cheaper gas
- Put `nonReentrant` before other modifiers
- **ERC-721/1155 callbacks**: `safeTransferFrom` triggers `onERC721Received`/`onERC1155Received` on recipient — apply CEI + `nonReentrant` before any safe-transfer call
- **Read-only reentrancy**: view functions reading state mid-call can return inconsistent data if consumed by external oracle-like logic

---

## Interface & Parameter Validation

- Verify `msg.sender` permissions explicitly in every external function — don't rely on assumed upstream context
- Reject unknown/invalid enum values explicitly — never silently fall through to a default
- Validate equal-length arrays before use in batch functions

---

## State Variable Completeness

For every state-changing operation, update **all** affected variables — partial updates are a frequent source of critical bugs:
- Per-user balance AND global total
- Forward mapping AND inverse/secondary index
- Decrement counter on remove AND corresponding array cleanup
- Position amount set to zero AND status flag updated

Check every early-return path — a variable skipped on one branch is often the bug.

---

## Logic Correctness

- A `return` inside a helper doesn't short-circuit the caller — always check the return value
- Validate denominator ≠ 0 before division; validate `a >= b` before `a - b` in `unchecked` blocks
- Multiply before divide: `(a * b) / c` preserves precision; `(a / c) * b` truncates early
- Every `if` without `else` — confirm the no-branch path is intentionally valid, not a silent pass-through

---

## Native Token Handling

- Never use `transfer()` or `send()` — the 2300 gas stipend fails for multisig recipients; use `SafeTransferLib.safeTransferETH()` or `Address.sendValue()`
- Refund excess ETH in `payable` functions with variable cost — check `msg.value > cost` and return the surplus
- Add `receive()` only if the contract is intentionally meant to hold ETH
- Validate `msg.value == 0` on non-payable paths to prevent accidental ETH lock

---

## Loop Safety

- Avoid unbounded loops over user-controlled arrays in state-changing functions — add pagination or process off-chain
- `continue` inside an `unchecked {}` loop with the increment at the bottom causes an infinite loop — the `continue` jumps past `++i`; move the increment before `continue`

---

## Access Control

- Verify `msg.sender` at the top of every privileged function; never use `tx.origin`
- Use `Ownable2Step` (not `Ownable`); use `AccessControl` for multi-role systems
- Add timelocks for critical parameter changes (fee rates, collateral ratios, oracle addresses)
- Admin setters need the same access control as privileged operations

---

## DoS Vectors

- Use pull-over-push for ETH payments — let users call `withdraw()` instead of the contract pushing funds
- Don't loop over unbounded user arrays in state-changing functions
- Avoid logic blocked by a single failing user (e.g. a `receive()` hook that reverts) — pull pattern solves this
- `try/catch` around external calls — a revert inside the callee's `catch` can still propagate; test the full call stack

---

## Integer Arithmetic

- Solidity 0.8+ overflow/underflow protection is on by default — don't disable it in production (`unchecked` blocks must be justified)
- For fixed-point arithmetic, use `1e18` scaling or a battle-tested library (PRBMath, FixedPointMathLib)
- Rounding direction matters in DeFi: always round in the protocol's favor (round down for withdrawals, round up for minting debt)
- Avoid division before multiplication — it truncates precision. Multiply first, then divide.

---

## Timestamp / Block Dependence

- `block.timestamp` can be pushed ±12 seconds by validators — never use it for sub-minute precision (e.g. lottery draws, short-window auctions)
- For timeouts where precision matters, prefer `block.number` over `block.timestamp`
- Never use `blockhash` for randomness — it is predictable by miners and only available for the last 256 blocks; use Chainlink VRF instead
- `block.timestamp` is acceptable for coarse-grained deadlines (hours or days), not fine-grained ones

---

## Static Analysis

Run [Slither](https://github.com/crytic/slither) before every audit submission:

```bash
pip install slither-analyzer
slither . --json slither-report.json
```

Key detectors to review and triage:

| Detector | Severity | What it flags |
|---|---|---|
| `reentrancy-eth` | High | Reentrancy with ETH transfers |
| `reentrancy-no-eth` | Medium | Reentrancy without ETH |
| `uninitialized-state` | High | Uninitialized state variables |
| `arbitrary-send-eth` | High | ETH sent to attacker-controlled address |
| `controlled-delegatecall` | High | `delegatecall` to user-controlled destination |
| `locked-ether` | Medium | Contract receives ETH but has no withdraw path |
| `suicidal` | High | Unprotected `selfdestruct` |
| `unchecked-transfer` | High | ERC20 `transfer`/`transferFrom` return value ignored |

Triage each finding as true positive or false positive before acting — Slither can over-report on proxies and upgradeable patterns.

---

## Configuration Safety

- Validate non-zero address for all payment recipients and privileged roles at configuration time
- Validate `startTime < endTime`; compare correctly against `block.timestamp`

---

## Deployment Patterns

- `new ContractName(...)` implicitly reverts on deployment failure — no manual check needed
- Inline `assembly create` / `create2` does **not** revert — check `deployed == address(0)` manually
- With CREATE2 across chains: include chain-specific data in the salt if constructor args differ per chain

---

## Static Analysis

Run `slither .` and `aderyn .` before every audit submission. Focus on High findings — treat all as blocking, investigate Medium. Triage accepted risks with an inline `// slither-disable-next-line` comment explaining why.

---

## References

Load the relevant reference file when the contract involves that scenario:

| Scenario | Reference |
|----------|-----------|
| ERC20 / ERC721 / ERC1155 token handling | [reference/token-standards.md](reference/token-standards.md) |
| Price feeds, oracle consumption | [reference/oracle.md](reference/oracle.md) |
| Deposits/withdrawals, DeFi pricing logic | [reference/flashloan.md](reference/flashloan.md) |
| Off-chain signatures, permit, meta-transactions | [reference/signatures.md](reference/signatures.md) |
| Proxy / upgradeable contracts | [reference/upgradeable.md](reference/upgradeable.md) |
| Multi-chain deployment, bridging | [reference/multichain.md](reference/multichain.md) |
