# Open Island

macOS 上用于本地 AI 编码会话的灵动岛风格状态监控。

[English README](./README.md)

[![Platform](https://img.shields.io/badge/platform-macOS%2013%2B-black)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-5.9-orange)](https://www.swift.org/)
[![Node.js](https://img.shields.io/badge/Node.js-required-339933)](https://nodejs.org/)
[![License](https://img.shields.io/badge/license-MIT-blue)](./LICENSE)
[![Status](https://img.shields.io/badge/status-early%20preview-informational)](#状态)

Open Island 是一个 macOS 菜单栏应用，适合同时运行多个本地编码 Agent 的开发者。它通过本地 Unix socket bridge 监听 Agent 活动，在刘海附近展示会话状态，弹出支持的权限请求，并允许你一键跳回所属的终端或 IDE。

## 特性

- 实时显示 Claude Code 和 Codex 的会话状态
- 在面板中展示支持的权限请求
- 一键跳回对应的终端或 IDE
- 轻量本地 macOS 应用，配合小型 bridge 进程运行

## 展示

### 主界面

当前应用的真实截图：

![Open Island real screenshot](./assets/media/open-island-real-screenshot.png)

这张图展示了当前 notch panel UI，以及多个会话的最新状态。

### 品牌图

![Open Island main interface](./assets/media/open-island-main-interface.png)

这是一张更适合 GitHub 首页和分享场景的展示图。

### 权限审批流程

![Open Island permission approval flow](./assets/media/open-island-permission-flow.gif)

展示 Open Island 如何发现权限请求、在面板中提示，并让你无需切回终端就能处理。

### Terminal / JetBrains 路由示意

![Open Island terminal and JetBrains routing overview](./assets/media/open-island-terminal-jetbrains-flow.png)

这张图概括了 Terminal / iTerm / JetBrains 会话如何进入 bridge，再回到 notch panel。

打包说明：

- 本地构建 DMG：`bash scripts/package-dmg.sh <version>`
- 构建出的 DMG 适合上传为 GitHub Release 附件
- 当前 DMG 默认是未签名的开发者预览版，除非你额外做了签名和 notarization

## 为什么做这个项目

CLI 编码 Agent 很强，但一旦你同时开着 Terminal、iTerm、Claude Code、Codex 以及 IDE 内置终端，就很容易失去对当前会话状态的感知。Open Island 的目标，就是把这些本地 Agent 活动变成一个轻量、始终可见的环境状态 UI。

## 当前支持

当前第一优先级支持：

- Claude Code
- Codex

代码结构已经为后续接入更多本地 Agent 留了空间，但目前的一等公民工作流仍然聚焦在 Claude Code 和 Codex。

## 状态

Open Island 已经可以用于本地 macOS 工作流，尤其适合以 Terminal、iTerm、Claude Code 和 Codex 为核心的使用场景。它仍然是 early preview，但核心闭环已经存在：会话监控、面板渲染、权限提示以及基础跳转能力都已经可用。

目前表现较好的部分：

- 个人和本地开发者工作流
- bridge、面板渲染和支持的权限流程
- Terminal 和 iTerm 的跳转体验

当前已知粗糙点：

- JetBrains 内置终端跳转仍然存在边界情况
- JetBrains 同项目多窗口的精确跳转还不稳定
- 部分交互依赖 macOS Accessibility 和 AppleScript 的稳定性

近期重点：

- 继续改进 JetBrains 路由，减少多窗口误跳
- 提高权限交互和跳转行为的稳定性
- 补更多测试和打包完善工作

## 环境要求

- macOS 13 或更高版本
- `PATH` 中可用的 Node.js
- Swift 5.9 或 Xcode Command Line Tools
- 为跳转和自动化行为开启 Accessibility 权限

## 安装

### 快速开始

安装启动器和本地 hooks：

```bash
./scripts/install-hooks.sh
```

然后使用：

```bash
open-island start
open-island stop
open-island restart
open-island status
```

如果当前 shell 找不到 `open-island`：

```bash
export PATH="$HOME/.local/bin:$PATH"
```

如果你要把打包后的 app 分发给其他用户，请先看：

- [未签名 macOS 安装说明](./docs/unsigned-macos-install.zh-CN.md)
- [发布清单](./docs/release-checklist.zh-CN.md)
- [更新日志](./CHANGELOG.md)

### 开发启动方式

启动 bridge：

```bash
cd bridge
npm install
npm start
```

启动原生 app：

```bash
cd native/NotchMonitor
swift build
swift run NotchMonitor
```

## 首次运行设置

Open Island 依赖 macOS Accessibility 来完成窗口激活、终端跳转和权限交互。

首次运行时请检查：

- `System Settings -> Privacy & Security -> Accessibility`
- 允许你用于启动 Open Island 的终端或应用

如果不开启该权限，面板可能仍能显示，但跳转和自动化行为可能会失败。

## 使用方式

1. 用 `open-island start` 启动 Open Island
2. 正常启动 Claude Code 或 Codex
3. 观察 notch panel 中实时出现的会话
4. 点击某个会话，跳回它所属的终端或 IDE
5. 在面板中查看和处理支持的权限请求

## 项目结构

```text
open-island/
├── native/                    # SwiftUI macOS app
│   └── NotchMonitor/
│       ├── Package.swift
│       └── Sources/
│           ├── NotchMonitorApp.swift
│           ├── Models/
│           ├── Views/
│           └── Services/
├── bridge/                    # Node.js socket bridge and hooks
│   ├── server.js
│   ├── hook.js
│   └── codex-wrapper.js
├── scripts/
│   └── install-hooks.sh
└── docs/
    └── implementation notes and design docs
```

## 开发

常用命令：

```bash
cd bridge && npm install
cd bridge && npm start
cd bridge && npm run dev

cd native/NotchMonitor && swift build
cd native/NotchMonitor && swift run NotchMonitor
```

如果你修改了 hook、wrapper 或跳转逻辑，重新测试前建议重启 app：

```bash
open-island stop
open-island start
```

## 排查问题

### `open-island: command not found`

把 `~/.local/bin` 加进 `PATH`，或者直接执行：

```bash
~/.local/bin/open-island start
```

### 仓库改名或移动后 Swift 构建失败

Swift module cache 路径可能已经过期，执行：

```bash
cd native/NotchMonitor
swift package clean
swift build
```

### Terminal 可以跳，IDE 不行

先检查：

- Open Island 是否正在运行
- bridge 是否已启动
- Accessibility 权限是否已开启

然后查看日志：

```bash
tail -n 200 /tmp/notch-monitor-jump.log
tail -n 200 /tmp/notch-monitor-hook.log
tail -n 200 /tmp/notch-monitor-codex-wrapper.log
```

### JetBrains 能切到 IDE，但切不到准确窗口

这是当前 early-preview 版本的已知限制。Open Island 通常可以激活正确的 JetBrains 应用，也经常能切到正确的项目窗口，但同项目多窗口的精确跳转目前还不稳定。

## FAQ

### 这个项目支持 macOS 之外的平台吗？

不支持。它依赖 macOS 的 UI automation、菜单栏 API 以及本地 Unix-domain 工作流假设。

### 支持远程 Agent 或云端会话吗？

目前不支持。当前设计目标是单台 Mac 上的本地开发者工作流。

### 为什么 JetBrains 的跳转不如 Terminal / iTerm 稳定？

JetBrains 暴露给 UI 自动化的表面能力不如 Terminal 和 iTerm 稳定。Open Island 通常能把正确的 IDE 激活到前台，但同项目多窗口的精确定位仍有限制。

### Codex 开箱即用吗？

是的。安装器会给 Codex 创建一个本地 wrapper，这样 Open Island 能在不改变你平时命令的前提下观察会话。

## 日志

常用调试日志：

- `/tmp/notch-monitor-jump.log`
- `/tmp/notch-monitor-hook.log`
- `/tmp/notch-monitor-codex-wrapper.log`

## 贡献

欢迎提 Issue 和 PR。

提交修改前建议至少做这些本地校验：

- `cd native/NotchMonitor && swift build`
- `cd bridge && npm install`
- 手动验证 bridge 启动、面板渲染、权限提示和跳转行为

## License

MIT
