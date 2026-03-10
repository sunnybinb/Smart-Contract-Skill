# Cross-Chain / Multi-Chain Contracts

> Read this file when your contract bridges assets, sends messages cross-chain, or is deployed on multiple chains.

## Signatures and Hashed Data

- Include `chainId` in all signatures and hashed data — EIP-712 domain separator handles this automatically; verify it is configured correctly in the constructor
- If not using EIP-712, manually include `block.chainid` in the hash preimage
- Never reuse a signature valid on one chain on another — a missing chainId makes signatures portable across chains (replay attack)

## Addresses and Configuration

- Never hardcode chain-specific addresses (tokens, bridges, routers) — pass them as constructor params or store in an on-chain config map
- Document clearly which addresses differ per chain in NatSpec and deployment scripts
- Use a deployment script that reads per-chain config from a JSON file (`foundry.toml` `[profile.mainnet]` sections work well)

## State and Canonical Chain

- Be explicit in NatSpec about which chain holds canonical state for any shared data
- Avoid patterns where two chains can independently update the same logical state without synchronization

## Message Delivery Guarantees

- Cross-chain message ordering is **not guaranteed** — design for out-of-order and duplicate delivery
- Make receive handlers **idempotent**: use a `messageId → bool executed` mapping to reject duplicates
- Use nonces per sender when ordering matters; the bridge protocol alone does not enforce this

## Gas and Opcode Differences

Chains in the EVM ecosystem have meaningful differences — test on each target chain's fork:

| Chain | Notable Differences |
|-------|---------------------|
| Arbitrum | `block.number` returns L2 block (fast), `block.timestamp` from L1; `PUSH0` supported post-ArbOS 20 |
| Optimism / Base | `block.basefee` reflects L2 fee; `tx.origin` behaves differently in some deposit contexts |
| Polygon | Different gas token (MATIC/POL); faster block times affect staleness thresholds |
| zkSync Era | Some opcodes not supported; `msg.sender` in `constructor` differs for factory deployments |

Always run `forge test --fork-url <rpc>` against each target chain before deploying.

## Bridge-Specific Patterns

### LayerZero

```solidity
function lzReceive(
    uint16 srcChainId,
    bytes memory srcAddress,
    uint64 nonce,
    bytes memory payload
) external override {
    // ALWAYS validate caller is the LZ endpoint
    require(msg.sender == address(lzEndpoint), "not LZ endpoint");
    // ALWAYS validate source chain and trusted remote
    require(srcChainId == TRUSTED_CHAIN_ID, "untrusted chain");
    require(keccak256(srcAddress) == keccak256(trustedRemote), "untrusted remote");
    // ... handle payload
}
```

### Chainlink CCIP

```solidity
function _ccipReceive(Client.Any2EVMMessage memory message) internal override {
    // Validate source chain and sender
    require(message.sourceChainSelector == ALLOWED_SOURCE_CHAIN, "untrusted chain");
    address sender = abi.decode(message.sender, (address));
    require(sender == allowedSender, "untrusted sender");
    // ... handle message
}
```

### General Rule

Always validate **both** the source chain identifier **and** the source address/sender in receive hooks — the bridge only guarantees delivery, not authorization.

## Testing Cross-Chain Logic

- Use `vm.chainId(chainId)` in Foundry tests to simulate different chains
- Write fork tests for each target chain — `forge test --fork-url $ARB_RPC`
- Test the full message lifecycle: send on chain A → receive on chain B (use mock bridge contracts or the protocol's test helpers)
