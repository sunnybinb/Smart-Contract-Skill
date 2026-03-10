# Oracle Integration

> Read this file when your contract consumes price feeds or any external data source.

## Core Rules

- Never use AMM spot prices as oracles — trivially manipulated in a single transaction
- Use Chainlink `latestRoundData()` and validate **all** return values including staleness
- Use TWAP as a secondary sanity check for high-value operations

## Chainlink Validation Pattern

```solidity
(uint80 roundId, int256 price, , uint256 updatedAt, uint80 answeredInRound) =
    priceFeed.latestRoundData();

if (price <= 0) revert Oracle__InvalidPrice();
if (updatedAt < block.timestamp - MAX_STALENESS) revert Oracle__StalePrice();
if (answeredInRound < roundId) revert Oracle__IncompleteRound();
```

- `MAX_STALENESS` depends on the feed's heartbeat — check the Chainlink docs for each feed (e.g. ETH/USD on mainnet heartbeats every 3600s, use ~3900s as threshold)
- Always check `answeredInRound >= roundId` — a completed round where this fails means the oracle circuit-breaker tripped

## Multi-Feed Aggregation

When combining multiple feeds (e.g. TOKEN/ETH × ETH/USD):

- Validate each feed independently
- Apply staleness checks to **each** feed separately
- Be aware of precision differences — feeds use different decimals (`decimals()` call)

## TWAP as Secondary Check

For high-value operations, cross-validate Chainlink price against a Uniswap V3 TWAP:

```solidity
// If prices diverge by more than 5%, revert
uint256 chainlinkPrice = getChainlinkPrice();
uint256 twapPrice = getTwapPrice(TWAP_PERIOD);
uint256 diff = chainlinkPrice > twapPrice
    ? chainlinkPrice - twapPrice
    : twapPrice - chainlinkPrice;
if (diff * 100 / chainlinkPrice > MAX_PRICE_DIVERGENCE_PCT) revert Oracle__PriceDivergence();
```

## Push vs Pull Oracles

- **Push** (Chainlink Data Feeds): updated on-chain by the oracle network — read `latestRoundData()`
- **Pull** (Pyth, Chronicle): price data is published off-chain, caller must submit a signed price update — remember to call `updatePriceFeeds()` before reading, and pass the required ETH fee

## Security Notes

- For deeper oracle attack patterns (price manipulation, sandwiching, TWAP manipulation) see the `solidity-security` skill
