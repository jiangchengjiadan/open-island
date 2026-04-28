# Open Island M1 手工测试用例

更新时间：2026-04-27

适用分支：

- `codex-default-hooks`

本测试清单覆盖当前这批改动：

- Codex hooks 默认安装
- Codex 主会话/辅助线程去重第一版
- Ghostty jump 首版
- Warp jump 首版
- VS Code / Cursor jump 首版
- stale session cleanup 第一版
- permission request 排队与并发保护第一版
- bootstrap 自愈检查第一版

## 测试前准备

### 环境要求

- macOS 13+
- Node.js 可用
- Swift/Xcode Command Line Tools 可用
- 已授予 Accessibility 权限
- 本地已安装需要参与测试的工具

建议准备这些应用：

- Claude Code
- Codex
- Terminal
- iTerm2
- Ghostty
- Warp
- Visual Studio Code
- Cursor

### 启动方式

建议统一这样启动：

```bash
open-island stop
open-island start
```

如需手动方式：

```bash
cd bridge && npm start
cd native/NotchMonitor && swift run NotchMonitor
```

### 建议同时观察的日志

```bash
tail -n 200 /tmp/notch-monitor-hook.log
tail -n 200 /tmp/notch-monitor-codex-wrapper.log
tail -n 200 /tmp/notch-monitor-jump.log
```

如果是源码运行 bridge，也建议盯一下 bridge 控制台输出。

## 一、安装与自愈

### TC-01 启动后自动安装 Claude 与 Codex 配置

步骤：

1. 先执行 `open-island stop`
2. 确认以下文件存在：
   - `~/.claude/settings.json`
   - `~/.codex/config.toml`
   - `~/.codex/hooks.json`
   - `~/.local/bin/codex`
3. 执行 `open-island start`
4. 等待 5 到 10 秒

预期：

- notch 空态诊断最终显示：
  - Claude hook ready
  - Codex hooks ready
  - Codex wrapper ready
  - bridge connected
- `~/.codex/hooks.json` 里能看到 `hook.js event codex`
- `~/.local/bin/codex` 里能看到 `codex-wrapper.js`

### TC-02 缺失 Codex hooks 时自动自愈

步骤：

1. 备份 `~/.codex/hooks.json`
2. 删除或移走 `~/.codex/hooks.json`
3. 保持 Open Island 正在运行
4. 等待一个诊断周期

预期：

- 面板会短暂显示 Codex hooks 缺失
- 20 秒内应自动触发修复
- `~/.codex/hooks.json` 被重新生成
- 诊断项恢复为 ready

### TC-03 缺失 Codex wrapper 时自动自愈

步骤：

1. 备份 `~/.local/bin/codex`
2. 删除或改名 `~/.local/bin/codex`
3. 保持 Open Island 正在运行
4. 等待一个诊断周期

预期：

- 面板会显示 Codex wrapper 缺失
- 自动修复会重新安装 wrapper
- `~/.local/bin/codex` 恢复

### TC-04 bridge 崩掉后自动恢复

步骤：

1. 确保 Open Island 已正常启动
2. 找到 bridge 进程并杀掉
3. 观察 20 秒内状态变化

预期：

- 面板先显示 bridge 未连接或等待连接
- 自动修复会重启 bridge
- 最终恢复 `Local bridge connected`

## 二、Codex 默认集成

### TC-05 Codex 会话默认注册

步骤：

1. 新开一个终端
2. 执行 `codex`
3. 观察 notch 面板

预期：

- 无需额外环境变量
- Codex 会话会自动出现在面板
- `tail -n 200 /tmp/notch-monitor-codex-wrapper.log` 可以看到：
  - wrapper 启动
  - connected to bridge
  - registered agent

### TC-06 Codex 结束后正常注销

步骤：

1. 进入 `codex`
2. 退出 Codex
3. 观察面板和 wrapper 日志

预期：

- 会话很快从面板消失
- wrapper 日志可见 `unregistered agent`

## 三、Codex 去重

### TC-07 同一个 Codex 会话只显示一个主项

步骤：

1. 在一个终端里启动 `codex`
2. 等待 10 到 20 秒
3. 观察面板里 Codex 项数量

预期：

- 同一终端中的一个 Codex 交互会话只出现 1 条主项
- 不应同时出现一条 `codex` 和一条 `codex — 项目名` 的重复项

### TC-08 多个终端各开一个 Codex 会话时应显示多条

步骤：

1. 在 Terminal 开一个 `codex`
2. 在 iTerm 或 Ghostty 再开一个 `codex`
3. 观察面板

预期：

- 两个不同终端会话应显示为两条
- 不应被错误去重合并

## 四、权限审批

### TC-09 单个审批请求正常展示与响应

步骤：

1. 启动一个会触发 `Bash` 或 `Write` 权限审批的 Claude/Codex 场景
2. 等待 notch 中出现审批条
3. 先点 `Allow`

