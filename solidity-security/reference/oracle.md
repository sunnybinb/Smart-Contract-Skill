# Oracle Security

> Deep-dive into oracle attack vectors. For correct integration patterns see the `develop-solidity` skill's `reference/oracle.md`.

---

## Attack Taxonomy

### 1. Spot Price Manipulation

AMM spot prices (`pool.slot0()`, `reserve0/reserve1`) reflect the current state of liquidity and can be moved by anyone within a single transaction via a large swap. Any contract that reads and acts on a spot price in the same transaction is vulnerable.

**Attack flow:**
1. Attacker flash-loans a large amount
2. Swaps to move the AMM price to an extreme
3. Calls your contract, which reads the manipulated price and misbehaves (e.g. borrows against inflated collateral)
4. Reverses the swap, repays the flash loan — all in one tx

**Mitigation:** Never use AMM spot prices. Use Chainlink Data Feeds or TWAP with a sufficiently long window.

---

### 2. TWAP Manipulation

Uniswap V3 TWAP is manipulation-resistant over long windows, but not immune:

- **Cost scales with window length**: manipulating a 1-hour TWAP requires holding the price off-market for 1 hour — expensive but not impossible for a well-capitalised attacker
- **Short windows (< 5 minutes)**: cheap to manipulate across a few blocks; never use windows shorter than 15–30 minutes for high-value decisions
- **Multi-block MEV**: post-merge, a validator controlling consecutive blocks can influence TWAP without paying swap fees by simply not including corrective trades

**Mitigation:**
- Use TWAP windows of at least 30 minutes for liquidations/minting
- Cross-validate TWAP against Chainlink — if they diverge by more than a threshold (e.g. 5%), revert or pause rather than trust either blindly

---

### 3. Chainlink Circuit Breaker / Stale Data

Chainlink feeds have a built-in circuit breaker: if the asset price moves outside a configured band (minAnswer / maxAnswer), the feed freezes at the boundary value rather than reporting the real price. During a LUNA-style collapse, Chainlink reported `minAnswer` while the real price was effectively zero.

**Detection pattern:**
```solidity
(uint80 roundId, int256 price, , uint256 updatedAt, uint80 answeredInRound) =
    priceFeed.latestRoundData();

// Price validity
if (price <= 0) revert Oracle__InvalidPrice();

// Staleness: compare against feed heartbeat (e.g. 3600s for ETH/USD on mainnet)
if (updatedAt < block.timestamp - MAX_STALENESS) revert Oracle__StalePrice();

// Incomplete round: answeredInRound < roundId means the oracle hasn't completed
if (answeredInRound < roundId) revert Oracle__IncompleteRound();
```

**Additional check — circuit breaker boundary:**
```solidity
// If your feed has known minAnswer/maxAnswer, compare:
int256 MIN_PRICE = 1e6; // feed-specific, check Chainlink docs
if (price <= MIN_PRICE) revert Oracle__PriceAtCircuitBreaker();
```

---

### 4. L2 Sequencer Uptime

On Arbitrum and Optimism, Chainlink Data Feeds are still pushed by the oracle network — but if the **L2 sequencer goes down**, the feed can appear "live" (not stale) while in reality no new prices are reaching the chain. After sequencer restart, prices are updated in bulk which can cause sudden price jumps.

**Mitigation — check sequencer liveness before reading prices:**
```solidity
// Chainlink provides a dedicated sequencer uptime feed per L2
// e.g. Arbitrum: 0xFdB631F5EE196F0ed6FAa767959853A9F217697D
AggregatorV2V3Interface sequencerFeed = AggregatorV2V3Interface(SEQUENCER_FEED);
(, int256 answer, uint256 startedAt,,) = sequencerFeed.latestRoundData();

// answer = 0 means sequencer is up; 1 means it's down
if (answer != 0) revert Oracle__SequencerDown();

// Grace period after restart: prices may be stale for up to GRACE_PERIOD seconds
uint256 GRACE_PERIOD = 3600;
if (block.timestamp - startedAt < GRACE_PERIOD) revert Oracle__SequencerGracePeriod();
```

---

### 5. Multi-Feed Precision Mismatch

When combining multiple Chainlink feeds (e.g. TOKEN/ETH × ETH/USD to get TOKEN/USD):

- Each feed has its own `decimals()` — do not assume they are the same
- Validate staleness on **each** feed independently
- Scale intermediate results before multiplying to avoid truncation

```solidity
// Wrong: assumes both feeds return 8 decimals
uint256 price = uint256(feedA.price) * uint256(feedB.price);

// Correct: normalise to a common precision first
uint256 priceA = uint256(feedA.price) * 10 ** (18 - feedA.decimals());
uint256 priceB = uint256(feedB.price) * 10 ** (18 - feedB.decimals());
uint256 combinedPrice = priceA * priceB / 1e18;
```

---

### 6. Pull Oracle Pitfalls (Pyth, Chronicle)

Pull oracles (Pyth, Chronicle) require the caller to submit a signed price update before reading. Unlike Chainlink (which pushes prices on-chain automatically), the price is only as fresh as the last submitted update.

**Common mistakes:**
- Reading `getPriceUnsafe()` without calling `updatePriceFeeds()` first → stale price silently accepted
- Not forwarding the required ETH fee to `updatePriceFeeds()` → call reverts or is silently no-op
- Caching the price across multiple function calls in the same block without re-validating

**Safe Pyth pattern:**
```solidity
function executeTrade(bytes[] calldata priceUpdateData) external payable {
    // 1. Update feeds — must happen before reading
    uint256 fee = pyth.getUpdateFee(priceUpdateData);
    pyth.updatePriceFeeds{value: fee}(priceUpdateData);

    // 2. Read and validate
    PythStructs.Price memory p = pyth.getPriceNoOlderThan(PRICE_ID, MAX_AGE);
    if (p.price <= 0) revert Oracle__InvalidPrice();
    // ...
}
```

---

## Defensive Strategies

### Commit-Reveal for High-Value Liquidations

Don't allow a liquidation to read an oracle price and execute in the same transaction — a searcher can time the transaction to land in the exact block where the price is momentarily favorable.

Pattern:
1. **Commit phase**: liquidator commits a hash of (target, price) off-chain
2. **Delay**: wait N blocks
3. **Reveal phase**: execute using the committed price — oracle price at reveal time must be within tolerance of the committed price

### Pause vs. Reject

When oracle data is invalid, choose the right response:
- **Reject** (`revert`): appropriate for individual transactions when the price is stale or out-of-bounds — caller can retry later
- **Pause** (emit event + disable protocol): appropriate when the oracle appears systematically broken (circuit breaker triggered, sequencer down) — prevents any transactions from proceeding until governance resolves it
- **Fallback oracle**: only if you have a secondary oracle of comparable quality and independent trust assumptions
