# Token Standards Security

> Security edge cases for ERC-20, ERC-721, ERC-1155, and ERC-4626.
> Use alongside the main `solidity-security` skill when your contract interacts with token contracts.

---

## ERC-20

### Non-Standard Return Values

The ERC-20 spec requires `transfer()` and `transferFrom()` to return a `bool`. Several widely-used tokens do not comply:

| Token | Issue |
|---|---|
| USDT (Ethereum) | `transfer()` returns nothing (void) |
| BNB | Returns `false` on failure instead of reverting |
| USDC (some versions) | Compliant, but version-dependent |

Calling `transfer()` directly and checking the return value will either revert (ABI decode failure) or silently succeed regardless of the actual outcome.

**Always use `SafeERC20` (OpenZeppelin) or `SafeTransferLib` (solmate):**
```solidity
// Wrong — will revert on USDT or silently succeed on BNB
bool ok = token.transfer(recipient, amount);

// Correct — wraps the call and handles missing return values
SafeERC20.safeTransfer(token, recipient, amount);
```

### solmate `SafeTransferLib` Contract Existence Caveat

Solmate's `SafeTransferLib` does **not** check whether the target address is a contract. If you call `safeTransfer(token, ...)` where `token` is an EOA or a non-existent address:
- The low-level call succeeds (empty code returns success)
- No tokens are transferred
- No revert occurs

**Use OpenZeppelin `SafeERC20`** when there is any uncertainty about whether the token address is a real ERC-20 contract. OpenZeppelin's version checks `address(token).code.length > 0` before calling.

### Fee-on-Transfer Tokens

Some tokens (e.g. PAXG, SAFEMOON, older REFLECT tokens) deduct a fee from each transfer. The recipient receives less than the `amount` argument:

```solidity
// Apparent: user deposited 100 tokens
token.safeTransferFrom(msg.sender, address(this), 100e18);

// Actual: contract received 98e18 (2% fee deducted)
// balances[msg.sender] += 100e18; // BUG: overstates the deposit
```

**Mitigation:** Measure the actual balance change:
```solidity
uint256 before = token.balanceOf(address(this));
token.safeTransferFrom(msg.sender, address(this), amount);
uint256 received = token.balanceOf(address(this)) - before;
balances[msg.sender] += received; // use actual received amount
```

### Rebasing Tokens

Rebasing tokens (e.g. stETH, AMPL, aTokens) change the balance of every holder at regular intervals without emitting `Transfer` events. A contract that stores `amount` deposited and expects to return exactly `amount` will encounter a mismatch:

- **Positive rebase** (stETH rewards): contract holds more tokens than accounted — yield is locked in the contract
- **Negative rebase** (slashing): contract holds fewer tokens — protocol is insolvent

**Mitigation:** Use share-based accounting rather than raw token amounts (e.g. wrap rebasing tokens into a non-rebasing wrapper before accepting them). Alternatively, explicitly document that rebasing tokens are not supported and add a check/denylist.

### Pausable and Blocklist Tokens

Tokens like USDC, USDT, and many bridged assets can:
- **Pause all transfers** (e.g. emergency stop)
- **Blocklist specific addresses** (e.g. OFAC compliance)

A transfer to or from a blocked address will revert even with `safeTransfer`. Design your protocol to handle these gracefully:
- Don't assume transfers always succeed even with `safeTransfer`
- Provide an escape hatch for stuck funds if a token gets paused mid-operation

### Flash-Mintable Tokens

Tokens with a flash mint function can have their `totalSupply` temporarily inflated to an arbitrary value within one transaction. Don't use `totalSupply()` as a reliable bound intra-transaction for security decisions.

### `approve` Race Condition

Replacing a non-zero allowance with another non-zero value in a single transaction can be front-run:

1. Alice approves Bob for 100 tokens
2. Alice sends tx to reduce allowance to 50
3. Bob front-runs and spends 100 (using the old allowance)
4. Alice's tx lands, setting allowance to 50
5. Bob spends 50 more — total: 150 instead of the intended 50

**Mitigation:**
```solidity
// Option 1: set to 0 first, then set new value (two transactions)
token.safeApprove(spender, 0);
token.safeApprove(spender, newAmount);

// Option 2: use increaseAllowance / decreaseAllowance
token.safeIncreaseAllowance(spender, additionalAmount);
```

### `from == to` in Transfer

If a protocol calls `transferFrom(alice, alice, amount)` — transferring from and to the same address — the behaviour depends on the token implementation:

- Most ERC-20s handle this correctly (balance unchanged, allowance consumed)
- Some implementations have bugs or unexpected behaviour in this edge case

Audit your protocol for any code path where `from` and `to` could be equal, especially in routing or swap logic, and ensure the outcome is intentional.

### Zero-Address Destination

`transfer(address(0), amount)` permanently burns tokens. Most modern ERC-20s revert on this, but non-standard tokens may not. If your contract computes the `to` address dynamically:

```solidity
// Always validate before transferring to a computed address
if (recipient == address(0)) revert Transfer__ZeroAddress();
token.safeTransfer(recipient, amount);
```

---

## ERC-20 Conformity Checklist

When integrating a new token, verify it actually conforms to ERC-20:

### Required Functions
- [ ] `totalSupply()` returns `uint256`
- [ ] `balanceOf(address)` returns `uint256`
- [ ] `transfer(address, uint256)` returns `bool`
- [ ] `transferFrom(address, address, uint256)` returns `bool`
- [ ] `approve(address, uint256)` returns `bool`
- [ ] `allowance(address, address)` returns `uint256`

