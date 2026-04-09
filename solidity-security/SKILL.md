---
name: solidity-security
description: "Audit, review, or harden Solidity smart contracts against known vulnerability patterns. Use when asked to audit a contract, find vulnerabilities, review security, prepare for an audit, or when implementing patterns that require security awareness: reentrancy, oracle manipulation, flash loans, signature replay, DoS, upgradeable storage collisions, access control exploits. Also triggers for pre-audit checklists and security-focused code review."
tags:
  - solidity
  - smart-contracts
  - security
  - audit
  - evm
  - defi
  - vulnerabilities
---

# Solidity Security Patterns

Vulnerability patterns and hardening techniques for production smart contracts. For code
standards and library-first patterns see the `develop-solidity` skill. For testing see
the `solidity-test` skill.

---

## Reentrancy

Follow CEI strictly: **Checks → Effects → Interactions**

```solidity
function withdraw(uint256 amount) external nonReentrant {
    // Checks
    if (balances[msg.sender] < amount) revert Vault__InsufficientBalance();
    // Effects — state updated before external call
    balances[msg.sender] -= amount;
    // Interactions — external call last
    SafeTransferLib.safeTransferETH(msg.sender, amount);
}
```

- Use `nonReentrant` on any function that sends ETH or calls an untrusted external contract
- Prefer `ReentrancyGuardTransient` (EIP-1153) over `ReentrancyGuard` — same protection, cheaper gas
- Put `nonReentrant` before other modifiers in the modifier list
- Read-only reentrancy is also a real attack vector — view functions that read state mid-call can return inconsistent values; protect them too if they feed external decisions (e.g. oracle consumers)

---

## Oracle Safety

- Never use AMM spot prices as oracles — trivially manipulated in one transaction
- Use Chainlink `latestRoundData()`, validate ALL return values, and check staleness:

```solidity
(uint80 roundId, int256 price, , uint256 updatedAt, uint80 answeredInRound) =
    priceFeed.latestRoundData();
if (price <= 0) revert Oracle__InvalidPrice();
if (updatedAt < block.timestamp - MAX_STALENESS) revert Oracle__StalePrice();
if (answeredInRound < roundId) revert Oracle__IncompleteRound();
```

- Use TWAP (time-weighted average price) as a secondary check for high-value operations
- Don't read oracle prices in the same block as a large balance change — use commit-reveal or delay patterns for high-value liquidations

---

## Flash Loan / Same-Block Manipulation

- Don't use `token.balanceOf(address(this))` for accounting — an attacker can donate tokens to skew it. Use internal tracked balances instead.
- Treat any value that can move atomically (balances, prices, totals) as potentially adversarial
- Price-dependent logic (liquidations, minting, borrowing) must use oracle prices, not on-chain spot values
- If your contract checks a condition and acts on it in the same transaction, assume an attacker can set that condition to any value they want

---

## Access Control Vulnerabilities

- Protect UUPS `_authorizeUpgrade` — an unprotected upgrade function is catastrophic. Always gate it with `onlyOwner` or equivalent
- Never leave `initialize()` callable after deployment — use OpenZeppelin's `Initializable` and `_disableInitializers()` in the constructor of implementation contracts
- Add timelocks for critical parameter changes (fee rates, collateral ratios, oracle addresses) so users can exit before changes take effect
- Don't rely on `tx.origin` for authentication — use `msg.sender`
- Two-step ownership: use `Ownable2Step` so accidental transfer to a wrong address can be cancelled before it takes effect

---

## Signature Safety

Always use EIP-712 typed structured data. Include nonce, chainId, and contract address to prevent replay:

```solidity
// Use OpenZeppelin's EIP712 + ECDSA — never hand-roll signature verification
bytes32 structHash = keccak256(abi.encode(TYPEHASH, nonce, chainId, amount));
bytes32 digest = _hashTypedDataV4(structHash);
address signer = ECDSA.recover(digest, signature);
```

- Nonce per signer: invalidate after use — never allow signature reuse
- Chain ID in domain separator: prevents cross-chain replay (EIP-712 handles this if domain is set correctly)
- Contract address in domain separator: prevents replay against a different contract with same interface
- Use `SignatureChecker` from OpenZeppelin to support both EOA and ERC-1271 smart wallet signers
- Validate `signer != address(0)` — `ECDSA.recover` returns zero for malformed signatures

---

## DoS Vectors

- Don't loop over unbounded user-supplied arrays in state-changing functions — add pagination or process off-chain
- Use pull-over-push for ETH payments: let users call `withdraw()` instead of the contract pushing ETH to a list of recipients
- Don't use `transfer()` or `send()` — the 2300 gas stipend is insufficient post-EIP-2929. Use `SafeTransferLib.safeTransferETH()`
- Avoid logic that can be blocked by a single user failing (e.g. reverting in a `receive()` hook) — pull pattern solves this
- Be careful with `try/catch` around external calls — a revert inside the catch can still be triggered by the callee

---

## Upgradeable Contracts

- Never change the order, type, or remove existing storage variables in an upgrade — causes storage collisions and corrupts state
- Add storage gaps in base contracts so future versions can add state variables: `uint256[50] private __gap;`
- Always write fork tests for upgrade paths — test the actual upgrade against a mainnet fork, not just unit tests
- Call all parent `__init` functions in `initialize()` — missing one can leave the contract in a broken state
- Prefer UUPS over Transparent Proxy — UUPS puts upgrade logic in the implementation (cheaper for users, upgrade auth is explicit)
- Use `@openzeppelin/hardhat-upgrades` or `forge-upgrades` to validate storage layout compatibility before deploying an upgrade
- For UUPS: the `_authorizeUpgrade` function must be properly protected; for Transparent Proxy: only the ProxyAdmin can upgrade

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

## Pre-Audit Checklist

Run through this before submitting for external audit:

- [ ] All admin/owner roles are multisigs for mainnet (never plain EOA)
- [ ] No `initialize()` callable after deployment — `_disableInitializers()` in implementation constructor
- [ ] CEI pattern followed on every state-changing external-call function
- [ ] `nonReentrant` on all ETH-sending and untrusted-external-call functions
- [ ] All Chainlink return values validated, staleness checked
- [ ] No `token.balanceOf(this)` used for internal accounting
- [ ] EIP-712 signatures include nonce, chainId, contract address; nonces invalidated after use
- [ ] No unbounded loops over user-controlled arrays
- [ ] No `transfer()` or `send()` — use `SafeTransferLib`
- [ ] Upgrade storage layout validated with tooling
- [ ] Fuzz and invariant tests pass with meaningful run count (≥ 10,000)
- [ ] Security contact in NatSpec on every deployed contract
- [ ] **Get an external audit before deploying significant value to mainnet**
