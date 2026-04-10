# Code Maturity Assessment

9-category scorecard (Trail of Bits framework) for evaluating smart contract codebase readiness before an external audit or mainnet deployment. Score each category 1–5.

---

## Scorecard

### 1. Documentation
**Score**: _ / 5

- [ ] NatSpec (`@notice`, `@param`, `@return`) on all public/external functions
- [ ] System architecture documentation (diagrams, data flow)
- [ ] Deployment and initialization instructions
- [ ] Upgrade procedures documented (if upgradeable)
- [ ] Known limitations and trust assumptions documented

### 2. Testing
**Score**: _ / 5

- [ ] Unit test coverage > 80% (measured with `forge coverage`)
- [ ] Integration tests covering multi-contract interactions
- [ ] Fuzz tests for all critical arithmetic and state transitions
- [ ] Fork tests for mainnet integrations (oracles, external protocols)
- [ ] Invariant tests asserting core protocol properties

### 3. Code Quality
**Score**: _ / 5

- [ ] Consistent naming conventions (variables, functions, events, errors)
- [ ] Zero compiler warnings
- [ ] Follows [Solidity style guide](https://docs.soliditylang.org/en/latest/style-guide.html)
- [ ] Appropriate use of established libraries (OpenZeppelin, Solmate) over hand-rolled equivalents
- [ ] No dead code, commented-out blocks, or TODOs left in

### 4. Security Practices
**Score**: _ / 5

- [ ] Access control on all state-changing functions
- [ ] Reentrancy guards on external-call functions
- [ ] Solidity 0.8+ (overflow/underflow protection on by default)
- [ ] Input validation at all external entry points
- [ ] CEI pattern followed throughout
- [ ] No `tx.origin` for authentication

### 5. Architecture
**Score**: _ / 5

- [ ] Clear separation of concerns (no monolithic contracts doing everything)
- [ ] Upgradability decision made deliberately and documented
- [ ] Gas-efficient design (storage reads/writes minimized)
- [ ] Modular structure that limits blast radius of a bug

### 6. Dependencies
**Score**: _ / 5

- [ ] All dependency versions pinned (no floating `^` on security-critical libs)
- [ ] Audited dependencies preferred over unaudited ones
- [ ] Minimal external dependencies (each adds attack surface)
- [ ] Process in place to monitor for known vulnerabilities in dependencies

### 7. Deployment & Operations
**Score**: _ / 5

- [ ] Deployment scripts exist and are tested
- [ ] Privileged operations gated by multi-sig (never plain EOA on mainnet)
- [ ] Monitoring and alerting in place (events, on-chain anomaly detection)
- [ ] Emergency procedures defined (pause, withdraw, upgrade path)

### 8. Incident Response
**Score**: _ / 5

- [ ] Pause mechanism exists for critical functions
- [ ] Upgrade path defined and tested (if upgradeable)
- [ ] Bug bounty program active or planned
- [ ] Security contact in NatSpec and/or README

### 9. Audit History
**Score**: _ / 5

- [ ] Previous audits conducted (if applicable)
- [ ] All prior audit findings addressed and documented
- [ ] Continuous security review process (e.g. Slither in CI)

---

## Scoring Guide

| Range | Interpretation |
|---|---|
| 40–45 | Audit-ready. Minor polish may be needed. |
| 30–39 | Mostly ready. Address gaps before submitting. |
| 20–29 | Significant gaps. Prioritize improvements first. |
| < 20 | Not ready for audit. Fundamental work required. |

---

## Overall Score: __ / 45

## Priority Improvements

1. _(highest impact gap)_
2. _(second priority)_
3. _(third priority)_
