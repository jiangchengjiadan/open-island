# Open Island

<p align="center">
  <img src="assets/icon/open-island-icon.svg" alt="Open Island" width="128" height="128">
</p>

<h1 align="center">Open Island</h1>

<p align="center">
  <strong>让 AI Agent 从终端黑盒走向桌面。</strong>
  <br>
  面向 Claude Code、Codex 和本地 CLI Agent 工作流的 macOS 原生桌面控制岛。
  <br><br>
  <a href="README.md">English</a> | <strong>简体中文</strong>
</p>

<p align="center">
  <a href="https://www.apple.com/macos/"><img src="https://img.shields.io/badge/platform-macOS%2013%2B-black?style=flat-square" alt="macOS 13+"></a>
  <a href="https://www.swift.org/"><img src="https://img.shields.io/badge/Swift-5.9-orange?style=flat-square" alt="Swift 5.9"></a>
  <a href="https://nodejs.org/"><img src="https://img.shields.io/badge/Node.js-required-339933?style=flat-square" alt="Node.js required"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue?style=flat-square" alt="MIT License"></a>
  <a href="#状态"><img src="https://img.shields.io/badge/status-early%20preview-informational?style=flat-square" alt="Early preview"></a>
</p>

<p align="center">
  <a href="#快速开始">快速开始</a> ·
  <a href="#展示">展示</a> ·
  <a href="#工作原理">工作原理</a> ·
  <a href="#开发">开发</a>
</p>

<p align="center">
  <img src="assets/media/open-island-main-interface.png" alt="Open Island main interface" width="760">
</p>

---

## Open Island 是什么？

Open Island 是一个轻量的 macOS 原生应用，为本地 AI 编码 Agent 提供一个桌面级控制面板。它常驻在屏幕刘海或顶部区域，通过本地 Unix socket bridge 监听 Agent 活动，把原本埋在终端里的关键信息展示出来：哪些任务正在运行、哪些任务在等待、哪些权限需要审批，以及应该跳回哪个终端或 IDE。

它不是 Claude Code、Codex 或终端的替代品。它补上的是本地自动化工作流里最后缺失的一块拼图：可见、可控、可跳转。

## 为什么需要它？

AI 编码正在从“问 ChatGPT 一个问题”变成“把任务交给本地 CLI Agent 执行”。你可能会在一个终端里让 Agent 改前端，在另一个终端里跑测试，还在 IDE 内置终端里等它处理权限请求。

这种工作流很强，但会带来三个直接痛点：

- **状态不可见**：Running、Waiting、Completed、Error 分散在多个终端 Tab 和 IDE 面板里。
- **权限审批容易被漏掉**：Agent 可能只是卡在一个隐藏窗口里的 Approve 提示上，白白等待十分钟。
- **上下文切换成本高**：一旦需要介入，你仍然要在一堆窗口里找回正确的会话现场。

Open Island 的目标，就是把这些本地 Agent 状态从终端黑盒里“提”出来，变成轻量、一直可见、但不打扰你的系统级状态层。

## 核心能力

- **多会话状态，全局可见**：把本地 Claude Code、Codex 和 Qoder 会话汇聚到一个刘海面板里，清楚区分运行中、等待中、已完成和异常状态。
- **桌面级权限审批**：支持的权限请求会直接出现在面板中，你可以在当前 IDE 视线内完成批准或拒绝，不必切回终端。
- **一键回到现场**：点击会话卡片即可跳回对应的 Terminal、iTerm、Ghostty、Warp、VS Code、Cursor 或支持的 IDE 路由，减少多项目并行时的上下文迷失。
- **纯本地 Bridge**：通过小型 Node.js Unix socket bridge 和 macOS 原生 UI 通信，不依赖云端中转、账号或远程遥测。
- **不改变原有习惯**：继续按原来的方式使用 `claude`、`codex`、终端和 IDE。Open Island 只是观察、汇聚和协调。

## 展示

### 主界面

![Open Island real screenshot](./assets/media/open-island-real-screenshot.png)

刘海面板可以集中展示多个活动会话及其最新状态。

### 权限审批流程

![Open Island permission approval flow](./assets/media/open-island-permission-flow.gif)

权限请求可以被捕获、展示，并直接在桌面面板中处理。

### Terminal / JetBrains 路由示意

![Open Island terminal and JetBrains routing overview](./assets/media/open-island-terminal-jetbrains-flow.png)

本地 Shell 和 IDE 会话通过 hook 进入 bridge，面板再提供回到正确工作现场的路径。

