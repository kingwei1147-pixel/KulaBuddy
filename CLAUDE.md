# CLAUDE.md

## Karpathy Guidelines — LLM Coding Best Practices

Behavioral guidelines to reduce common LLM coding mistakes, derived from [Andrej Karpathy's observations](https://x.com/karpathy/status/2015883857489522876).

**Tradeoff:** These guidelines bias toward caution over speed. For trivial tasks, use judgment.

### 1. Think Before Coding

**Don't assume. Don't hide confusion. Surface tradeoffs.**

Before implementing:
- State your assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them — don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.

### 2. Simplicity First

**Minimum code that solves the problem. Nothing speculative.**

- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it.

Ask yourself: "Would a senior engineer say this is overcomplicated?" If yes, simplify.

### 3. Surgical Changes

**Touch only what you must. Clean up only your own mess.**

When editing existing code:
- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Match existing style, even if you'd do it differently.
- If you notice unrelated dead code, mention it — don't delete it.

When your changes create orphans:
- Remove imports/variables/functions that YOUR changes made unused.
- Don't remove pre-existing dead code unless asked.

The test: Every changed line should trace directly to the user's request.

### 4. Goal-Driven Execution

**Define success criteria. Loop until verified.**

Transform tasks into verifiable goals:
- "Add validation" → "Write tests for invalid inputs, then make them pass"
- "Fix the bug" → "Write a test that reproduces it, then make it pass"
- "Refactor X" → "Ensure tests pass before and after"

For multi-step tasks, state a brief plan:
```
1. [Step] → verify: [check]
2. [Step] → verify: [check]
3. [Step] → verify: [check]
```

Strong success criteria let you loop independently. Weak criteria ("make it work") require constant clarification.

---

## Project: MOMO — Autonomous AI Agent

- TypeScript + Node.js
- 8 domain workflows: market-analysis, product-design, financial-analysis, legal-review, hr-recruitment, engineering-design, content-marketing, customer-support
- Multi-agent architecture with coordinator + worker agents
- MCP dynamic loading + ClaWHub skill ecosystem + self-improvement loop

### 核心解决痛点

MOMO 解决的核心问题是：**现有 AI Agent 方案在"自主性"和"本地化"之间存在空白 —— 要么完全依赖云端 API（如 Claude Code），要么需要复杂的第三方基础设施（Ollama/vLLM/LM Studio）来运行本地模型。**

具体来说：

1. **零依赖本地推理** — 内置 `node-llama-cpp` 运行时，无需安装任何第三方推理引擎，直接加载 GGUF 模型即可运行，可完全离线
2. **能力自补全** — 运行时自动检测能力缺口 → 搜索 MCP 服务器 → 安装注册，无需用户手动配置集成
3. **状态持久化** — 任务可暂停/恢复，状态机落盘，长期运行不丢失进度（竞品大多单 Session）
4. **中文原生** — DeepSeek 中文思维 + 完整 i18n，面向中文用户的自主 Agent

### 核心逻辑流

入口在 `AgentRuntime.runTask()`，执行流程如下：

```
用户请求
  │
  ├─ 状态机恢复检查（是否从 checkpoint 恢复）
  ├─ TaskIntent 意图识别 → routingReason / taskType / outputFormat
  ├─ 复杂度判定 → simple? → runSimpleTask（单次 LLM 调用 + 限 3 次工具）
  │
  └─ complex / normal? → 进入主循环（最长 5 个退化阶段）：
       │
       ├─ 1. HierarchicalPlanner（复杂任务）
       │     将目标分解为子目标树 → 通过 subgoalExecutor
       │     委托给多 Agent 协同执行（coordinator → worker agents）
       │     → 完成后聚合子目标结果为上下文
       │
       ├─ 2. MCP Auto-Completion（能力自补全）
       │     capabilityPlan.missingTools → mcp.search → mcp.install
       │     → 刷新可用工具列表
       │
       ├─ 3. 记忆注入（L1~L5 分层记忆）
       │     任务记忆(L2) + 语义记忆(L4) + RAG 知识库(L5)
       │     + 进化技能建议 + 失败规避模式 + benchmark 建议
       │
       ├─ 4. AgentRuntime 主循环（多周期 planning → execution → verification）
       │     AgentStateMachine 驱动状态流转：
       │       idle → classify → plan → execute → verify → complete / retry
       │
       │     plan 阶段：
       │       - 构建 System Prompt（含时间上下文、Karpathy 准则、工具列表）
       │       - 可选 ThoughtTree（MCTS 多分支探索，选择最优路径）
       │       - buildToolDefinitions 根据 taskType 过滤可用工具
       │       - LLM 返回工具调用（native tool_calls 或 XML <invoke> 格式）
       │
       │     execute 阶段（completeWithTools）：
       │       - 循环执行工具调用，直至 maxToolCalls 或重复检测
       │       - 错误诊断+自动重试（transient → 指数退避重试）
       │       - 缺失依赖自动安装（tool.provision → shell.exec）
       │       - ThoughtTree 分支选择（同一场景多条路线择最优）
       │       - 上下文裁剪（超出 token 限制时截断旧工具结果）
       │
       │     verify 阶段：
       │       - 用 criticModel 验证结果质量（success/failure + gaps）
       │       - 失败后进入退化阶段（最多 5 个 phase）：
       │           Phase 0: 正常执行
       │           Phase 1: 定向修复（critic 返回的 gaps → 精确修补）
       │           Phase 2: MCP 搜索缺失工具 → 安装 → 重试
       │           Phase 3: 子 Agent 委托执行
       │           Phase 4: 优雅失败 + 可操作建议
       │       - 每轮失败触发 SelfEvolver（从失败提炼 SKILL.md）
       │
       ├─ 5. 执行模式切换
       │     ├─ task 模式（单 Agent 标准执行）
       │     ├─ project / dag-pipeline 模式（多阶段 DAG 编排）
       │     │   → 按拓扑序执行各 phase，每 phase 由角色 Agent 独立完成
       │     └─ project / master-worker 模式（主从协同）
       │         → Coordinator 分解 → 分发 subgoal → Worker 执行 → Aggregator 汇总
       │
       └─ 6. 收尾
            - 结果合成（工具结果 → 自然语言总结）
            - SelfEvolver 提炼技能
            - 状态机落盘 + checkpoint 清理
            - SmartEscalation 记录成功/失败
```

**关键机制总结：**

- **长链推理** — 支持多 planning cycle + 最多 5 阶段退化重试 + ThoughtTree MCTS 分支探索 + HierarchicalPlanner 层次化分解，深度非单轮可及
- **多 Agent 协作** — AgentRegistry 注册 12+ 专业 Worker（研发/金融/法务/HR/设计/市场/客服/教育/医疗/房地产/视频/播客），Coordinator 通过 delegation protocol + ContextBus 分发子任务
- **自我进化** — 从失败中自动学习生成 SKILL.md，后续任务自动注入进化后的策略和陷阱警告
- **MCP 自配置** — 运行时自动检测工具缺口，搜索 npm registry 安装 MCP 服务器，无需手动配置
