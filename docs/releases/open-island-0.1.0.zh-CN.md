# Open Island 0.1.0

Open Island 的首个公开预览版本。

Open Island 是一个 macOS 菜单栏应用，用灵动岛风格的轻量面板来监控本地 Claude Code 和 Codex 会话。它会展示会话状态、支持的权限请求，以及跳回终端或 IDE 的入口，让你不需要一直在终端 tab 之间来回切。

## 这个预览版包含什么

- 对本地 Claude Code 和 Codex 会话的实时监控
- active、waiting、completed、error 等状态展示
- 在面板中展示支持的权限请求
- 面向 Terminal、iTerm 和 JetBrains 系 IDE 的跳回能力
- 本地 Unix socket bridge 和启动器工作流

## 下载

附件：

- `Open-Island-0.1.0.dmg`

## 安装说明

这个预览版 DMG 当前是未签名、未 notarize 的。

在 macOS 上打开方式：

1. 下载 `Open-Island-0.1.0.dmg`
2. 把 `Open Island.app` 拖到 `Applications`
3. 在 Finder 中打开 `Applications`
4. 对 `Open Island.app` 执行右键或按住 Control 点击
5. 选择 `Open`

如果 macOS 仍然阻止打开，请进入：

- `System Settings -> Privacy & Security`

然后选择 `Open Anyway`。

为了让跳转和权限交互正常工作，还需要开启：

- `System Settings -> Privacy & Security -> Accessibility`

## 已知限制

- 这仍然是 early preview 构建
- Terminal 和 iTerm 的跳转体验目前优于 JetBrains 内置终端
- JetBrains 同项目多窗口的精确跳转目前还不稳定
- 当前打包出来的 DMG 仍然是未签名、未 notarize 的

## 反馈建议

如果你遇到问题，建议反馈时附上：

- macOS 版本
- 你使用的是 Terminal、iTerm、PyCharm 还是 IntelliJ IDEA
- 正在运行的 Agent 工具
- 相关日志片段：
  - `/tmp/notch-monitor-jump.log`
  - `/tmp/notch-monitor-hook.log`
  - `/tmp/notch-monitor-codex-wrapper.log`

## 仓库文档

- 中文 README：[README.zh-CN.md](../../README.zh-CN.md)
- 未签名安装说明：[docs/unsigned-macos-install.zh-CN.md](../unsigned-macos-install.zh-CN.md)
- 更新日志：[CHANGELOG.md](../../CHANGELOG.md)