## 当前支持

当前第一优先级支持的 Agent：

- Claude Code
- Codex
- Qoder CLI

当前跳转覆盖：

- Terminal
- iTerm
- Ghostty
- Warp
- VS Code
- Cursor
- JetBrains IDEs，但内置终端和同项目多窗口精确路由仍有边界情况

项目结构刻意保持轻量和可扩展：Agent hook、bridge 事件和 SwiftUI/AppKit 面板彼此分离，后续可以继续接入更多本地 Agent，而不需要改变产品核心形态。目前的一等公民工作流仍然聚焦在本地 macOS 下的 Claude Code、Codex 和 Qoder。

## 状态

Open Island 仍然是 early preview，但已经可以用于以 Terminal、iTerm、Claude Code 和 Codex 为核心的本地 macOS 工作流。核心闭环已经存在：会话监控、面板渲染、权限提示和基础跳转能力都已经可用。

目前表现较好的部分：

- 个人和本地开发者工作流
- Bridge 通信与面板渲染
- 支持的权限审批流程
- Terminal 和 iTerm 跳转体验
- VS Code 和 Cursor 的 workspace 跳转
- Codex 默认 hooks 安装和会话去重
- Qoder 会话监控

当前边界：

- JetBrains 内置终端跳转仍然存在边界情况
- JetBrains 同项目多窗口精确跳转还不稳定
- Ghostty 和 Warp 跳转仍属于首版 best-effort
- 部分交互依赖 macOS Accessibility 和 AppleScript 的稳定性

近期重点：

- 继续改进 JetBrains 路由，减少多窗口误跳
- 提高权限交互和跳转行为的稳定性
- 补更多测试和打包完善工作

## 快速开始

### 环境要求

- macOS 13 或更高版本
- `PATH` 中可用的 Node.js
- Swift 5.9 或 Xcode Command Line Tools
- 为跳转和自动化行为开启 Accessibility 权限

### 安装本地 hooks 和启动器

```bash
./scripts/install-hooks.sh
```

这一步会安装 Claude、Qoder、Codex 的 hooks，以及 Codex wrapper 和 `open-island` 启动器。

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

首次运行时请打开：

```text
System Settings -> Privacy & Security -> Accessibility
```

允许你用于启动 Open Island 的终端或应用。如果不开启该权限，面板可能仍能显示，但跳转和自动化行为可能会失败。

## 工作原理

```text
Claude Code / Codex / local shell
  -> hook 或 wrapper 事件
Node.js bridge
  -> 本地 Unix socket
SwiftUI + AppKit 刘海面板
  -> 状态展示、权限操作、跳转动作
Terminal / iTerm / IDE
```

Bridge 只在本地通信。如果 Open Island 没有运行，Agent 工作流应该继续照常执行；hooks 的定位是轻量观察层，而不是强依赖。

## 打包构建

分发构建说明：

- 本地构建 DMG：`bash scripts/package-dmg.sh <version>`
- 构建出的 DMG 适合上传为 GitHub Release 附件
- 当前 DMG 默认是未签名的开发者预览版，除非你额外做了签名和 notarization

参考：

- [未签名 macOS 安装说明](./docs/unsigned-macos-install.zh-CN.md)
- [发布清单](./docs/release-checklist.zh-CN.md)
- [更新日志](./CHANGELOG.md)

## 开发

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

如果你修改了 hook、wrapper 或跳转逻辑，重新测试前建议重启 app：

```bash
open-island stop
open-island start
```

## 使用方式

1. 用 `open-island start` 启动 Open Island
2. 正常启动 Claude Code、Codex 或 Qoder
3. 观察 notch panel 中实时出现的会话
4. 点击某个会话，跳回它所属的终端或 IDE
5. 在面板中查看和处理支持的权限请求

## 最近完成

- Codex hooks 改为默认安装
- Codex 权限 hook 返回格式已兼容当前 CLI
- Codex 主会话和辅助进程去重收紧
- bridge 新增 stale session cleanup 和 permission request 排队
- bootstrap 诊断可尝试有限自愈
- iTerm/tmux 跳转向 session-first 重构
- VS Code/Cursor 跳转优先走 editor CLI 的 workspace reopen
- 新增 Qoder hooks 和会话监控

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
- Bridge 是否已启动
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

### Open Island 会上传我的 Agent 活动吗？

不会。当前 bridge 是纯本地通信，通过本地 Unix socket 传递事件。
