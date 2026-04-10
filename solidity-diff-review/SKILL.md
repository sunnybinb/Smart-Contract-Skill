---
name: solidity-diff-review
description: "Review a Solidity code diff (git diff / PR changes) for security issues. Use when given a diff, patch, PR description, or set of changed files to review for: newly introduced vulnerabilities, removed security guards, access-control regressions, storage layout changes, new untrusted external calls, CEI violations, and logic changes that break invariants. Produces a structured findings report with severity ratings (High / Medium / Low / Info). Distinct from a full audit — only reviews what changed."
tags:
  - solidity
  - smart-contracts
  - security
  - diff
  - code-review
  - pr-review
  - audit
---

# Solidity Diff Security Review

Review Solidity code changes for security regressions and newly introduced vulnerabilities. This skill covers **only what changed** — it is not a full audit of the codebase.

Two parallel tracks:
- **Track A** — New code security check: apply vulnerability patterns to all added/modified code
- **Track B** — Regression analysis: identify protections that were removed or weakened

For detailed vulnerability pattern descriptions, see the `solidity-security` skill.

---

## Phase 1 — Parse and Categorise the Diff

Before checking anything, read the entire diff and tag each changed hunk with one or more of the categories below. This determines which checks to apply.

| Category | Signal |
|---|---|
| `NEW_FUNCTION` | `+` lines containing a `function` declaration — entirely new entry points |
| `MODIFIED_FUNCTION` | Both `+` and `-` lines within the same function body |
| `REMOVED_GUARD` | `-` lines with `require`, `revert`, `if (...) revert`, `modifier`, `nonReentrant`, `onlyOwner`, `onlyRole`, or similar guards |
| `LOGIC_REORDER` | Code moved within a function (same logic, different sequence) — watch for CEI order changes |
| `ACCESS_CONTROL_CHANGE` | Modifier added or removed; visibility changed (`internal → external`, `private → public`); role check added or removed |
| `STATE_VAR_CHANGE` | `+`/`-` at contract storage level (declarations, not inside functions) — variable added, removed, reordered, or type changed |
| `IMPORT_CHANGE` | New or removed `import` statements — new library or safety library removed |
| `DEPENDENCY_CHANGE` | New external contract being called — `new X()`, new interface usage, new `IERC20(addr).call(...)` pattern |

A single hunk can have multiple categories. Assign all that apply.

---

## Phase 2 — Track A: New Code Security Review

For every `+` line in `NEW_FUNCTION` or `MODIFIED_FUNCTION` hunks, apply these checks. Only check new/modified code — do not report pre-existing issues that the diff does not touch.

### Reentrancy
- Does the function send ETH or call an external contract (ERC-20 transfer, external interface call)?
- If yes: is CEI (Checks → Effects → Interactions) followed? State updates must come **before** the external call
- Is `nonReentrant` present on functions that touch ETH or untrusted contracts?
- If ERC-721/1155 `safeTransferFrom` is used: `onReceived` hook fires on the recipient — treat as untrusted external call

### Access Control
- Does every new `external` or `public` function have an explicit `msg.sender` permission check (modifier or inline `if`)?
- Does it use `tx.origin`? (`tx.origin` must never be used for auth)
- Is visibility intentional? A new `public` function that should be `internal` is a High finding

### Input Validation
- Are multi-array parameters checked for equal length?
- Are enum values or type-dispatched parameters validated? Unknown values should revert
- Are zero-address inputs validated where the address is used for payments or access control?

### Math Safety
- Any new division — is the denominator validated non-zero?
- Any new `unchecked` block — is every subtraction bounds-checked before use?
- Multiply before divide — does new code divide before multiplying (precision loss)?

### Native Token (ETH)
- Any new `payable` function — does it refund excess `msg.value` if the call has a fixed cost?
- Does any new ETH transfer use `transfer()` or `send()`? Must use `call{value:}` or `SafeTransferLib`
- Does a contract expected to receive ETH have a `receive()` function?

