# Solidity Engineering Skills 规划

## Context

用户希望建立覆盖 Solidity 工程完整生命周期的 skill 集合：Design → Develop → Test → Audit。
当前项目状态：
- `develop-solidity-contracts/SKILL.md` — 已存在，内容较全面（含 testing 和 security 章节）
- `solidity-test/` — 空目录（占位符）
- `solidity-security/` — 空目录（占位符）
- `pashov-skills/solidity-auditor/SKILL.md` — 第三方完整 audit orchestrator

---

## 规划方案：4 个专注 Skill

### Skill 1: `design-solidity-contracts` (新建)

**目录：** `design-solidity-contracts/SKILL.md`

**触发场景：** 用户需要规划协议架构、写接口、选择 ERC 标准、决定升级策略、做威胁建模时

**核心内容：**
- 接口先行（Interface-First Design）：先写 `IMyProtocol.sol`，再实现
- ERC/EIP 标准选型（ERC20/ERC721/ERC4626/ERC2535 等适用场景）
- 升级策略选择：无升级 vs UUPS vs Transparent Proxy vs Beacon Proxy
- 存储布局规划（slots 规划，避免 upgrade 碰撞）
- 访问控制架构（Ownable2Step / AccessControl / AccessManager 的选型）
- 依赖关系图 / 系统边界图（文字 ASCII 描述）
- 威胁建模：识别信任边界、外部调用点、特权操作
- 产出物：`SPEC.md` 模板（接口清单 + 不变量列表 + 角色列表）

---

### Skill 2: `develop-solidity-contracts` (完善现有)

**目录：** `develop-solidity-contracts/SKILL.md` — 已存在，内容基本完整

**调整方向：**
- 保留核心：代码规范、OZ 库优先、Gas 优化、安全模式
- 精简 Testing 章节（指向 test-solidity-contracts skill）
- 精简 CI/Audit 章节（指向 audit-solidity-contracts skill）
- 聚焦实现阶段的职责

---

### Skill 3: `test-solidity-contracts` (填充空目录)

**目录：** `solidity-test/SKILL.md`

**触发场景：** 用户需要为合约写测试、设计测试策略、运行 fuzz/invariant 测试时

**核心内容：**
- **Branching Tree Technique (BTT)**：用 `.tree` 文件规划所有执行路径，`bulloak` 工具自动生成测试骨架
- **单元测试**：modifier-based setup, 命名规范 `test_Method_WhenCondition`
- **Fuzz 测试**：`vm.assume` 使用原则，bound 技巧，减少 reject rate
- **不变量测试**：Handler 合约模式，Chimera 框架（同时跑 Foundry + Echidna + Medusa）
- **Fork 测试**：oracle sanity、升级路径验证、主网 state 测试
- **覆盖率**：`forge coverage`，关注 branch coverage 而非 line coverage
- **测试组织**：`test/unit/`, `test/fuzz/`, `test/invariant/`, `test/fork/`
- **工具链命令**：`forge test --fuzz-runs 10000`, `echidna`, `medusa`

---

### Skill 4: `audit-solidity-contracts` (填充空目录)

**目录：** `solidity-security/SKILL.md`

**触发场景：** 用户准备进行安全自查、送审前检查、或使用静态分析工具时

**与 pashov-skills 的区别：**
- pashov's `solidity-auditor`：面向审计员的全流程 orchestrator（并行 agents 扫描）
- 本 skill：面向**开发者**的送审前自查清单 + 静态分析工具使用指南

**核心内容：**
- **静态分析**：`slither .`, `aderyn .` — 如何读输出、哪些 findings 重要
- **手动检查清单（分类）：**
  - 访问控制：特权函数、initialize 保护、时间锁
  - 重入：CEI 检查、nonReentrant 覆盖
  - 算术：unchecked 块审查、精度损失
  - Oracle：价格来源、staleness 检查、TWAP
  - 闪电贷/同块操纵：余额追踪、原子操作
  - 签名：EIP-712、nonce、chainId、replay
  - DoS：无界循环、push-over-pull
  - 升级：storage gap、_authorizeUpgrade 保护
- **Halmos/Certora**：形式验证入门（何时值得使用）
- **送审前 checklist**：代码冻结、文档完整性、NatSpec、部署脚本审查

---

## 文件结构

```
smart-contract-skills/
├── design-solidity-contracts/   ← 新建
│   └── SKILL.md
├── develop-solidity-contracts/  ← 已存在，可微调
│   └── SKILL.md
├── solidity-test/               ← 填充
│   └── SKILL.md
├── solidity-security/           ← 填充
│   └── SKILL.md
└── pashov-skills/               ← 保持不变
    └── solidity-auditor/
        └── SKILL.md
```

## 实施顺序

1. `design-solidity-contracts/SKILL.md` — 全新，优先级最高（目前完全缺失）
2. `solidity-test/SKILL.md` — 全新，填充空目录
3. `solidity-security/SKILL.md` — 全新，开发者视角的 audit 清单
4. `develop-solidity-contracts/SKILL.md` — 微调（精简测试/审计章节，保持聚焦）

## 验证方式

- 每个 SKILL.md 创建后，用对应触发词测试：例如"design a staking protocol", "write tests for ERC20", "security review this contract"
- 确认 skill 触发正确，内容不重叠，各自聚焦自身生命周期阶段
