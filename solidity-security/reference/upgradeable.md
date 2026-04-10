# Upgradeable Contracts

> Read this file when the contract uses a proxy pattern (UUPS, Transparent, Beacon) or when performing an upgrade to an existing deployment.

## Storage Layout Rules

Storage slots are assigned by position — the EVM doesn't use variable names. Breaking the layout corrupts all state.

### Never Do These

```solidity
// V1
contract MyProtocol {
    uint256 public fee;       // slot 0
    address public treasury;  // slot 1
}

// V2 — BROKEN: inserted a new variable before existing ones
contract MyProtocol {
    uint256 public fee;       // slot 0
    address public newAdmin;  // slot 1 — shifted treasury to slot 2!
    address public treasury;  // slot 2 — now reads garbage
}

// V2 — BROKEN: removed a variable
contract MyProtocol {
    // fee removed — treasury now at slot 0, reads fee's value
    address public treasury;  // slot 0 — WRONG
}

// V2 — BROKEN: changed variable type
contract MyProtocol {
    uint128 public fee;       // slot 0 — only occupies half; other half is now "address public treasury"
    address public treasury;  // slot 0 (packed) — reads from wrong offset
}
```

### Safe Upgrade Pattern

- Only **append** new state variables at the bottom
- Never change types, order, or remove variables
- Never insert new base contracts mid-inheritance chain — base contract storage comes first

```solidity
// V1
contract MyProtocol is Initializable, OwnableUpgradeable {
    uint256 public fee;
    address public treasury;
    uint256[48] private __gap; // storage gap for future additions
}

// V2 — SAFE: append only
contract MyProtocol is Initializable, OwnableUpgradeable {
    uint256 public fee;
    address public treasury;
    // New variable added at the end
    uint256 public feeRecipientShare;
    uint256[47] private __gap; // reduced gap by 1
}
```

## Storage Gaps

Add a gap in every base contract so future versions can add state without collision:

```solidity
abstract contract BaseProtocol is Initializable {
    uint256 public someVar;
    // ...
    uint256[49] private __gap; // 50 slots total in this contract
}
```

When adding a new variable in `BaseProtocol`, reduce `__gap` by 1. Don't add the gap in leaf contracts (contracts not extended by others).

## Initialization

Variable initializers at the declaration site are **not executed** in upgradeable contracts deployed behind a proxy — the constructor runs on the implementation, not the proxy:

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
    _disableInitializers(); // prevent initialize() from being called on implementation
}

function initialize(address admin) external initializer {
    __Ownable_init(admin);        // required
    __ReentrancyGuard_init();     // required if using ReentrancyGuardUpgradeable
    __Pausable_init();            // required if using PausableUpgradeable
    // ... your init logic
}
```

## UUPS vs Transparent Proxy

| | UUPS | Transparent |
|-|------|-------------|
| Upgrade logic | In implementation | In proxy |
| Gas cost for users | Lower (no admin check on every call) | Higher |
| Risk | Must protect `_authorizeUpgrade` | Admin slot collision (handled by OZ) |
| Recommendation | Preferred for new contracts | Legacy; avoid for new deployments |

### Protecting UUPS Upgrade

```solidity
function _authorizeUpgrade(address newImplementation)
    internal
    override
    onlyOwner  // REQUIRED — unprotected = anyone can upgrade
{}
```

## Upgrade Testing Workflow

1. **Storage layout check**: use tooling before deploying

```bash
# Foundry
forge script script/Upgrade.s.sol --fork-url $RPC

# Hardhat
npx hardhat run scripts/upgrade.ts --network mainnet --dry-run
```

2. **Fork test the actual upgrade**

```solidity
function testUpgrade() public {
    vm.createSelectFork(vm.envString("MAINNET_RPC"));
    address proxy = 0x...; // real deployed proxy address
    MyProtocolV2 impl = new MyProtocolV2();
    
    vm.prank(owner);
    UUPSUpgradeable(proxy).upgradeToAndCall(address(impl), "");
    
    // Verify state preserved
    assertEq(MyProtocolV2(proxy).fee(), expectedFee);
    // Verify new functionality works
    MyProtocolV2(proxy).newFunction();
}
```

3. **Validate with OZ tools**

```bash
# hardhat-upgrades
npx hardhat run scripts/validate-upgrade.ts

# forge-upgrades (foundry plugin)
forge script script/ValidateUpgrade.s.sol
```

## New Base Contract in Inheritance Chain

```solidity
// V1
contract MyProtocol is Initializable, OwnableUpgradeable {
    uint256 public fee; // slot after OZ slots
}

// V2 — BROKEN: PausableUpgradeable inserted between Initializable and Ownable
// its storage slots now shift MyProtocol's fee variable
contract MyProtocol is Initializable, PausableUpgradeable, OwnableUpgradeable {
    uint256 public fee; // now at a different slot!
}

// V2 — SAFE: append new base at the end of the inheritance list
contract MyProtocol is Initializable, OwnableUpgradeable, PausableUpgradeable {
    uint256 public fee; // slot unchanged
}
```
