# Tasks
- [x] Task 1: 完成运行时逻辑审查基线梳理，明确当前实现与实际支持范围。
  - [x] SubTask 1.1: 复核 bridge、socket、hook、wrapper、native 服务之间的主链路
  - [x] SubTask 1.2: 归档当前已确认的逻辑 bug、实现不一致和代码规范问题
  - [x] SubTask 1.3: 将问题映射到会话展示、权限审批、交互 prompt、跳转、自检与文档五个能力面

- [x] Task 2: 修复会话发现与会话合并逻辑中的正确性问题。
  - [x] SubTask 2.1: 修正 `SocketService.publishAgents()` 中按名称过早过滤的问题
  - [x] SubTask 2.2: 统一去重策略，确保多 tty、多 pid、同名会话可以并存
  - [x] SubTask 2.3: 复核进程扫描与 socket 来源合并后的排序、去重和回收行为

- [x] Task 3: 修复交互式 prompt 检测与提交链路中的错误路由问题。
  - [x] SubTask 3.1: 明确当前仅支持的终端范围，并限制能力暴露
  - [x] SubTask 3.2: 修正 prompt 提交时仅依赖前台 Terminal 窗口的风险
  - [x] SubTask 3.3: 为无法可靠定位目标会话的情况补充安全降级和日志

- [x] Task 4: 修复历史兼容入口与安装行为中的状态一致性问题。
  - [x] SubTask 4.1: 修正 legacy register/update 可能制造重复会话的问题
  - [x] SubTask 4.2: 复核 Claude hook、Codex wrapper、Codex hooks 默认策略与面板行为是否一致
  - [x] SubTask 4.3: 明确 bridge 启动、自检、失败诊断与重试边界

- [x] Task 5: 收敛不合理实现、误导性文案和不合规范的代码。
  - [x] SubTask 5.1: 移除或整理明显未使用的函数、导入和历史残留逻辑
  - [x] SubTask 5.2: 对 README、中文 README、空状态文案进行能力对齐
  - [x] SubTask 5.3: 补充必要注释与命名收敛，消除容易误导维护者的实现细节

- [x] Task 7: 收敛扩展 Agent 类型与文档支持边界之间的不一致。
  - [x] SubTask 7.1: 明确 README 中 Claude/Codex 与扩展 Agent 类型的关系
  - [x] SubTask 7.2: 明确哪些类型是当前一等支持，哪些仅为预留或启发式识别
  - [x] SubTask 7.3: 完成后重新验证 checklist 中的支持范围一致性条目

- [x] Task 6: 完成本次审查的回归验证。
  - [x] SubTask 6.1: 验证同名多会话不会被错误折叠
  - [x] SubTask 6.2: 验证权限审批与交互 prompt 的实际支持边界
  - [x] SubTask 6.3: 验证 Terminal、iTerm、JetBrains 的跳转行为说明与实现一致
  - [x] SubTask 6.4: 验证安装、自检、onboarding、keep awake 的文案和行为一致

# Task Dependencies
- [Task 2] depends on [Task 1]
- [Task 3] depends on [Task 1]
- [Task 4] depends on [Task 1]
- [Task 5] depends on [Task 1]
- [Task 6] depends on [Task 2]
- [Task 6] depends on [Task 3]
- [Task 6] depends on [Task 4]
- [Task 6] depends on [Task 5]
- [Task 6] depends on [Task 7]