### Required Events
- [ ] `Transfer(address indexed from, address indexed to, uint256 value)`
- [ ] `Approval(address indexed owner, address indexed spender, uint256 value)`

### Behavioral Checks
- [ ] `transfer(0)` does not revert — emits Transfer event with 0 value
- [ ] Self-transfers (`transfer(self, amount)`) do not revert or double-count
- [ ] `approve()` overwrites existing allowance without requiring reset to 0
- [ ] `transferFrom` reduces the allowance by the transferred amount

---

## Weird ERC-20 Patterns Reference

| Pattern | Risk | Detection |
|---|---|---|
| Fee-on-transfer | Balance accounting mismatch | Check balance before/after transfer |
| Rebasing / elastic supply | Share accounting breaks on rebase | Check for `rebase()` or `sync()` events |
| Pausable | Transfers can be blocked globally | Check for `pause()` / `unpause()` functions |
| Blocklist | Specific addresses cannot transfer | Check for address-based restriction functions |
| Multiple entry points | Proxy with multiple implementation paths | Check for multiple `transfer` codepaths |
| Missing return value | Silent failure on direct `.transfer()` call | Use SafeERC20 |
| Large approval reverting | Some tokens cap approval values | Test with `type(uint256).max` approve |
| Flash-mintable | `totalSupply` can spike intra-tx | Check for `flashMint()` function |

See also: [d-xo/weird-erc20](https://github.com/d-xo/weird-erc20) for a comprehensive list with test cases.

---

## ERC-721

### `safeTransferFrom` Triggers `onERC721Received`

`safeTransferFrom` calls `onERC721Received(operator, from, tokenId, data)` on the recipient if it is a contract. This is a **reentry point**:

```solidity
// Vulnerable: state not updated before safeTransferFrom
function sell(uint256 tokenId) external {
    nft.safeTransferFrom(address(this), msg.sender, tokenId); // triggers onERC721Received
    balances[msg.sender] -= price; // never reached if attacker reenters here
}

// Safe: CEI + nonReentrant
function sell(uint256 tokenId) external nonReentrant {
    balances[msg.sender] -= price;           // Effects first
    nft.safeTransferFrom(address(this), msg.sender, tokenId); // Interaction last
}
```

**Risk surface:**
- Any protocol that calls `safeTransferFrom` on an NFT must treat the recipient as an untrusted external contract
- The `onERC721Received` hook can call back into your contract with any function
- Apply CEI and `nonReentrant` before every `safeTransferFrom` call

**When to use `transferFrom` vs `safeTransferFrom`:**
- `transferFrom` skips the hook — safe from reentrancy, but the recipient may not be able to handle the NFT (locked forever if it's a contract without an NFT handler)
- `safeTransferFrom` is user-friendly but introduces reentrancy risk — always pair with CEI + guard

---

## ERC-1155

### `onERC1155Received` and `onERC1155BatchReceived`

ERC-1155 has two receiver hooks:
- `onERC1155Received`: called on single-token transfers
- `onERC1155BatchReceived`: called on batch transfers

Both are reentry vectors with the same risk profile as ERC-721's hook.

**Batch transfers amplify the attack surface:** a single `safeBatchTransferFrom` call can transfer multiple token IDs in one transaction. If your protocol processes each ID separately in a loop and the hook can reenter, an attacker can exploit mid-loop state inconsistencies.

**Pattern:** Apply CEI and `nonReentrant` to any function that calls `safeTransferFrom` or `safeBatchTransferFrom` on an ERC-1155 contract.

```solidity
function withdrawBatch(uint256[] calldata ids, uint256[] calldata amounts) external nonReentrant {
    // Effects: update all balances before any transfer
    for (uint256 i; i < ids.length; ++i) {
        balances[msg.sender][ids[i]] -= amounts[i];
    }
    // Interaction: one call after all state is updated
    nft1155.safeBatchTransferFrom(address(this), msg.sender, ids, amounts, "");
}
```

---

## ERC-4626 (Tokenised Vaults)

### Inflation Attack on First Deposit

A classic attack against naive ERC-4626 implementations:

1. Attacker deposits 1 wei → receives 1 share
2. Attacker donates a large amount directly to the vault (bypasses `deposit()`)
3. First real user deposits 1000 tokens → share price is now huge → user receives 0 shares (rounds down to 0)
4. Attacker redeems their 1 share and receives the entire vault balance

**Mitigation — virtual shares (OpenZeppelin v5 approach):**
```solidity
// _decimalsOffset() adds virtual shares/assets to prevent first-deposit manipulation
// OpenZeppelin's ERC4626 implementation uses this pattern
function _decimalsOffset() internal view virtual override returns (uint8) {
    return 3; // 1000x virtual shares buffer
}
```

**Alternative:** seed the vault with a small initial deposit in the constructor and burn those shares (make them unwithdrawable) so the share price is non-trivially manipulable from the start.

### Rounding Direction

ERC-4626 specifies rounding rules:
- `deposit` / `mint`: round **down** in favour of the vault (users receive slightly fewer shares)
- `withdraw` / `redeem`: round **up** in favour of the vault (users must burn slightly more shares)

Incorrect rounding direction allows users to extract value from the vault over many small transactions (rounding dust accumulation attack). Use OpenZeppelin's ERC-4626 implementation which handles this correctly.

### `maxWithdraw` and `maxRedeem` Must Respect Limits

If your vault has withdrawal limits (e.g. a lending protocol with utilisation), `maxWithdraw()` must return the actual withdrawable amount — not the user's full balance. Callers may rely on this to avoid reverts. Returning an incorrect (over-stated) value breaks integrators.
