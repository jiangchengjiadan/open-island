# CodexIsland 参考迁移计划

更新时间：2026-05-29

参考项目：

- `/Users/danielhe/enviroment/server/workspace/codex-island`

## 结论

`codex-island` 的主功能是 `Claude / Codex` 用量、成本和图表展示，不是 agent 监控工具。它没有我们当前的 `bridge / hook / permission approval / terminal jump` 主链路，所以不适合整体替换 Open Island。

但它有三类能力适合分阶段迁移：

- 岛窗口设计：notch 形状、屏幕定位、hover peek、展开动画、点击穿透。
- Usage / Cost：Claude 和 Codex 用量接口、本地日志 token/cost 统计。
- 产品化能力：设置窗口、显示器选择、刷新间隔、低功耗、Sparkle 更新链路。

## 可复用模块

### P0：窗口和岛外观

可参考：

- `Sources/Window/IslandWindowController.swift`
- `Sources/Window/BorderlessFloatingWindow.swift`
- `Sources/Model/IslandModel.swift`
- `Sources/Model/NotchInfo.swift`
- `Sources/Views/IslandShape.swift`
- `Sources/Theme/Animations.swift`

适合迁移的点：

- 根据真实 notch / menu bar 高度定位窗口。
- 非刘海屏使用可配置宽度，而不是固定假设。
- 紧贴屏幕顶部，外形为平顶、底部连续圆角。
- 鼠标只在岛形区域内命中，岛外区域点击穿透。
- `compact -> peek -> expanded` 状态模型。
- 屏幕变化后自动重新定位。
- 锁屏时隐藏，解锁后淡入。

不建议直接复制：

- 完整 `IslandRootView`。它是 usage 面板，不适合直接承载 agent 列表。
- 完整 `IslandModel` 尺寸逻辑。我们的高度由 agent 数量、审批条、prompt 决定。

### P1：Usage 页面

可参考：

- `Sources/Usage/UsageFetcher.swift`
- `Sources/Usage/UsageStore.swift`
- `Sources/Usage/AppUsage.swift`
- `Sources/Usage/ClaudeCredentials.swift`

适合迁移的点：

- Codex 使用 `~/.codex/auth.json` 的 access token 调用 usage endpoint。
- Claude 使用本地 token / keychain / refresh token 读取 usage。
- 刷新失败时不覆盖已有好数据。
- 网络从断开恢复时立即刷新。
- refresh interval 设置。

风险：

- Claude / Codex usage endpoint 都不是稳定公开 API。
- Usage 失败不能影响 agent 监控和权限审批。
- 需要单独做降级状态和错误展示。

### P2：Cost 页面

可参考：

- `Sources/Cost/ClaudeLogReader.swift`
- `Sources/Cost/CodexLogReader.swift`
- `Sources/Cost/LogParseCache.swift`
- `Sources/Cost/Pricing.swift`
- `Sources/Cost/CostStore.swift`

适合迁移的点：

- 从 `~/.claude/projects/**/*.jsonl` 解析 Claude token usage。
- 从 `~/.codex/sessions/**/rollout-*.jsonl` 解析 Codex token usage。
- per-file cache，避免每次刷新全量扫描。
- 今天 / 本月 / 趋势统计。

风险：

- 这块和 CLI 监控不是一个闭环，建议等窗口和 usage 稳定后再做。
- 价格表需要维护，模型名会变。

### P3：产品化

可参考：

- `Sources/Views/SettingsView.swift`
- `Sources/Views/Settings/*`
- `Sources/Update/UpdaterController.swift`
- `docs/SPARKLE.md`
- `release.sh`

适合迁移的点：

- 自定义 Settings 窗口。
- 显示器选择。
- 低功耗模式。
- 启动项。
- Sparkle 更新。

风险：

- 当前项目还在快速迭代，不宜过早把设置项和更新链路做重。

## 迁移顺序

### Phase 1：岛窗口基础形态

状态：`Done`

目标：

