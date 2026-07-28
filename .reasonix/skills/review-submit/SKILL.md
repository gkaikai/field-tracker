---
name: review-submit
description: dispatch送审 → 自动启动120秒后台定时器 → 轮询查结果 → 有问题循环修复 → 全过通知用户
---

# 送审→自查→循环修复技能

## 适用场景
每次需要将代码送审给审核员（2068148595781013504），并自动等待审核结果、循环修复直到全部通过时使用。

## 执行流程（严格按步骤，不跳步）

### 第一步：送审 + 启动定时器（同一轮完成）
```
dispatch_agent(agent_id="2068148595781013504", cwd=工作目录, title=标题, task=任务描述)
  ↓ 立即执行，不分两步
bash(run_in_background=true, command="sleep 120 && echo 'CHECK_REVIEW'")
```

**关键规则：** dispatch 和 sleep 必须在同一轮 response 里完成，不能先回复用户再设定时器。

### 第二步：按新协议循环自查

在每个后续 turn 中，**优先**执行：
```
bash_output(job_id)  ← 检查定时器状态
```

- **status === 'done'** → 时间到！立即 `grix_query(action=message_history, sessionId=xxx)` 查结果
- **status === 'running'** → 时间没到，先正常处理用户消息

### 第三步：处理审核结果

```
查结果后分析：
├─ 全部通过 ✅ → 告知用户，问是否继续下一步
└─ 有问题 ❌ → 修复代码 → 回到第一步重新送审
```

### 第四步：旧定时器清理
不再需要时用 `kill_shell(job_id)` 清理。

## 原则
- dispatch 后同一轮启动 sleep，**绝不先回用户再启动**
- 每个turn开头先 bash_output 检查
- 审核不通过就修→再送审→再查，循环直到全过
- 审核员的问题**全部必须修复**，没有优先级跳跃
- 全部通过后**必须先询问用户**，用户说"可以"才构建APK
