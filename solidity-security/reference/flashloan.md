# Flash Loan / Same-Block Manipulation

> Read this file when your contract has price-sensitive logic, handles deposits/withdrawals, or performs accounting using token balances.

## What Flash Loans Enable

A flash loan lets an attacker borrow any amount, execute arbitrary logic, and repay — all in one transaction. This means:

- **Token balances can be set to any value within one block**
- **AMM spot prices can be manipulated to any value and restored within one block**
- Any condition that can be satisfied by moving tokens or changing prices is attackable

## Vulnerable Patterns

### Balance-Based Accounting

```solidity
// VULNERABLE: attacker flash-loans tokens into this contract before calling
function deposit() external {
    uint256 shares = (msg.value * totalShares) / address(this).balance;
    // ...
}

// FIX: track balance internally
uint256 private _totalEthBalance;

function deposit() external payable {
    uint256 shares = (msg.value * totalShares) / _totalEthBalance;
    _totalEthBalance += msg.value;
    // ...
}
```

Never use `token.balanceOf(address(this))` or `address(this).balance` for share/price calculation. Use internal tracked balances instead.

### Spot Price Oracles

```solidity
// VULNERABLE: AMM spot price manipulable in same tx
function getPrice() external view returns (uint256) {
    (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
    return reserve1 * 1e18 / reserve0;
}
```

Use Chainlink price feeds or sufficiently-long TWAP instead. See [oracle.md](oracle.md) for validation patterns.

### Donation / Inflation Attacks

```solidity
// VULNERABLE: attacker donates tokens to inflate share price before first deposit
function deposit(uint256 amount) external {
    uint256 shares;
    if (totalSupply == 0) {
        shares = amount;
    } else {
        shares = amount * totalSupply / totalAssets(); // totalAssets includes donated tokens
    }
}

// FIX: use virtual shares (ERC-4626 standard offset)
uint256 constant VIRTUAL_SHARES = 1e3;
uint256 constant VIRTUAL_ASSETS = 1;

function convertToShares(uint256 assets) public view returns (uint256) {
    return (assets * (totalSupply + VIRTUAL_SHARES)) / (totalAssets() + VIRTUAL_ASSETS);
}
```

See [token-standards.md](token-standards.md) for the full ERC-4626 inflation attack.

## Defenses

| Threat | Defense |
|--------|---------|
| Balance manipulation | Use internal tracked balances, not `balanceOf` |
| Spot price manipulation | Use Chainlink or TWAP oracle |
| Share inflation (first deposit) | Virtual shares / dead shares / minimum deposit |
| Reentrancy within flash loan | CEI + `nonReentrant` |
| Atomic price move for liquidation | Add a delay (commit-reveal, or separate block for liquidation trigger) |

## Commit-Reveal for Liquidations

For high-value liquidations, consider separating the price snapshot from the liquidation execution:

1. **Commit phase**: record that an account is underwater (in a mapping) using the current oracle price
2. **Reveal phase**: execute the liquidation in a subsequent block, verifying the account is still underwater

This prevents an attacker from manipulating the oracle price and liquidating in the same transaction.

## Testing Flash Loan Resistance

```bash
# Fork test with a real flash loan provider
forge test --fork-url $MAINNET_RPC --match-test testFlashLoanAttack -vvv
```

Write invariant tests that assert:
- `totalShares * pricePerShare == totalAssets` always holds
- No single transaction can move share price by more than X%
