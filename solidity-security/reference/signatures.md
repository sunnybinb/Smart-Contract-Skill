# Signature Safety

> Read this file when your contract validates off-chain signatures, uses permit patterns, or implements gasless meta-transactions.

## EIP-712 Implementation Template

Use OpenZeppelin's `EIP712` + `ECDSA` — never hand-roll signature hashing:

```solidity
import {EIP712} from "openzeppelin-contracts/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import {SignatureChecker} from "openzeppelin-contracts/contracts/utils/cryptography/SignatureChecker.sol";

contract MyProtocol is EIP712 {
    bytes32 private constant PERMIT_TYPEHASH = keccak256(
        "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
    );

    mapping(address => uint256) public nonces;

    constructor() EIP712("MyProtocol", "1") {}

    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        bytes calldata signature
    ) external {
        if (block.timestamp > deadline) revert Permit__Expired();

        bytes32 structHash = keccak256(abi.encode(
            PERMIT_TYPEHASH,
            owner,
            spender,
            value,
            nonces[owner]++, // increment AFTER use to prevent replay
            deadline
        ));

        bytes32 digest = _hashTypedDataV4(structHash); // includes chainId + contract address

        // SignatureChecker supports both EOA (ecrecover) and ERC-1271 (smart wallets)
        if (!SignatureChecker.isValidSignatureNow(owner, digest, signature))
            revert Permit__InvalidSignature();
    }
}
```

## Replay Attack Taxonomy

| Attack Type | Missing Protection | Fix |
|-------------|-------------------|-----|
| Same-chain replay | No nonce | Invalidate nonce after use |
| Cross-chain replay | No chainId | EIP-712 domain separator includes chainId |
| Cross-contract replay | No contract address | EIP-712 domain includes `verifyingContract` |
| Signature recycling | No deadline | Include `deadline` in struct hash |
| Front-run replay | Nonce not invalidated before external call | Increment nonce before any state change (CEI) |

## Domain Separator

EIP-712's `_hashTypedDataV4` builds the domain separator from:
- `name`: protocol name
- `version`: version string
- `chainId`: `block.chainid` — automatically prevents cross-chain replay
- `verifyingContract`: `address(this)` — prevents replay against other contracts with the same interface

Verify the domain separator is computed in the **constructor** (or lazily with chain ID check), not hardcoded — if chain ID changes (e.g. fork), the hardcoded value is stale.

## Signature Malleability

`ecrecover` accepts two valid `(v, r, s)` pairs for the same message. ECDSA.recover from OpenZeppelin v4.7.3+ rejects malleable signatures (high-s values). Do not use raw `ecrecover` directly.

```solidity
// VULNERABLE: raw ecrecover accepts malleable signatures
address signer = ecrecover(digest, v, r, s);

// SAFE: OZ ECDSA rejects malleable signatures
address signer = ECDSA.recover(digest, signature);
if (signer == address(0)) revert Sig__Invalid();
```

## Smart Wallet Support (ERC-1271)

EOA signatures use `ecrecover`. Contract wallets (Gnosis Safe, Argent, Coinbase Smart Wallet) use `isValidSignature(bytes32, bytes)` from ERC-1271. A pure `ecrecover` check silently fails for contract signers — the recovered address won't match the contract address.

```solidity
// BROKEN for smart wallets
address signer = ECDSA.recover(digest, sig);
require(signer == expectedOwner); // fails for contract wallets

// SAFE: supports both EOA and ERC-1271
require(SignatureChecker.isValidSignatureNow(expectedOwner, digest, sig));
```

## Nonce Patterns

**Per-account sequential nonce** (ERC-20 permit style):
- Simple; replay protection guarantees ordering
- Downside: multiple pending signatures from the same account conflict

```solidity
mapping(address => uint256) public nonces;
// use: nonces[signer]++
```

**Unordered nonces** (permit2 style):
- Multiple signatures can be valid simultaneously
- Use a bitmap: `mapping(address => mapping(uint256 => uint256)) usedNonces`

```solidity
function _useNonce(address owner, uint256 nonce) internal {
    uint256 wordPos = nonce >> 8;   // nonce / 256
    uint256 bitPos  = nonce & 0xff; // nonce % 256
    uint256 bit = 1 << bitPos;
    uint256 prev = usedNonces[owner][wordPos];
    if (prev & bit != 0) revert Nonce__AlreadyUsed();
    usedNonces[owner][wordPos] = prev | bit;
}
```

## Deadline Enforcement

Always include and check a deadline:

```solidity
if (block.timestamp > deadline) revert Permit__Expired();
```

Without a deadline, a valid signature can be held and submitted at any future time (e.g. after the user has revoked intent but the signature is still technically valid).

## Common Mistakes

- **`abi.encodePacked` with dynamic types**: two different structs can produce the same packed bytes — always use `abi.encode` for struct hashes
- **Forgetting `++nonce` before external calls**: if the function makes an external call before invalidating the nonce, a reentrant call can reuse the same signature
- **Validating signature but not the intended recipient**: check that the signer authorized THIS specific action, not just "signed something valid"
