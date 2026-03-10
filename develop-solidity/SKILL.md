---
name: develop-solidity-contracts
description: "Write production-grade Solidity smart contracts following code standards and OpenZeppelin library-first patterns. Use when writing tokens (ERC20/ERC721/ERC1155), DeFi protocols, access control, governance, or upgradeable contracts. Triggers for any Foundry or Hardhat project that involves writing Solidity. For deep security vulnerability patterns use the solidity-security skill. For test writing use the solidity-test skill."
tags:
  - solidity
  - smart-contracts
  - foundry
  - evm
  - blockchain
  - defi
---

# Solidity Development Standards

Production-grade smart contract development synthesizing the Cyfrin security team's standards,
OpenZeppelin's library-first methodology, and battle-tested DeFi patterns.

## Philosophy

**Correctness over cleverness.** Prioritize auditability over optimization and battle-tested
library components over custom solutions. Write every line as if a well-funded adversary is
reading it right now — but don't over-engineer.

---

## Workflow: Understand Before Writing

Before generating or modifying any contract:

1. **Search** the project for existing contracts (`Glob **/*.sol`)
2. **Read** existing files — understand what already exists before changing anything
3. **Integrate, don't replace** — "add pausability" means modify existing code, not generate from scratch. Only replace if explicitly asked ("start fresh", "rewrite this")

---

## Library-First: OpenZeppelin Before Custom Code

Before writing ANY custom logic, check whether OpenZeppelin already provides it:

| Situation | Action |
|-----------|--------|
| Exact match exists (`Ownable`, `ERC20`, `ReentrancyGuard`, …) | Import and use directly |
| Close match exists | Import and extend via the `virtual` override points the library exposes |
| No match | Only then write custom logic |

**Never hand-write what the library already provides:**
- Never `require(msg.sender == owner)` — use `Ownable`
- Never write a custom `paused` modifier — use `Pausable` or `ERC20Pausable`
- Never hand-roll ERC20/ERC721 transfer logic

**Find OZ in the project:** `lib/openzeppelin-contracts/` (Foundry) or
`node_modules/@openzeppelin/contracts/` (npm/Hardhat). Use `Glob` to browse what's actually
installed — do not assume which version is available. Check the installed source's NatSpec to
confirm which functions are `virtual` before recommending overrides; this changes across versions.

**Never copy-paste library source into the user's contract.** Always import from the dependency
so the project receives future security updates.

---

## Code Quality and Style

### File Layout

```
Pragma statements
Import statements (named, absolute only)
Events
Errors
Interfaces
Libraries
Contracts
```

### Contract Layout

```
Type declarations
State variables
Events
Errors
Modifiers
Functions (see ordering below)
```

### Function Ordering

```
constructor
receive (if exists)
fallback (if exists)
external/public state-changing
external/public view/pure
internal/private state-changing
internal/private view/pure
```

Use section headers between groups:

```solidity
/*//////////////////////////////////////////////////////////////
                   INTERNAL STATE-CHANGING FUNCTIONS
//////////////////////////////////////////////////////////////*/
```

### Imports

Named, absolute imports only — never relative paths:

```solidity
// good
import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {Ownable2Step} from "openzeppelin-contracts/contracts/access/Ownable2Step.sol";

// bad
import "../token/ERC20.sol";
```

### Errors

Custom errors prefixed `ContractName__ErrorName` — never `require(condition, "string")`:

```solidity
error MyToken__InsufficientBalance(address user, uint256 needed, uint256 available);

if (balance < amount) revert MyToken__InsufficientBalance(msg.sender, amount, balance);
```

Custom errors are cheaper than strings, carry structured data, and are easier to test.

### Variables and Storage

- Don't initialize to default values: `uint256 x;` not `uint256 x = 0;`
- Prefer named return variables when they eliminate a local variable declaration
- Use `immutable` for values set once in the constructor (non-upgradeable contracts)
- Pack storage slots: group same-size variables together; put co-accessed variables in the same slot
- Cache storage reads — calling `sload` twice on the same slot is expensive; read once, assign to a local

### Gas Hygiene

- Prefer `calldata` over `memory` for read-only function inputs
- Don't cache `calldata` array length (`.length` on calldata is free)
- Don't copy entire structs from storage to memory if only a few fields are needed
- Enable the optimizer in `foundry.toml` (`optimizer = true`, `optimizer_runs = 200` or higher for frequently-called contracts)

### Access Control

- Prefer `Ownable2Step` over `Ownable` (two-step ownership transfer prevents accidents)
- Use `msg.sender` inside `onlyOwner` functions instead of reading the `owner` storage variable
- Put `nonReentrant` before other modifiers in the modifier list
- Prefer `ReentrancyGuardTransient` (EIP-1153) over `ReentrancyGuard` — same protection, cheaper gas
- For complex role systems, use `AccessControl` or `AccessManager` from OpenZeppelin

### NatSpec and Security Contact

```solidity
/**
 * @title MyProtocol
 * @notice Brief user-facing description
 * @dev Internal notes for developers
 * @custom:security-contact security@myprotocol.com
 */
```

### Pragma

- Strict versions for deployed contracts: `pragma solidity 0.8.26;`
- Floating for libraries, interfaces, abstract contracts, scripts, tests: `pragma solidity ^0.8.0;`

---

## Basic Security Patterns
### Reentrancy

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

Use `nonReentrant` on any function that sends ETH or calls an untrusted external contract.

### Integer Arithmetic

- Solidity 0.8+ overflow/underflow protection is on by default — don't disable it in production
- For fixed-point arithmetic, use `1e18` scaling or a battle-tested library (PRBMath, FixedPointMathLib)

For deeper vulnerability patterns (oracle manipulation, flash loans, signature replay, DoS,
upgradeable storage collisions), use the `solidity-security` skill.

---

## References

Load the relevant reference file only when the contract involves that topic:

- **Oracle / price feeds** → see [reference/oracle.md] 
- **Cross-chain / multi-chain / bridging** → see [reference/cross-chain.md] 