### ERC-20 Safety
- Are new token transfers using `safeTransfer` / `safeTransferFrom`? (Required for USDT and other non-standard tokens)
- Is `approve` called with a non-zero value replacing another non-zero value? (Race condition)
- Is `token.balanceOf(address(this))` used for internal accounting? (Flash-loan inflatable)

### Signature Verification
- Is new signature code using EIP-712 with nonce, `block.chainid`, and contract address in the domain?
- Is `signer != address(0)` validated after recovery?
- Is the nonce invalidated after use?
- Is `SignatureChecker` (supports ERC-1271 smart wallets) used instead of raw `ecrecover`?

### Oracle Integration
- Is a new price feed read without validating all `latestRoundData()` return values?
- Is `updatedAt` compared against `block.timestamp - MAX_STALENESS`?
- Is an AMM spot price (`slot0`, `reserve`) used as a price source?

### Upgradeable Contracts
- Is a new state variable initialised at the declaration site (`uint256 public foo = 42`)? This doesn't execute for proxy deployments — must be set in `initialize()`
- Is a new variable inserted between existing state variables (in an already-deployed upgradeable contract)? Storage collision

---

## Phase 3 — Track B: Regression / Impact Analysis

Focus on `-` lines and structural changes. Regressions are often the most severe finding in a diff and the most commonly missed in manual review.

### Removed Guards (`REMOVED_GUARD`)

This is the highest-priority category. For every removed guard:
1. Identify **what invariant** the guard was enforcing
2. Determine **who can now bypass it** and what they can do
3. Rate severity: if an attacker can exploit the missing guard to steal funds or corrupt state → High

Common patterns:
```diff
- require(msg.sender == owner, "not owner");    // High: access control removed
- if (amount == 0) revert Vault__ZeroAmount();  // Low-Medium: input validation removed
- nonReentrant                                  // High: reentrancy guard removed
- require(!paused, "paused");                   // Medium-High: pause check removed
```

### CEI Reordering (`LOGIC_REORDER`)

Check if lines were moved in a way that puts an external call **before** a state update:

```diff
- balances[msg.sender] -= amount;     // was: state update first
- token.safeTransfer(msg.sender, amount);
+ token.safeTransfer(msg.sender, amount);  // now: external call before state update
+ balances[msg.sender] -= amount;          // CEI violated → reentrancy possible
```

Any reordering that moves an external call earlier in a function is a High finding unless `nonReentrant` is present.

### Access Control Changes (`ACCESS_CONTROL_CHANGE`)

| Change | Severity |
|---|---|
| Modifier removed (`onlyOwner`, `onlyRole`) | High |
| Visibility `internal → external` or `private → public` | High |
| Visibility `external → internal` on a function users relied on | Medium (functionality regression) |
| Modifier added (tightening access) | Info — verify intentional |
| New `onlyOwner` setter without timelock | Medium (centralisation risk) |

### Storage Variable Changes (`STATE_VAR_CHANGE`)

For upgradeable contracts (UUPS, Transparent Proxy, Beacon):
- Any variable **removed** → storage collision in all subsequent slots — High
- Any variable **reordered** → same collision — High
- Any variable **inserted** between existing variables → pushes all following variables down — High
- Any **new inherited base contract** added to the inheritance chain → inserts its storage before the child's — High
- Variable added **at the end** of all state → safe (append-only rule)

For non-upgradeable contracts, state variable reordering is a non-issue but a **type change** (e.g. `uint128 → uint256`) can affect ABI encoding and event parsing.

### Import Changes (`IMPORT_CHANGE`)

| Change | Check |
|---|---|
| Safety library removed (`SafeERC20`, `ReentrancyGuard`, `Ownable2Step`) | High — verify the safety it provided is now handled another way |
| New import of an unaudited library | Medium — check if the library has known issues |
| Version pinning removed (floating pragma) | Low |
| New import of a protocol's own unreviewed contract | Medium — new trust dependency |

### New External Dependencies (`DEPENDENCY_CHANGE`)

