# Open Island 运行时逻辑与代码质量审查 Spec

## Why
当前代码已经具备可用的主流程，但会话合并、交互式输入路由、Codex/Claude 能力对齐、以及若干历史兼容逻辑中仍存在明显的逻辑 bug 和实现不一致问题。为了让 Open Island 后续能够稳定启动、稳定监控、稳定跳转，需要先完成一次系统性的代码审查与修复收敛。

## What Changes
- 对 bridge、native app、安装脚本进行一次面向运行时正确性的代码审查
- 修复会导致会话丢失、错误合并、错误提交交互输入、或能力声明与真实行为不一致的逻辑问题
- 收敛文档、UI 文案、安装行为与实际支持能力之间的不一致
- 清理明显未使用、误导性或历史遗留实现，降低后续维护风险
- 为本次审查涉及的核心链路补充明确的验证清单

## Impact
- Affected specs: 会话发现与展示、权限审批、交互式 prompt 处理、Terminal/IDE 跳转、安装与引导、自检与能力声明
- Affected code: `bridge/server.js`, `bridge/hook.js`, `bridge/codex-wrapper.js`, `bridge/utils.js`, `native/NotchMonitor/Sources/Services/SocketService.swift`, `native/NotchMonitor/Sources/Services/TerminalPromptService.swift`, `native/NotchMonitor/Sources/Services/TerminalJumpService.swift`, `native/NotchMonitor/Sources/Services/AppBootstrapService.swift`, `native/NotchMonitor/Sources/Views/NotchPanel.swift`, `scripts/auto-install-hooks.js`, `scripts/install-codex-wrapper.js`, `README.md`, `README.zh-CN.md`

## ADDED Requirements
### Requirement: 会话合并必须保持运行时唯一性与完整性
系统 SHALL 以运行时标识为主进行会话合并，不得仅因显示名相同而丢弃不同终端、不同 tty、不同 pid 或不同 cwd 的活跃会话。

#### Scenario: 同名会话并存
- **WHEN** 两个同类型会话拥有相同显示名称但来自不同 tty 或不同 pid
- **THEN** 面板中应同时保留两个会话
- **AND** 后续去重逻辑只能合并真实重复的同一会话

### Requirement: 交互式 prompt 的提交必须路由到目标会话
系统 SHALL 仅在能够确认目标终端会话的情况下提交交互式输入，避免把选项误发送到错误窗口或错误标签页。

#### Scenario: 目标会话可定位
- **WHEN** 用户在面板中选择某个交互式 prompt 的选项
- **THEN** 系统应将输入发送到该 prompt 所属的终端会话
- **AND** 不得仅依赖“当前前台 Terminal 窗口”这一不稳定前提

#### Scenario: 目标会话不可定位
- **WHEN** 系统无法可靠识别 prompt 所属终端会话
- **THEN** 系统不得盲目提交输入
- **AND** 应返回可诊断的失败结果或日志

### Requirement: 能力声明必须与真实实现保持一致
系统 SHALL 保证 README、空状态文案、安装流程与真实支持能力一致，避免将未完整支持的能力描述为已稳定可用。

#### Scenario: 功能仅部分支持
- **WHEN** 某项能力仅支持 Claude、仅支持 Codex wrapper、或仅支持 Terminal.app
- **THEN** 文档和 UI 必须明确该限制
- **AND** 不得暗示 iTerm、JetBrains 或其他工具已具有同等能力

### Requirement: 历史兼容入口不得制造错误状态
系统 SHALL 保留历史兼容入口时，确保其不会产生重复会话、悬空状态或不可清理的无效数据。

#### Scenario: 调用 legacy update/register
- **WHEN** 历史兼容命令被外部调用
- **THEN** 更新行为必须命中同一会话标识
- **AND** 不得因为错误的 agent id 生成逻辑制造新会话

### Requirement: 代码审查结果必须可验证
系统 SHALL 为本次审查中识别出的关键修复点提供可执行或可人工复核的验证步骤。

#### Scenario: 修复完成后回归
- **WHEN** 开发者完成本次变更
- **THEN** 必须能够逐项验证会话展示、权限审批、交互 prompt、跳转和安装行为是否符合预期

## MODIFIED Requirements
### Requirement: Open Island 会展示本地活跃 Agent 会话
系统 SHALL 展示通过 socket bridge、进程扫描或 Codex 辅助发现的活跃会话，但展示逻辑必须优先保证正确性，不得因为名称碰撞、来源差异或弱匹配规则导致活跃会话丢失、错合并或误判。

### Requirement: Open Island 支持从面板处理需要注意的会话
系统 SHALL 仅对已经真实支持的权限请求与交互 prompt 提供面板内操作入口；未完整支持的平台、终端或工具需要降级为只读提示或清晰的限制说明。

## REMOVED Requirements
### Requirement: 名称相同的会话可以视为同一会话
**Reason**: 该假设会在多终端、同仓库、多窗口场景下隐藏真实活跃会话，直接导致监控结果不正确。  
**Migration**: 使用 tty、pid、cwd、socket id 等运行时标识进行合并；仅将名称作为展示字段，不作为主去重键。
