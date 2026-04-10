---
name: design-solidity
description: "Design Solidity smart contract systems before writing any implementation code. Use when asked to design a protocol, plan architecture, choose an upgrade strategy, select ERC standards, plan storage layout, or define access control roles. Triggers for: design a staking protocol, architecture for a DeFi vault, choose between UUPS and Transparent Proxy, plan storage slots for an upgradeable contract, threat model this system, write the interface first."
tags:
  - solidity
  - smart-contracts
  - architecture
  - design
  - evm
  - blockchain
---

# Solidity Contract Design

Architecture and design decisions before any implementation code is written. For code standards
see the `develop-solidity` skill. For security patterns see `solidity-security`.

---

## Interface-First Design

Write the interface before any implementation. The interface is the contract's public API and
the source of truth for what it does.

```solidity
// IMyProtocol.sol — define this first
interface IMyProtocol {
    event Deposited(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);

    error MyProtocol__InsufficientBalance(address user, uint256 requested, uint256 available);

    function deposit(uint256 amount) external;
    function withdraw(uint256 amount) external;
    function balanceOf(address user) external view returns (uint256);
}
```

Benefits: forces clarity on what the contract must do, enables parallel development of
tests and implementation, makes the ABI stable before internals are settled.

---

## ERC / EIP Standard Selection

| Use case | Standard | Notes |
|----------|----------|-------|
| Fungible token | ERC-20 | Extend via OZ `ERC20`; add `ERC20Permit` for gasless approvals |
| Non-fungible token | ERC-721 | `ERC721Enumerable` only if on-chain enumeration is required (expensive) |
| Semi-fungible (items with quantities) | ERC-1155 | Batch transfers; useful for gaming and multi-token protocols |
| Tokenized vault / yield-bearing token | ERC-4626 | Standardized deposit/withdraw/redeem interface |
| Diamond proxy / multi-facet | ERC-2535 | Only when contract size exceeds 24 KB limit and modular upgrade paths are required |
| Meta-transactions / gasless | ERC-2771 | Trusted forwarder pattern; check replay protection |
| Off-chain signatures | EIP-712 | Typed structured data; always include `chainId` and contract address in domain |

Default to the simplest standard that meets requirements. Avoid ERC-2535 unless contract
size genuinely forces it — the complexity cost is high.

---

## Upgrade Strategy

| Strategy | Proxy type | Best for |
|----------|------------|----------|
| No upgrade | None | Immutable protocols; maximally trustless |
| UUPS | `UUPSUpgradeable` | Most upgradeable contracts; upgrade logic in implementation |
| Transparent Proxy | `TransparentUpgradeableProxy` | Admin separation required; slightly higher gas |
| Beacon Proxy | `BeaconProxy` | Many instances of the same logic; upgrade all at once via beacon |

**Prefer UUPS over Transparent Proxy** for new projects — less deployment gas, cleaner pattern.

When using any proxy:
- All state lives in the proxy; the implementation is stateless
- Never use `constructor` for initialization — use `initialize()` with `initializer` modifier
- Storage layout is immutable across upgrades; only append new variables at the end
- Add `__gap` arrays in base contracts to reserve storage for future variables

---

## Storage Layout Planning

Storage slots are permanent. Plan them before writing any code.

```solidity
contract MyProtocolStorage {
    // Slot 0
    address public owner;         // 20 bytes
    bool public paused;           // 1 byte  } packed into slot 0
    uint96 public feeBps;         // 12 bytes }

    // Slot 1
    uint256 public totalDeposits; // 32 bytes — full slot

    // Slot 2+: mappings (slot determined by keccak256(key, slot_index))
    mapping(address => uint256) public balances;

    // Gap for upgradeable base contracts — reserve slots for future variables
    uint256[50] private __gap;
}
```

Rules:
- Pack small types together (address + bool + uint96 fit in one 32-byte slot)
- `mapping` and `array` values are stored at `keccak256(key ++ slot)` — the slot itself holds 0
- For upgradeable contracts, always end base contracts with `__gap`
- Never reorder existing variables in an upgradeable contract — only append

---

## Access Control Architecture

| Complexity | Pattern | When to use |
|------------|---------|-------------|
| Single admin | `Ownable2Step` | Simple protocols with one privileged role |
| Multiple roles | `AccessControl` | Distinct roles (MINTER, PAUSER, UPGRADER) |
| Role hierarchy with delegation | `AccessManager` (OZ v5) | Complex DAOs, multi-contract systems |

Define roles before writing any contract:

```
OWNER          — can upgrade, change critical parameters, set roles
OPERATOR       — can pause/unpause, trigger emergency actions
FEE_MANAGER    — can update fee rates (behind timelock)
```

Timelocks are mandatory for: fee rate changes, collateral ratio updates, oracle address changes,
and any parameter that affects user funds.

---

## Threat Modeling

Before writing any implementation, identify:

**Trust boundaries** — where does control cross from trusted to untrusted?
- User-supplied calldata
- External contract calls (oracles, tokens, callbacks)
- Off-chain inputs (signatures, merkle proofs)

**Privileged operations** — what can the admin do that users cannot?
- List every privileged function
- For each: what happens if the admin key is compromised?

**Invariants** — what must always be true?
- Write these as comments before implementation; later turn them into invariant tests
- Examples: `totalSupply == sum(balances)`, `collateral >= debt * ratio`

**Entry points** — every `external` and `public` function is an attack surface:
- Who can call it?
- What state does it modify?
- What external calls does it make?

---

## Design Output: SPEC.md Template

Before starting implementation, produce a brief spec:

```markdown
## Interfaces
- IMyProtocol: deposit, withdraw, balanceOf

## Roles
- OWNER: upgrade, set fee
- OPERATOR: pause/unpause

## Invariants
- contract ETH balance >= sum(user balances)
- only OWNER can call upgrade

## External dependencies
- Chainlink price feed (ETHUSD)
- ERC20 token (user-supplied — treat as untrusted)

## Upgrade strategy
- UUPS; upgrade gated by OWNER + 48h timelock
```

The spec is the checklist for implementation and the first input to the auditor.
