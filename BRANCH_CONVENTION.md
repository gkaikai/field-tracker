# Field Tracker 分支规范

> 版本: v1.0
> 最后更新: 2026-07-19

---

## 1. 分支命名规范

所有分支名使用小写字母，单词之间用连字符 (`-`) 或斜杠 (`/`) 分隔。

### 1.1 长期分支

| 分支名称 | 用途 | 保护级别 |
|---------|------|---------|
| `main` | 生产环境代码，仅通过合并进入 | 🔒 受保护，禁止直接推送 |
| `dev` | 日常开发集成分支，所有 feature 合入此处 | 🔒 受保护 |
| `test` | 测试环境分支，用于集成测试和验收 | 🔒 受保护 |

### 1.2 功能分支

用于开发新功能，从 `dev` 分支创建，合并回 `dev`。

```
feature/<功能简述>
```

**示例：**
- `feature/login-page` — 登录页面开发
- `feature/export-excel` — Excel 导出功能
- `feature/gps-optimization` — GPS 定位优化
- `feature/attendance-report` — 考勤报表模块

### 1.3 Bug 修复分支

用于修复 `dev` 或 `test` 分支上的非紧急 Bug，从 `dev` 分支创建，合并回 `dev`。

```
bugfix/<问题简述>
```

**示例：**
- `bugfix/login-crash` — 登录闪退修复
- `bugfix/wrong-clock-time` — 打卡时间显示错误修复
- `bugfix/null-pointer-attendance` — 考勤空指针异常修复

### 1.4 紧急修复分支

用于修复生产环境 (`main`) 的紧急问题，从 `main` 分支创建，修复后同时合并回 `main` 和 `dev`。

```
hotfix/<紧急问题简述>
```

**示例：**
- `hotfix/api-timeout` — 生产环境 API 超时修复
- `hotfix/auth-bypass` — 认证绕过安全漏洞修复
- `hotfix/data-loss-recovery` — 数据丢失恢复修复

### 1.5 发布分支

用于准备发版，从 `dev` 分支创建，测试通过后合并到 `main`。

```
release/<版本号>
```

**示例：**
- `release/v1.2.0`
- `release/v2.0.0-beta`

---

## 2. 分支合并流程

### 2.1 总览

```
feature/* ──→ dev ──→ test ──→ main
bugfix/*  ──→ dev ──→ test ──→ main
hotfix/*  ──────→ main ←──────┘
              ↘──→ dev
release/* ────→ test ──→ main
              └──→ dev (如有必要)
```

### 2.2 标准开发流程

```
1. 从 dev 创建功能分支
        git checkout dev
        git checkout -b feature/xxx

2. 在功能分支上开发、提交

3. 发起 Pull Request 合入 dev
        feature/xxx → dev

4. 通过 Code Review 后合并到 dev

5. dev 通过测试后，合并到 test
        dev → test

6. test 通过验收后，合并到 main
        test → main
```

### 2.3 紧急修复流程

```
1. 从 main 创建 hotfix 分支
        git checkout main
        git checkout -b hotfix/xxx

2. 修复并提交

3. 发起 Pull Request，同时合入 main 和 dev
        hotfix/xxx → main  (紧急上线)
        hotfix/xxx → dev   (同步修复)

4. 如果 hotfix 涉及的内容 dev 中已有变更，
   则需在 dev 分支上 cherry-pick 相关 commit
```

### 2.4 合并要求

| 步骤 | 合并方向 | 必须通过的检查 |
|------|---------|--------------|
| 功能开发 | `feature/*` → `dev` | Code Review + CI 通过 |
| 集成测试 | `dev` → `test` | 测试人员验收 |
| 发布上线 | `test` → `main` | 全部测试通过 + 产品验收 |
| 紧急修复 | `hotfix/*` → `main` | 紧急审核 + CI 通过 |
| 修复同步 | `hotfix/*` → `dev` | Code Review + CI 通过 |

### 2.5 禁止操作

- ❌ 禁止直接向 `main` 推送代码（除 hotfix 流程外）
- ❌ 禁止将 `feature` 分支直接合并到 `main` 或 `test`
- ❌ 禁止在合并前未通过 Code Review
- ❌ 禁止在 CI 失败的情况下强行合并
- ❌ 禁止将未完成的 `feature` 分支长期（超过 3 个工作日）不合并

---

## 3. 提交信息规范

### 3.1 格式

```
<type>(<scope>): <subject>

<body>

<footer>
```

### 3.2 Type 类型

| Type | 说明 | 示例 |
|------|------|------|
| `feat` | 新功能 | `feat(attendance): add clock-in reminder` |
| `fix` | Bug 修复 | `fix(login): resolve null pointer on empty account` |
| `hotfix` | 紧急修复 | `hotfix(api): fix production timeout issue` |
| `docs` | 文档变更 | `docs: update API documentation` |
| `style` | 代码格式（不影响功能） | `style: format code with Prettier` |
| `refactor` | 重构 | `refactor(gps): extract location service` |
| `perf` | 性能优化 | `perf(db): add index to attendance table` |
| `test` | 测试相关 | `test(export): add unit tests for Excel export` |
| `chore` | 构建/工具/依赖 | `chore: upgrade Flutter SDK to 3.22` |
| `ci` | CI 配置变更 | `ci: add automated testing workflow` |

