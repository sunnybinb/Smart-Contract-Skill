# Smart Contract Skills for Claude Code

Four specialized [Claude Code](https://claude.ai/code) skills covering the full Solidity development lifecycle:

| Skill | Trigger | Purpose |
|-------|---------|---------|
| `design-solidity` | "design a staking protocol", "choose an upgrade strategy" | Architecture, interface-first design, ERC selection, storage layout, threat modeling |
| `develop-solidity` | "write an ERC20", "add pausability to this contract" | Code standards, OpenZeppelin library-first patterns, gas hygiene, access control |
| `solidity-security` | "audit this contract", "security review", "find vulnerabilities" | Reentrancy, oracle manipulation, flash loans, signature replay, DoS, upgradeable storage |
| `solidity-test` | "write tests for this contract", "add fuzz testing" | Foundry unit/fuzz/invariant/fork tests, Branching Tree Technique, Chimera multi-fuzzer |

Each skill loads only when relevant and references companion files for deep detail, keeping
the main context lean.

## Installation

### Quick install (recommended)

```bash
git clone https://github.com/sunnybinb/Smart-Contract-Skill
cd Smart-Contract-Skill
./install.sh
```

Restart Claude Code. The skills are available globally across all your projects.

### Project-only install

```bash
./install.sh --local
```

Installs into `.claude/skills/` in the current working directory.

### Manual install

Copy or symlink any skill directory into `~/.claude/skills/`:

```bash
ln -s /path/to/Smart-Contract-Skill/solidity-security ~/.claude/skills/solidity-security
```

## Skills overview

### `design-solidity`

Covers the design phase before writing any code: interface-first design, ERC/EIP standard
selection, upgrade strategy (UUPS vs Transparent Proxy vs Beacon), storage slot planning,
access control architecture, and threat modeling.

### `develop-solidity`

Production Solidity code standards: OpenZeppelin library-first, file/contract layout, named
imports, custom errors, storage packing, gas hygiene. Includes cross-chain and oracle reference
files. Pairs with `solidity-security` for vulnerability patterns.

### `solidity-security`

Security vulnerability patterns for contract hardening and pre-audit review: reentrancy (CEI,
`nonReentrant`, read-only reentrancy), integer arithmetic, access control, DoS, timestamp
dependence, static analysis with Slither. Reference files for token standards, oracle safety,
flash loans, signatures, upgradeable contracts, and multi-chain deployment.

### `solidity-test`

Foundry test strategy: Branching Tree Technique with Bulloak scaffolding, unit/fuzz/invariant/
fork test patterns, handler contracts with ghost variables, Chimera multi-fuzzer setup, coverage
with `forge coverage`.

## Updates

```bash
cd Smart-Contract-Skill
git pull
```

Skills are loaded via symlinks so updates are immediate — no reinstall needed.