For every new external contract call:
- Is the callee trusted? (Protocol-owned vs. arbitrary user-supplied address)
- Can the callee reenter? Does the call happen after state is fully updated?
- If the address comes from user input: can an attacker pass a malicious contract?
- Is the interface minimal (call only the needed function)?

---

## Phase 4 — Output: Structured Findings Report

Produce findings in this exact format. Order by severity (High first).

```
## Diff Security Review

**Scope:** <list of files changed, total hunks>
**Risk summary:** X High · Y Medium · Z Low · W Info

---

### [H-01] <Short descriptive title>

**Severity:** High
**Category:** REMOVED_GUARD / NEW_FUNCTION / ... (from Phase 1)
**Location:** `src/Vault.sol` hunk starting at line 87
**Change:**
```diff
- require(!paused, "paused");
```
**Impact:** Any caller can now invoke `withdraw()` while the protocol is in a paused state, allowing fund drainage during an incident response window.
**Recommendation:** Restore the pause check, or replace with an equivalent `whenNotPaused` modifier from OpenZeppelin `Pausable`.

---

### [M-01] <Short descriptive title>

**Severity:** Medium
**Category:** NEW_FUNCTION
**Location:** `src/Lending.sol` line 134 — new function `liquidate()`
**Change:** New external function added with no reentrancy guard.
**Impact:** The liquidation calls `token.safeTransfer(liquidator, reward)` before decrementing the borrower's debt. A malicious liquidator contract can reenter `liquidate()` and claim the reward multiple times.
**Recommendation:** Add `nonReentrant` to `liquidate()` and ensure state (`debtOf[borrower]`) is updated before the transfer (CEI).

---

### [L-01] <Short descriptive title>
...

### [I-01] <Short descriptive title>
...
```

**Severity scale:**

| Severity | Criteria |
|---|---|
| **High** | Directly exploitable: fund loss, access bypass, state corruption; or critical guard removed with clear exploit path |
| **Medium** | Exploitable under specific conditions; weakened protection; new risky pattern without an obvious immediate exploit |
| **Low** | Missing best-practice check; not directly exploitable but raises risk if other assumptions break |
| **Info** | Style note, naming issue, improvement suggestion; no security impact |

**If no findings:** state explicitly — `No security issues found in this diff. All changes reviewed against Track A and Track B criteria.`

---

## Checklist: Change-Type Quick Reference

Use this when a hunk's category is identified, to avoid missing common checks:

**`NEW_FUNCTION` — always check:**
- [ ] Caller permission (`msg.sender` validated)
- [ ] CEI order if any external call or ETH send
- [ ] `nonReentrant` if ETH or untrusted external call
- [ ] Input bounds (array lengths, zero-address, zero-amount)

**`REMOVED_GUARD` — always ask:**
- [ ] What invariant did this guard protect?
- [ ] Can an attacker exploit the missing guard now?
- [ ] Was it removed intentionally (documented in PR description)?

**`STATE_VAR_CHANGE` in upgradeable contract — always check:**
- [ ] No variable inserted before existing ones
- [ ] No variable removed or reordered
- [ ] No new base contract inherited mid-chain
- [ ] New variable is at the bottom of storage, not the top

**`LOGIC_REORDER` — always check:**
- [ ] Does the new order put any external call before a state update?
- [ ] Is `nonReentrant` present if external call moved earlier?

**`ACCESS_CONTROL_CHANGE` — always check:**
- [ ] If modifier removed: what was it protecting?
- [ ] If visibility widened: is this intentional? Can users call this safely?

---

## Scope Discipline

- **Do not** report pre-existing issues that the diff does not modify — those belong in a full audit, not a diff review
- **Do** note if a diff interacts with pre-existing vulnerable code (e.g. a new call path that routes through an already-known-insecure function)
- When in doubt about whether a finding is in-scope of the diff, include it with an `[I]` (Info) tag and note it was pre-existing

See the `solidity-security` skill for detailed explanations of each vulnerability pattern referenced above.
