# Token Integration Safety

Safe patterns for integrating ERC20 (and other token standards) into smart contracts.

---

## Always Use SafeERC20

Non-standard tokens (USDT, BNB, others) do not return `bool` on `transfer`/`transferFrom` — calling them directly will revert on ABI decode. Use OpenZeppelin's `SafeERC20`:

```solidity
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

using SafeERC20 for IERC20;

// ✅ Safe — handles missing return value
token.safeTransfer(recipient, amount);
token.safeTransferFrom(sender, recipient, amount);

// ❌ Dangerous — will revert on tokens that return nothing
token.transfer(recipient, amount);
```

---

## Fee-on-Transfer Tokens

Some tokens (e.g. PAXG, older STA) deduct a fee on every transfer. The received amount is less than the sent amount. Never rely on the `amount` argument — always measure the actual balance delta:

```solidity
// ✅ Correct
uint256 before = token.balanceOf(address(this));
token.safeTransferFrom(msg.sender, address(this), amount);
uint256 received = token.balanceOf(address(this)) - before;
// use `received`, not `amount`

// ❌ Wrong — over-credits the user if token has fees
balances[msg.sender] += amount;
```

---

## Rebasing / Elastic Supply Tokens

Tokens like stETH, AMPL, and aTokens change user balances externally without emitting `Transfer` events. Using raw `balanceOf` for share accounting breaks when the token rebases:

- Use share-based accounting (e.g. wrap rebasing tokens into a non-rebasing wrapper before accepting them)
- Or explicitly document that the protocol does not support rebasing tokens and add a check/denylist

---

## Pausable and Blocklist Tokens

Tokens like USDC, USDT, and many bridged assets can:
- **Pause all transfers** (e.g. emergency stop)
- **Blocklist specific addresses** (e.g. OFAC compliance)

A transfer to or from a blocked address will revert. Design your protocol to handle these gracefully:
- Don't assume transfers always succeed even with `safeTransfer`
- Provide an escape hatch for stuck funds if a token gets paused mid-operation

---

## Flash-Mintable Tokens

Tokens with a flash mint function can have their `totalSupply` temporarily inflated to an arbitrary value within one transaction. Don't use `totalSupply()` as a reliable bound intra-transaction for security decisions.

---

## ERC20 Conformity Checklist

When integrating a new token, verify it actually conforms to ERC20:

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

## Weird ERC20 Patterns Reference

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
