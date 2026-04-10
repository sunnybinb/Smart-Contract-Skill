# Upgradeable Contracts

> Read this file when the contract uses a proxy pattern (UUPS, Transparent, Beacon) or when performing an upgrade to an existing deployment.
>
> **Storage layout rules (§ below) only apply when two versions of a contract are being compared — skip this section when reviewing a single contract in isolation.**

## Storage Layout Rules

Storage slots are assigned by position — the EVM doesn't use variable names. Breaking the layout corrupts all state.

**Never:**
- Insert new variables before existing ones
- Remove existing variables
- Change a variable's type
- Insert new base contracts mid-inheritance chain (base contract storage comes first)

**Always:** append new variables at the end; reduce `__gap` by 1 for each slot consumed.

```solidity
// V1
contract MyProtocol is Initializable, OwnableUpgradeable {
    uint256 public fee;       // slot 0
    address public treasury;  // slot 1
    uint256[48] private __gap;
}

// V2 — BROKEN: inserted variable before treasury → treasury now reads garbage
contract MyProtocol is Initializable, OwnableUpgradeable {
    uint256 public fee;
    address public newAdmin;  // slot 1 — shifted treasury!
    address public treasury;  // slot 2 — wrong
    uint256[48] private __gap;
}

// V2 — SAFE: append only, reduce gap by 1
contract MyProtocol is Initializable, OwnableUpgradeable {
    uint256 public fee;
    address public treasury;
    uint256 public feeRecipientShare; // new — appended at end
    uint256[47] private __gap;        // was [48]
}
```

### Storage Gaps

Add a gap in every **base** contract (not leaf contracts) so future versions can add state without collision:

```solidity
abstract contract BaseProtocol is Initializable {
    uint256 public someVar;
    uint256[49] private __gap; // 50 slots total in this contract
}
```

## Initialization

Variable initializers at the declaration site are **not executed** through a proxy — the constructor runs on the implementation, not the proxy:

```solidity
// BROKEN: foo is never set to 42 when accessed through the proxy
uint256 public foo = 42;

// FIX: set in initialize()
uint256 public foo;

function initialize() external initializer {
    foo = 42;
    __Ownable_init(msg.sender);
}
```

- Call `_disableInitializers()` in the **implementation constructor** to prevent direct initialization of the implementation contract
- Call all parent `__init` functions — missing one leaves that parent's state broken

```solidity
constructor() {
    _disableInitializers();
}

function initialize(address admin) external initializer {
    __Ownable_init(admin);
    __ReentrancyGuard_init();  // required if using ReentrancyGuardUpgradeable
    __Pausable_init();         // required if using PausableUpgradeable
}
```

## Protecting UUPS Upgrade

```solidity
function _authorizeUpgrade(address newImplementation)
    internal
    override
    onlyOwner  // REQUIRED — unprotected = anyone can upgrade
{}
```