- 让 Open Island 的 collapsed 岛更接近真实 notch。
- 改善多屏和屏幕变化后的定位。
- 不改变 agent 列表、审批、jump、hook 行为。

任务：

- 新增 notch 信息检测。
- collapsed 岛使用真实 menu bar 高度。
- collapsed 外形改为平顶、底部圆角。
- 监听屏幕变化并重新定位。
- 为后续 `peek` 状态预留结构。

验收：

- `swift build` 通过。
- app 启动后仍显示 collapsed 岛。
- hover / click 仍能展开。
- 审批自动展开不受影响。

### Phase 2：Peek 状态

状态：`Done`

目标：

- 引入 `compact / peek / expanded` 状态。
- hover 只进入 peek，点击进入 expanded。

任务：

- 增加 panel state enum。
- collapsed view 扩展为 peek view。
- peek 展示当前最高优先级 agent：权限、运行中、等待、最近完成。
- 调整 hover keep rect。

验收：

- hover 不再直接打开完整列表。
- 点击 peek 能进入完整 agent 面板。
- 有审批时仍直接 expanded。

### Phase 3：Usage 页面

状态：`Done`

目标：

- 在 Open Island 中新增 usage 数据源，但不改变 agent 监控。

任务：

- 引入 UsageFetcher / UsageStore 的最小子集。
- 只接 Claude / Codex。
- 面板中增加 Agent / Usage 分页入口。
- usage 请求失败时显示独立错误，不影响 agents。

验收：

- 无登录状态下显示明确错误。
- 有 token 时能显示 Claude/Codex usage。
- CLI agent 监控仍正常。

### Phase 4：Cost 页面

目标：

- 增加本地 token/cost 统计。

任务：

- 引入 ClaudeLogReader / CodexLogReader / LogParseCache。
- 增加 today / month summary。
- 后续再接图表。

验收：

- 大日志目录下刷新不卡 UI。
- token 数量和 `ccusage` / Codex 日志能大致对齐。

## 当前执行

已完成 `Phase 1`、`Phase 2` 和 `Phase 3`。下一步进入 `Phase 4` 前建议先验证 usage 页面真实账号数据。

本轮只做：

- notch/menu bar 检测。
- collapsed 岛外形改造。
- 屏幕变化重定位。

本轮已落地：

- 新增 `OpenIslandNotchInfo`，按目标屏幕检测真实 notch / menu bar 高度。
- collapsed 岛宽高改为基于 notch 信息计算。
- collapsed 外形改为平顶、底部连续圆角。
- `NotchPanelWindow` 监听屏幕参数变化并重定位。
- `NotchPanelWindow` 引入 `compact / peek / expanded` 三态。
- 鼠标悬停顶部触发区只显示 peek 预览岛，不再直接展开完整列表。
- 点击 compact / peek 岛进入 expanded 完整 agent 面板。
- 鼠标离开 peek 保持区后自动回到 compact。
- 有权限审批时仍走 `expandForAttention()` 直接展开。
- 新增 `WindowUsage / AppUsage` usage 数据模型。
- 新增 `UsageFetcher / UsageStore`，获取 Claude / Codex usage。
- Codex 从 `~/.codex/auth.json` 读取 access token。
- Claude 从环境变量或 `Claude Code-credentials` Keychain 读取 access token。
- 展开面板新增 `Agents / Usage` 页签，Usage 页展示 Claude / Codex 的 5h 和 7d 窗口。
- Usage 自动 5 分钟刷新，手动刷新按钮可立即刷新。
- Claude usage 支持 env token、Keychain token、refresh token 轮换。
- Claude access token 过期时会调用 OAuth refresh，并把旋转后的 access/refresh token 写回 Keychain。
- Claude scope 不足时展示 re-auth 按钮，触发 `claude auth login` 并轮询 usage 恢复。
- 网络从断开恢复到可用时会立即刷新 usage。
- 保持现有 agent 列表、审批、jump、hook 行为不变。

暂不做：

- Cost 页面。
- settings。
- Sparkle。
- Cursor/OpenCode。
