# Interactive Prompt 协议设计

更新时间：2026-04-29

目的：

- 统一当前分裂的两条链路：
  - `permission_request`
  - terminal 文本解析出的 `interactivePrompt`
- 为后续 OpenCode、Plan Review、统一问答交互提供正式协议

相关现状：

- bridge 当前正式支持的是 `permission_request / permission_response`
- 原生端已有 `InteractivePrompt` UI，但数据源主要还是 [`TerminalPromptService.swift`](/Users/danielhe/enviroment/server/workspace/open-island/native/NotchMonitor/Sources/Services/TerminalPromptService.swift:1) 的文本解析
- OpenCode 需要的不只是选项式 prompt，还包括 `answer(text)`

## 一句话结论

应该把“审批”和“交互式问题”统一抽象成 `interaction`，而不是继续维护：

- 一套 permission 专用协议
- 一套 terminal 文本解析 prompt
- 将来再为 OpenCode 单独做第三套

建议方向：

- socket 层新增统一事件：
  - `interaction_requested`
  - `interaction_responded`
- `permission_requested` 先保留一段时间作为兼容层，再逐步收敛到 interaction

## 当前问题

当前项目里其实已经同时存在两种 prompt：

### 1. Permission Prompt

来源：

- `bridge/hook.js`
- `bridge/server.js`

特点：

- 有正式 socket 协议
- 有 requestId
- 支持 allow / deny / allow similar
- queueing 已做

### 2. Interactive Prompt

来源：

- `TerminalPromptService.swift`

特点：

- 没有正式 bridge 协议
- 主要依赖终端文本模式匹配
- 原生 UI 只能看见“标题 + 选项”，看不见上游真实语义
- 无法承接 OpenCode 这类需要 `answer(text)` 的来源

这导致三个问题：

- bridge 无法统一管理 pending interaction
- UI 无法统一处理 response
- 新 agent 一旦不是 Claude/Codex 的旧交互模式，就会继续分叉

## 建议协议

## 1. 统一请求事件

### `interaction_requested`

建议消息结构：

```json
{
  "type": "interaction_requested",
  "data": {
    "agentId": "cursor:conversation-id",
    "request": {
      "id": "cursor:conversation-id:timestamp",
      "kind": "permission",
      "title": "Allow Bash",
      "message": "Cursor wants to run a shell command.",
      "markdown": null,
      "options": [
        { "id": "allow", "value": "allow", "title": "Allow", "detail": null },
        { "id": "deny", "value": "deny", "title": "Deny", "detail": null }
      ],
      "textResponse": {
        "enabled": false,
        "placeholder": null
      },
      "metadata": {
        "toolName": "Bash",
        "command": "git status",
        "permissionKey": "Bash:command:git status"
      },
      "timestamp": 1760000000000
    }
  }
}
```

其中：

- `kind`
  - `permission`
  - `question`
  - 后续可扩 `plan_review`
- `markdown`
  - 给后续 Plan Review 留位
- `options`
  - 承接现有审批条和选项式 prompt
- `textResponse`
  - 用于 OpenCode question、将来更自由的问答输入
- `metadata`
  - 放 source-specific 附加信息，避免主结构膨胀

## 2. 统一响应事件

### `interaction_responded`

建议消息结构：

```json
{
  "type": "interaction_responded",
  "data": {
    "agentId": "opencode:session-id",
    "requestId": "opencode:session-id:timestamp",
    "selectedOption": "allow",
    "text": null,
    "scope": "once",
    "metadata": {
      "permissionKey": "Bash:command:git status"
    }
  }
}
```

用于文本回答时：

```json
{
  "type": "interaction_responded",
  "data": {
    "agentId": "opencode:session-id",
    "requestId": "opencode:session-id:timestamp",
    "selectedOption": "answer",
    "text": "Use the staging API key from .env.local",
    "scope": "once",
    "metadata": {}
  }
}
```

## 3. 与现有 permission 协议的关系

短期不建议立刻删掉：

- `permission_requested`
- `permission_responded`

更稳的做法是：

1. bridge 内部先用统一 `interaction` 结构建模
2. 对 permission 类型同时广播：
   - `interaction_requested`
   - `permission_requested` 兼容事件
3. 原生端优先消费 `interaction_requested`
4. 等 UI 和 bridge 都稳定后，再收掉旧事件

这样不会把当前已经稳定的审批闭环一次性打坏。

## 对现有 Swift 模型的影响

当前 [`Agent.swift`](/Users/danielhe/enviroment/server/workspace/open-island/native/NotchMonitor/Sources/Models/Agent.swift:1) 里有：

- `permissionRequest`
- `interactivePrompt`

建议后续演进成：

- `activeInteraction: AgentInteraction?`

并把下面两类结构合并：

- `PermissionRequest`
- `InteractivePrompt`

建议新模型：

```swift
struct AgentInteraction: Codable {
    let id: String
    let kind: InteractionKind
    let title: String
    let message: String?
    let markdown: String?
    let options: [InteractiveOption]
    let textResponse: TextResponseCapability?
    let metadata: [String: String]?
    let timestamp: Date
}
```

这样 UI 就不需要知道它到底来自：

- Claude/Codex permission
- terminal fallback prompt
- OpenCode question
- future plan review

## 对 bridge 的影响

bridge 当前已有：

- pending permission queue
- session-scoped similar approval

后续建议改成：

- `pendingInteractions: Map<agentId, InteractionQueue>`

其中 permission-specific 的能力继续保留在 metadata 里：

- `permissionKey`
- `command`
- `filePath`

而 question-specific 的能力也可以放进去：

- `questionId`
- `responseFormat`

这会让：

- `Issue 4.2` 的排队逻辑
- `Issue 6.1` 的统一协议
- `Issue 7.2` 的 OpenCode directive 回写

共用一套主干。

## 对 terminal fallback 的定位

`TerminalPromptService` 不应该立刻删除，但定位要变成：

- `fallback detector`

建议顺序：

1. 先让 SocketService 优先消费 `interaction_requested`
2. 没有协议事件时，再跑 `TerminalPromptService.detectPrompt`
3. 检测结果也转成同一种 `AgentInteraction` 结构

这样 `Issue 6.2` 就自然成立：

- 协议优先
- 文本解析降级
- UI 无感知

## 当前结论

`Issue 6.1` 已经可以从设计上定稿：

- 统一抽象：`interaction`
- 请求事件：`interaction_requested`
- 响应事件：`interaction_responded`
- permission 和 question 共用同一套 queue / id / metadata 框架
- terminal 文本解析保留，但只能作为 fallback

建议实现顺序：

1. bridge 内部先引入统一 interaction 结构
2. Swift 端新增 `AgentInteraction`
3. 保留 permission 兼容事件，逐步切 UI
4. 最后再让 OpenCode / future Plan Review 接入这套协议
