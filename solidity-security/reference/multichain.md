# Multi-chain Security

> Security considerations for contracts deployed across multiple chains or participating in cross-chain messaging.
> For cross-chain development patterns (LayerZero, CCIP) see the `develop-solidity` skill's `reference/cross-chain.md`.

---

## Token Decimal Differences

The same logical token can have different decimals on different chains. This is not a bug in the token — it is by design for bridged representations.

**Known examples:**

| Token | Ethereum | BSC | Orderly |
|---|---|---|---|
| USDC | 6 | 18 | 6 |
| USDT | 6 | 18 | 6 |

**Where this breaks:**
- Off-chain indexers that read event amounts from one chain and write them to a shared database without normalising decimals will produce incorrect balances on the other chain
- Contracts that hard-code a scaling factor (`/ 1e6`) will misbehave when deployed to a chain where that token uses 18 decimals
- Cross-chain bridges that read `amount` from a deposit event and mint 1:1 on the destination chain must normalise decimals in the bridging logic

**Mitigation:** Never hard-code decimal assumptions. Always call `token.decimals()` at runtime and normalise to a canonical internal precision (e.g. `1e18`) before any cross-chain comparison or calculation.

---

## Different Native Tokens Per Chain

`msg.value` carries the chain's native token — not ETH everywhere:

| Chain | Native Token | Notes |
|---|---|---|
| Ethereum | ETH | baseline |
| Polygon | MATIC (now POL) | different USD value |
| BSC | BNB | different USD value |
| Arbitrum | ETH | same as mainnet |
| Optimism / Base | ETH | same as mainnet |
| Avalanche C-Chain | AVAX | different USD value |

**Where this breaks:**
- A contract that collects `msg.value` as a USD-equivalent fee (e.g. "pay 0.01 ETH to use the protocol") has a wildly different real cost per chain
- Gas estimation done on one chain and used as a budget for a cross-chain call will be wrong if the destination chain has a different native token value
- `WETH` addresses differ per chain — hard-coding the Ethereum WETH address will fail or interact with the wrong contract on other chains

**Mitigation:** Use chain-specific configuration mappings for native token handling. Never assume 1 native token = any fixed USD value in contract logic.

---

## Hard-Coded Addresses

Many contracts hard-code addresses that are only valid on one chain:

**Common hard-coded addresses that differ per chain:**

| Contract | Ethereum | Arbitrum | Optimism |
|---|---|---|---|
| WETH | `0xC02aa...` | `0x82aF...` | `0x4200...` |
| USDC | `0xA0b8...` | `0xaf88...` | `0x0b2C...` |
| Chainlink ETH/USD | `0x5f4e...` | `0x639F...` | `0x13e3...` |
| CCIP Router | `0x80226...` | `0x141f...` | `0x3206...` |
| Uniswap V3 Factory | `0x1F98...` | `0x1F98...` | `0x1F98...` |

Note: some addresses are the same (Uniswap uses deterministic deployment), but many are not.

**Mitigation:**
- Store chain-specific addresses in a constructor parameter or immutable set at deployment time
- Use a configuration struct passed during initialisation
- Document explicitly which addresses are expected to differ per chain in your deployment scripts

---

## L2 Opcode and Block Variable Differences

EVM-compatible L2s are not identical to Ethereum L1 at the opcode level.

### `block.number`
- **Arbitrum**: `block.number` returns the L2 block number (changes every ~250ms), NOT the L1 block. Use `ArbSys(0x64).arbBlockNumber()` if you need the L1 block
- **Optimism / Base**: `block.number` returns the L2 block number, which tracks L1 loosely (one L2 block per L1 block historically, but this has changed with Bedrock)
- **Impact**: any time-lock or delay measured in block count will behave very differently on Arbitrum (blocks per second) vs Ethereum (blocks per ~12s)

### `block.timestamp`
- **Arbitrum**: sourced from L1 Ethereum — reliable but can be delayed when the sequencer lags
- **Optimism**: each L2 block has its own timestamp, set by the sequencer — can differ slightly from L1

### `PUSH0` opcode (EIP-3855)
- Available on Ethereum mainnet and most L2s post-upgrade
- **Not available** on older zkSync Era deployments, some early L2 versions, and some EVM-compatible sidechains
- Solidity 0.8.20+ uses `PUSH0` by default — contracts compiled with `>=0.8.20` may fail to deploy on chains that don't support it
- **Mitigation**: set `evmVersion = "paris"` in your compiler config if targeting chains without `PUSH0` support

### `SELFDESTRUCT`
- Deprecated in EIP-6049; behaviour changed post-Dencun (EIP-6780) — only empties balance if called in the same transaction as contract creation
- Some L2s may differ in their `SELFDESTRUCT` implementation

---

## Cross-Chain Signature Replay

A signature valid on one chain is valid on another if the domain separator doesn't include `block.chainid`.

**Vulnerable pattern:**
```solidity
// No chainId — same signature works on Ethereum and Arbitrum
bytes32 digest = keccak256(abi.encode(TYPEHASH, nonce, amount));
```

**Safe pattern (EIP-712):**
```solidity
// EIP-712 domain includes chainId automatically if constructed correctly
bytes32 domain = keccak256(abi.encode(
    DOMAIN_TYPEHASH,
    keccak256(bytes(name)),
    keccak256(bytes(version)),
    block.chainid,      // ← critical
    address(this)       // ← critical
));
```

If using OpenZeppelin's `EIP712` base contract, the domain separator is computed correctly as long as you pass the right name and version — `block.chainid` is included automatically.

---

## CREATE2 Address Collisions

CREATE2 produces the same address if `(deployer, salt, bytecodeHash)` are identical. Cross-chain this means:

- If your deployment script uses the same salt everywhere, contracts land at the same address on all chains — this is sometimes intentional (counterfactual addresses) but requires that **constructor arguments** are also identical
- If constructor args encode chain-specific state (e.g. a chain ID, a specific token address), the bytecodeHash differs and the address will differ — this can surprise tooling that assumes counterfactual addresses are universal
- An attacker who controls a chain's CREATE2 deployer can pre-deploy a malicious contract at the address your protocol expects — validate that deployed code matches expected bytecode before trusting a CREATE2 address

---

## Off-Chain Indexer Considerations

Cross-chain indexers that aggregate events from multiple chains are particularly vulnerable to decimal and native token confusion:

- An event `Deposit(user, amount)` emitted on BSC where USDC has 18 decimals vs the same event on Ethereum where USDC has 6 decimals — the raw `amount` values are incomparable without normalisation
- Indexers that sum amounts across chains for a "total TVL" figure without normalising will overcount BSC by 10^12
- Always normalise to a canonical unit (e.g. USD with 18 decimal precision) immediately when ingesting cross-chain events