### 3.3 Scope 范围

项目常用 scope：

| Scope | 对应模块 |
|-------|---------|
| `login` | 登录模块 |
| `attendance` | 考勤打卡 |
| `gps` | GPS 定位 |
| `export` | 数据导出 |
| `report` | 报表模块 |
| `api` | 后端 API |
| `db` | 数据库 |
| `ui` | 前端界面 |
| `config` | 配置管理 |

### 3.4 提交要求

1. **语言**: 推荐使用英文写 subject，保持团队统一；body 和 footer 可用中文
2. **subject**: 不超过 72 个字符，首字母小写，句末不加句号
3. **body**: 可选，说明变更动机和前后对比，每行不超过 72 字符
4. **footer**: 可选，标注 Breaking Changes 或关联 Issue
5. **一个 commit 只做一件事**：不要将不相关的改动混入同一提交

### 3.5 示例

```
feat(attendance): add geofence-based clock-in validation

Implement geofence radius checking for clock-in. Users must be within
200m of the designated location to clock in.

Closes #42
```

```
fix(login): handle network timeout gracefully

Show a user-friendly retry dialog instead of a blank screen when
the login request times out after 10 seconds.

Fixes #58
```

```
hotfix(api): fix data race in concurrent attendance submissions

Production incident 2026-07-18: concurrent clock-in requests caused
duplicate records. Added database-level unique constraint.

Closes #71
```

---

## 4. Code Review 要求

### 4.1 基本规则

| 规则 | 说明 |
|------|------|
| **必审原则** | 所有合并到 `dev`、`test`、`main` 的代码必须经过 CR |
| **至少 1 人** | 每个 Pull Request 至少由 1 名团队成员 Review 通过 |
| **作者不可自审** | 代码作者不能给自己 Review |
| **CI 先行** | Review 前必须确认 CI 构建通过 |
| **无重大遗留** | 所有 blocking 级别的评论必须解决才能合并 |

### 4.2 Review 检查清单

**功能性：**
- [ ] 代码实现了 PR 描述的功能
- [ ] 边界情况已处理（空值、超时、网络异常等）
- [ ] 没有未处理的异常或错误
- [ ] 与现有功能兼容，没有引入回归

**代码质量：**
- [ ] 遵循项目现有的代码风格和架构
- [ ] 函数/方法职责单一，不过度复杂
- [ ] 变量和函数命名清晰自文档
- [ ] 没有硬编码的魔法数字或字符串（应使用常量/配置）
- [ ] 日志记录完整且合理（避免敏感信息泄露）

**安全性：**
- [ ] 用户输入经过了合法性校验
- [ ] 没有 SQL 注入、XSS、CSRF 等安全风险
- [ ] 敏感数据（密码、Token）没有明文存储或传输
- [ ] 接口有合适的权限控制

**测试：**
- [ ] 新功能有对应的单元测试
- [ ] Bug 修复有对应的回归测试
- [ ] 测试覆盖了正常路径和异常路径
- [ ] 所有测试通过

**性能：**
- [ ] 没有不必要的数据库查询（N+1 问题）
- [ ] 没有阻塞主线程的长时间操作（移动端）
- [ ] 循环和递归有正确的终止条件

### 4.3 Review 评论等级

| 等级 | 标签 | 含义 | 行动要求 |
|------|------|------|---------|
| 🔴 Blocking | `blocking` | 必须修改才能合并 | 需作者回应并修改 |
| 🟡 Discussion | `question` | 需要澄清或讨论 | 讨论后确认或修改 |
| 🟢 Suggestion | `suggestion` | 非强制改进建议 | 可采纳或留待后续 |
| ⚪ Nitpick | `nit` | 个人偏好或细微格式 | 可忽略 |

### 4.4 PR 描述模板

```markdown
## 变更描述
<!-- 简要说明本次 PR 做了什么 -->

## 关联 Issue
<!-- Closes #xxx / Fixes #xxx -->

## 测试说明
<!-- 如何验证变更的正确性 -->

## 截图（可选）
<!-- UI 变更请附截图 -->

## 检查清单
- [ ] 本地测试通过
- [ ] CI 通过
- [ ] 已添加/更新测试
- [ ] 文档已更新（如有需要）
- [ ] 无敏感信息泄露
```

---

## 5. 参考命令速查

```bash
# 创建功能分支
git checkout dev
git pull origin dev
git checkout -b feature/my-feature

# 提交代码
git add .
git commit -m "feat(xxx): concise description"

# 推送分支并创建 PR
git push origin feature/my-feature

# 同步 dev 最新代码到当前分支
git fetch origin dev
git rebase origin/dev

# 合并（在本地模拟，实际建议在远程 PR 中操作）
git checkout dev
git merge --no-ff feature/my-feature
git push origin dev

# 删除已合并的本地分支
git branch -d feature/my-feature

# 删除已合并的远程分支
git push origin --delete feature/my-feature
```

---

> **注意**: 此规范适用于 Field Tracker 项目所有团队成员。如有修改建议，请发起 Issue 讨论。
