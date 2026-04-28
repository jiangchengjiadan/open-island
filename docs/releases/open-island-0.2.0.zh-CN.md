# Open Island 0.2.0

Open Island 的第二个公开预览版本。

Open Island 是一个 macOS 菜单栏应用，用灵动岛风格的轻量面板来监控本地编码 Agent 会话。`0.2.0` 的重点不是继续堆概念，而是把本地工作流做得更可用：更稳的 hooks 安装、更稳的权限链路、更广的 jump 覆盖，以及更准确的终端和编辑器回跳。

## 这个预览版包含什么

- 对本地 Claude Code、Codex 和 Qoder CLI 会话的实时监控
- Codex 默认 hooks 安装，以及与当前 Codex CLI 更兼容的 hook 返回格式
- 在面板中展示支持的权限请求
- bridge 侧的 stale session cleanup 和 permission request 排队
- 面向 Terminal、iTerm、Ghostty、Warp、VS Code、Cursor 和 JetBrains 系 IDE 的跳回能力
- 面向 iTerm/tmux 的 session-first 跳转改进
- 面向 VS Code 和 Cursor 的 workspace reopen 跳转

## 下载

附件：

- `Open-Island-0.2.0.dmg`

## 安装说明

这个预览版 DMG 当前是未签名、未 notarize 的。

在 macOS 上打开方式：

1. 下载 `Open-Island-0.2.0.dmg`
2. 把 `Open Island.app` 拖到 `Applications`
3. 在 Finder 中打开 `Applications`
4. 对 `Open Island.app` 执行右键或按住 Control 点击
5. 选择 `Open`

如果 macOS 仍然阻止打开，请进入：

- `System Settings -> Privacy & Security`

然后选择 `Open Anyway`。

为了让跳转和权限交互正常工作，还需要开启：

- `System Settings -> Privacy & Security -> Accessibility`

## 相比 0.1.0 的主要变化

- Codex hooks 改为默认安装
- 新增 Qoder 监控和 hook 安装
- 并发权限请求的处理更稳定
- stale session 会自动清理
- iTerm 多窗口回跳准确率提升
- VS Code 和 Cursor 可以直接 reopen 对应 workspace
- 新增 Ghostty 和 Warp 的首版 jump 支持

## 已知限制

- 这仍然是 early preview 构建
- JetBrains 同项目多窗口的精确跳转目前还不稳定
- Ghostty 和 Warp 跳转仍属于首版 best-effort
- 当前打包出来的 DMG 仍然是未签名、未 notarize 的

## 反馈建议

如果你遇到问题，建议反馈时附上：

- macOS 版本
- 你使用的是 Terminal、iTerm、VS Code、Cursor、PyCharm 还是其他宿主
- 正在运行的 Agent 工具
- 相关日志片段：
  - `/tmp/notch-monitor-jump.log`
  - `/tmp/notch-monitor-hook.log`
  - `/tmp/notch-monitor-codex-wrapper.log`

## 仓库文档

- 中文 README：[README.zh-CN.md](../../README.zh-CN.md)
- 未签名安装说明：[docs/unsigned-macos-install.zh-CN.md](../unsigned-macos-install.zh-CN.md)
- 更新日志：[CHANGELOG.md](../../CHANGELOG.md)