预期：

- 审批条展示对应请求内容
- 点击后请求消失
- agent 继续执行
- `hook.log` 中可看到允许结果

### TC-10 Allow Similar 生效

步骤：

1. 触发一次相同命令或相同文件的审批
2. 点 `Allow Similar`
3. 再次让同一个会话触发相同请求

预期：

- 第二次请求不再弹出人工审批
- 会自动通过

### TC-11 多个审批请求排队

步骤：

1. 在同一个 agent 会话里连续触发两个需要审批的动作
2. 先不要处理第一个
3. 观察面板
4. 处理第一个后观察第二个

预期：

- 面板不会被第二个请求直接覆盖
- 第一个请求响应后，第二个才出现
- 不应出现点 A 实际回应到 B 的现象

### TC-12 多个 agent 同时审批

步骤：

1. 同时开两个会触发审批的 agent 会话
2. 让它们先后发起审批

预期：

- 两个 agent 各自显示自己的审批状态
- 响应一个 agent 不会清掉另一个 agent 的审批

## 五、stale session cleanup

### TC-13 completed 会话过期清理

步骤：

1. 让一个 agent 会话正常结束
2. 观察它在面板中停留时间

预期：

- 会话不会永久残留
- 大约 1 分钟内应被清理

### TC-14 异常终止的有 pid 会话被清理

步骤：

1. 启动一个 Codex 会话
2. 直接强杀真实子进程或关闭宿主终端，制造异常结束
3. 不要手动 restart app
4. 观察面板

预期：

- 该会话不会永久挂在面板上
- 大约几十秒内应被 bridge 清理

### TC-15 waiting 会话不会被过早清理

步骤：

1. 启动一个会进入等待状态的会话
2. 保持窗口打开但不继续操作
3. 观察 1 到 3 分钟

预期：

- 活跃但等待中的会话不应被立刻清除
- 只要 pid 还活着，应继续保留

## 六、Jump 行为

### TC-16 Terminal jump

步骤：

1. 在 Terminal 启动 Claude/Codex
2. 点击对应面板项

预期：

- Terminal 被激活
- 尽量回到正确窗口/tab
- `jump.log` 能看到成功或 fallback 路径

### TC-17 iTerm jump

步骤：

1. 在 iTerm 启动 Claude/Codex
2. 点击面板项

预期：

- iTerm 被激活
- 尽量切到正确 tab/session

### TC-18 Ghostty jump

步骤：

1. 在 Ghostty 某个项目目录下运行 agent
2. 点击面板项

预期：

- Ghostty 被激活
- 若工作目录能匹配，应回到对应 terminal
- 匹配不到时至少激活 Ghostty app

### TC-19 Warp jump

步骤：

1. 在 Warp 某项目目录下运行 agent
2. 点击面板项

预期：

- Warp 被激活
- 若窗口标题含项目 token，会抬对应窗口
- 否则至少激活 Warp

### TC-20 VS Code terminal jump

步骤：

1. 在 VS Code 内置 terminal 运行相关 agent
2. 点击面板项

预期：

- VS Code 被激活
- 若窗口标题可匹配项目 token，应抬对应窗口
- 最低要求是正确 IDE 被激活

### TC-21 Cursor terminal jump

步骤：

1. 在 Cursor 内置 terminal 运行相关 agent
2. 点击面板项

预期：

- Cursor 被激活
- 若窗口标题可匹配项目 token，应抬对应窗口
- 最低要求是正确 IDE 被激活

## 七、回归检查

### TC-22 JetBrains jump 未回退

步骤：

1. 在 JetBrains 内置 terminal 跑会话
2. 点击面板项

预期：

- 仍然走原先 JetBrains 分支
- 不应因为新增 VS Code / Cursor 分支而错误识别

### TC-23 非审批状态点击仍能 jump

步骤：

1. 让一个 agent 处于普通 running 状态
2. 点击面板项

预期：

- 仍能正常 jump
- 不会因为新增队列逻辑导致普通项点击失效

### TC-24 审批状态点击按钮后不会卡死

步骤：

1. 触发审批条
2. 分别测试 `Allow`、`Allow Similar`、`Deny`

预期：

- UI 不会残留不可消失的审批条
- 处理后如有下一条排队请求，应自然切换

## 八、建议记录格式

你测试时建议按下面格式记录：

```text
TC-11
结果：通过 / 失败 / 部分通过
现象：
日志：
复现概率：
备注：
```

## 九、优先级建议

如果时间有限，优先测这些：

1. `TC-05` Codex 默认注册
2. `TC-07` Codex 去重
3. `TC-11` 多请求排队
4. `TC-14` stale cleanup
5. `TC-18` Ghostty jump
6. `TC-19` Warp jump
7. `TC-20` VS Code jump
8. `TC-21` Cursor jump

这 8 条最能覆盖这批改动的核心风险。
