---
name: solidity-test
description: "Write tests for Solidity smart contracts using Foundry. Use when writing unit tests, fuzz tests, invariant tests, or fork tests, setting up a Foundry test suite, applying the Branching Tree Technique, integrating Chimera for multi-fuzzer testing, or measuring test coverage. Also triggers for: write a test for this contract, add fuzz testing, set up invariant testing, improve test coverage."
tags:
  - solidity
  - smart-contracts
  - foundry
  - testing
  - fuzz
  - invariant
  - coverage
---

# Solidity Testing with Foundry

Test strategy and patterns for production smart contracts. For contract code standards see
the `develop-solidity` skill. For security vulnerability patterns see the `solidity-security` skill.

---

## Philosophy

Write tests alongside the contract — not after. Tests are the first line of defense against
regressions during refactors and upgrades. Prefer tests that explore the full input space over
tests that cherry-pick specific values.

---

## Test Types and When to Use Each

| Type | Prefix | Purpose |
|------|--------|---------|
| Unit | `test_` | Verify specific behavior with concrete inputs |
| Fuzz | `testFuzz_` | Explore edge cases across randomized input space |
| Invariant | (handler-based) | Assert properties that must hold across any call sequence |
| Fork | `testFork_` | Test against live mainnet state — oracles, upgrades, integrations |

**Fuzz over unit** wherever possible — let the fuzzer find the edge cases you wouldn't think to write.

**Invariant tests** for core protocol properties: things that must always be true regardless of
who calls what in what order. Examples: total supply equals sum of balances, protocol is always solvent.

**Fork tests** are mandatory for oracle integrations and upgrade paths — test against the actual
on-chain state, not mocked values.

---

## Directory Structure

```
test/
  unit/          # concrete-input tests for individual functions
  fuzz/          # property-based tests with randomized inputs
  invariant/     # stateful invariant suites with handlers
  fork/          # mainnet-fork integration tests
  helpers/       # shared setup, fixtures, mocks
```

---

## Branching Tree Technique (BTT)

Structure unit and fuzz tests as a decision tree. For each function, enumerate all branches:

```
withdraw()
├── when paused
│   └── it reverts
└── when not paused
    ├── when balance insufficient
    │   └── it reverts with Vault__InsufficientBalance
    └── when balance sufficient
        ├── it decrements the user balance
        ├── it transfers ETH to the user
        └── it emits Withdrawn event
```

Each leaf becomes one test case. This ensures complete branch coverage and makes it immediately
obvious which scenarios are missing tests.

Use [Bulloak](https://github.com/alexfertel/bulloak) to generate Foundry test scaffolding from
`.tree` files automatically.

---

## Foundry Fuzz Configuration

In `foundry.toml`:

```toml
[fuzz]
runs = 10000          # minimum for meaningful coverage; increase for critical paths
seed = "0x1"          # reproducible runs in CI

[invariant]
runs = 500            # each run is a full call sequence
depth = 100           # calls per run
fail_on_revert = false  # allow reverts in handlers; only assert on invariant violations
```

---

## Invariant Test Pattern

Use a **handler contract** to constrain the fuzzer to valid call sequences:

```solidity
contract VaultHandler is CommonBase, StdCheats, StdUtils {
    Vault internal vault;
    uint256 public ghost_depositSum;

    function deposit(uint256 amount) public {
        amount = bound(amount, 1, 100 ether);
        deal(address(this), amount);
        vault.deposit{value: amount}();
        ghost_depositSum += amount;
    }

    function withdraw(uint256 amount) public {
        amount = bound(amount, 0, vault.balanceOf(address(this)));
        vault.withdraw(amount);
        ghost_depositSum -= amount;
    }
}

contract VaultInvariantTest is Test {
    VaultHandler handler;
    Vault vault;

    function setUp() public {
        vault = new Vault();
        handler = new VaultHandler(vault);
        targetContract(address(handler));
    }

    // Invariant: contract ETH balance always equals tracked deposits
    function invariant_balanceMatchesDeposits() public view {
        assertEq(address(vault).balance, handler.ghost_depositSum());
    }
}
```

Ghost variables (like `ghost_depositSum`) track protocol state in the handler to compare against
contract state in invariant assertions.

---

## Fork Tests

```solidity
contract MyForkTest is Test {
    uint256 forkId;

    function setUp() public {
        forkId = vm.createFork(vm.envString("ETH_RPC_URL"), BLOCK_NUMBER);
        vm.selectFork(forkId);
    }

    function test_oraclePriceIsValid() public {
        // test against real Chainlink feed
    }
}
```

Pin to a specific block number for reproducible CI runs. Use `vm.createSelectFork` for a single fork.

---

## Chimera: Multi-Fuzzer Integration

[Chimera](https://github.com/Recon-Fuzz/chimera) allows the same handler-based invariant suite to
run across multiple fuzzers (Echidna, Medusa, Foundry) without rewriting tests.

Structure:
- `CryticToFoundry.sol` — Foundry entry point, inherits from the shared suite
- `CryticTester.sol` — Echidna/Medusa entry point, same suite

This maximizes coverage: Foundry's fuzzer is fast; Echidna/Medusa explore different state paths.
Use Chimera for high-value protocol components where thoroughness matters most.

---

## Coverage

```bash
forge coverage --report lcov
genhtml lcov.info -o coverage/
```

Aim for 100% line and branch coverage on core logic. Coverage gaps in security-critical paths
(withdrawal logic, access control, invariant-breaking scenarios) are audit findings.

Use `// forge-coverage-ignore` sparingly and only for unreachable defensive branches.

---

## Deployment Script Reuse

Share a base `Setup` between tests and deployment scripts so the same initialization path runs
in both environments:

```solidity
abstract contract BaseScript is Script {
    function _deployCore() internal returns (MyProtocol protocol) {
        protocol = new MyProtocol(...);
    }
}

contract Deploy is BaseScript { ... }
contract MyProtocolTest is Test, BaseScript { ... }
```

[Example pattern](https://github.com/rheo-xyz/very-liquid-vaults/blob/main/test/Setup.t.sol)
