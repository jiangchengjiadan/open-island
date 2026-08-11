import Foundation
import AppKit

enum TerminalPromptService {
    private static let logURL = URL(fileURLWithPath: "/tmp/notch-monitor-interactive.log")

    private struct PromptRoutingTarget {
        let ttyCandidates: [String]
        let terminalLabel: String
    }

    /// 判断当前 agent 是否具备安全的内联 prompt 检测与提交条件。
    static func supportsInlinePrompt(for agent: Agent) -> Bool {
        promptRoutingTarget(for: agent, logFailures: false) != nil
    }

    /// 读取目标会话的终端内容，并在确认可安全路由时解析交互式 prompt。
    static func detectPrompt(for agent: Agent) -> InteractivePrompt? {
        guard let target = promptRoutingTarget(for: agent, logFailures: true) else {
            return nil
        }

        let contents = fetchTerminalContents(for: target).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !contents.isEmpty else {
            log("prompt detection skipped agent=\(agent.id) reason=no-terminal-contents tty=\(target.ttyCandidates.joined(separator: ","))")
            return nil
        }

        let prompt = parsePrompt(from: contents, agentId: agent.id)
        if let prompt {
            log("detected prompt agent=\(agent.id) title=\(prompt.title) options=\(prompt.options.count) terminal=\(target.terminalLabel)")
        }
        return prompt
    }

    /// 将选项提交到精确匹配的 Terminal 会话；如果无法定位目标 tab，则直接失败而不发送按键。
    @discardableResult
    static func submit(option: InteractiveOption, to agent: Agent) -> Bool {
        guard let target = promptRoutingTarget(for: agent, logFailures: true) else {
            log("submit blocked agent=\(agent.id) value=\(option.value) reason=unsupported-routing-target")
            return false
        }

        let result = submitOption(option.value, to: target)
        log("submitted option agent=\(agent.id) value=\(option.value) result=\(result ? "ok" : "blocked") terminal=\(target.terminalLabel)")
        return result
    }

    /// 为当前 agent 解析唯一且可安全操作的 Terminal 路由目标。
    private static func promptRoutingTarget(for agent: Agent, logFailures: Bool) -> PromptRoutingTarget? {
        guard isSupportedTerminalApp(agent.terminalApp) else {
            if logFailures {
                log("prompt routing unsupported agent=\(agent.id) terminalApp=\(agent.terminalApp ?? "nil")")
            }
            return nil
        }

        guard let ttyHint = normalizedTTYHint(from: agent) else {
            if logFailures {
                log("prompt routing unsupported agent=\(agent.id) reason=missing-tty terminalApp=\(agent.terminalApp ?? "nil")")
            }
            return nil
        }

        return PromptRoutingTarget(
            ttyCandidates: ttyHint.candidates,
            terminalLabel: agent.terminalApp?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Terminal"
        )
    }

    /// 当前真实支持的内联 prompt 仅限 macOS Terminal.app 及其常见环境标识。
    private static func isSupportedTerminalApp(_ terminalApp: String?) -> Bool {
        let raw = (terminalApp ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !raw.isEmpty else { return false }
        if raw.contains("iterm") || raw.contains("ghostty") || raw.contains("warp") || raw.contains("jetbrains") || raw.contains("jediterm") {
            return false
        }
        return raw == "terminal" || raw == "apple_terminal" || raw.contains("apple_terminal")
    }

    /// 从 agent 中提取标准化 tty 候选集合，用于精确命中 Terminal tab。
    private static func normalizedTTYHint(from agent: Agent) -> (primary: String, candidates: [String])? {
        let raw = (agent.tty ?? agent.terminal).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }

        var values = Set<String>()
        values.insert(raw)
        if raw.hasPrefix("/dev/") {
            values.insert(String(raw.dropFirst("/dev/".count)))
        } else {
            values.insert("/dev/\(raw)")
        }

        let ordered = Array(values)
        return (raw, ordered)
    }

    /// 读取精确 tty 所在 Terminal tab 的内容，避免误读当前选中但不属于目标会话的窗口。
    private static func fetchTerminalContents(for target: PromptRoutingTarget) -> String {
        let ttyList = "{\(target.ttyCandidates.map(appleScriptString).joined(separator: ", "))}"
        let script = """
        tell application "Terminal"
            repeat with targetTTY in \(ttyList)
                set targetTTYValue to contents of targetTTY
                repeat with theWindow in windows
                    set windowRef to contents of theWindow
                    repeat with tabIndex from 1 to count of tabs of windowRef
                        try
                            set tabRef to tab tabIndex of windowRef
                            set tabTTY to tty of tabRef
                            set normalizedTTY to tabTTY
                            if normalizedTTY starts with "/dev/" then
                                set normalizedTTY to text 6 thru -1 of normalizedTTY
                            end if
                            if tabTTY is targetTTYValue or normalizedTTY is targetTTYValue then
                                return contents of tabRef
                            end if
                        end try
                    end repeat
                end repeat
            end repeat
        end tell
        return ""
        """

        return run(script: script, target: "TerminalContents") ?? ""
    }

    /// 仅在精确匹配到目标 tty 所在 tab 后才发送选项输入，避免误发到错误终端。
    private static func submitOption(_ value: String, to target: PromptRoutingTarget) -> Bool {
        let ttyList = "{\(target.ttyCandidates.map(appleScriptString).joined(separator: ", "))}"
        let escapedValue = appleScriptString(value)
        let script = """
        set matchedWindowIndex to -1
        set matchedTabIndex to -1
        tell application "Terminal"
            repeat with targetTTY in \(ttyList)
                set targetTTYValue to contents of targetTTY
                repeat with windowIndex from 1 to count of windows
                    set windowRef to window windowIndex
                    repeat with tabIndex from 1 to count of tabs of windowRef
                        try
                            set tabRef to tab tabIndex of windowRef
                            set tabTTY to tty of tabRef
                            set normalizedTTY to tabTTY
                            if normalizedTTY starts with "/dev/" then
                                set normalizedTTY to text 6 thru -1 of normalizedTTY
                            end if
                            if tabTTY is targetTTYValue or normalizedTTY is targetTTYValue then
                                set matchedWindowIndex to windowIndex
                                set matchedTabIndex to tabIndex
                                exit repeat
                            end if
                        end try
                    end repeat
                    if matchedWindowIndex is not -1 then exit repeat
                end repeat
                if matchedWindowIndex is not -1 then exit repeat
            end repeat

            if matchedWindowIndex is not -1 and matchedTabIndex is not -1 then
                activate
                set targetWindow to window matchedWindowIndex
                set selected tab of targetWindow to tab matchedTabIndex of targetWindow
                set index of targetWindow to 1
            end if
        end tell

        if matchedWindowIndex is -1 or matchedTabIndex is -1 then
            return "miss"
        end if

        tell application "System Events"
            tell process "Terminal"
                set frontmost to true
                delay 0.05
                keystroke \(escapedValue)
                delay 0.05
                key code 36
            end tell
        end tell
        return "ok"
        """

        return run(script: script, target: "TerminalSubmit") == "ok"
    }

    /// 从终端内容中提取可展示的编号选项 prompt。
    private static func parsePrompt(from contents: String, agentId: String) -> InteractivePrompt? {
        let lines = contents
            .components(separatedBy: .newlines)
            .map { $0.replacingOccurrences(of: "\t", with: " ").trimmingCharacters(in: .whitespaces) }

        let regex = try? NSRegularExpression(pattern: #"^[›>]*\s*(\d+)\.\s+(.+?)\s*$"#)
        var matches: [(index: Int, number: String, title: String)] = []

        for (index, line) in lines.enumerated() {
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            guard
                let regex,
                let match = regex.firstMatch(in: line, options: [], range: range),
                let numberRange = Range(match.range(at: 1), in: line),
                let titleRange = Range(match.range(at: 2), in: line)
            else {
                continue
            }

            matches.append((index, String(line[numberRange]), String(line[titleRange]).trimmingCharacters(in: .whitespaces)))
        }

        guard matches.count >= 2 else { return nil }

        var groups: [[(index: Int, number: String, title: String)]] = []
        var currentGroup: [(index: Int, number: String, title: String)] = []

        for match in matches {
            if let previous = currentGroup.last, match.index - previous.index > 3 {
                if currentGroup.count >= 2 {
                    groups.append(currentGroup)
                }
                currentGroup = []
            }
            currentGroup.append(match)
        }
        if currentGroup.count >= 2 {
            groups.append(currentGroup)
        }

        guard let group = groups.last else { return nil }

        var options: [InteractiveOption] = []
        for (offset, item) in group.enumerated() {
            let nextIndex = offset + 1 < group.count ? group[offset + 1].index : lines.count
            var detailLines: [String] = []
            if nextIndex > item.index + 1 {
                for line in lines[(item.index + 1)..<nextIndex] {
                    if line.isEmpty || line.contains("Enter to select") || line.contains("Esc to cancel") {
                        continue
                    }
                    detailLines.append(line)
                }
            }

            options.append(
                InteractiveOption(
                    id: "\(agentId)-option-\(item.number)",
                    value: item.number,
                    title: item.title,
                    detail: detailLines.isEmpty ? nil : detailLines.joined(separator: " ")
                )
            )
        }

        guard !options.isEmpty else { return nil }

        let title = promptTitle(from: lines, before: group[0].index)
        return InteractivePrompt(
            id: "\(agentId)-prompt-\(options.map(\.value).joined(separator: "-"))",
            title: title,
            message: nil,
            options: options,
            timestamp: Date()
        )
    }

    /// 选择最接近选项组的上一行文本作为 prompt 标题。
    private static func promptTitle(from lines: [String], before firstOptionIndex: Int) -> String {
        guard firstOptionIndex > 0 else { return "Action Required" }

        for index in stride(from: firstOptionIndex - 1, through: max(0, firstOptionIndex - 6), by: -1) {
            let line = cleanedPromptTitle(lines[index])
            if !line.isEmpty {
                return line
            }
        }

        return "Action Required"
    }

    /// 清理提示标题中的无关符号和明显错误信息。
    private static func cleanedPromptTitle(_ line: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if trimmed.contains("Denied in NotchMonitor") || trimmed.contains("Error:") {
            return ""
        }

        let cleaned = trimmed.replacingOccurrences(
            of: #"^[^A-Za-z0-9\u4e00-\u9fa5]*"#,
            with: "",
            options: .regularExpression
        )
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 执行 AppleScript，并把失败细节落到交互日志中。
    private static func run(script: String, target: String) -> String? {
        var error: NSDictionary?
        let appleScript = NSAppleScript(source: script)
        let result = appleScript?.executeAndReturnError(&error)

        if let error {
            log("applescript failed target=\(target) error=\(error)")
        }

        return result?.stringValue
    }

    /// 对插入 AppleScript 的字符串做最小必要转义。
    private static func appleScriptString(_ string: String) -> String {
        "\"\(string.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\""
    }

    /// 追加写入交互 prompt 诊断日志。
    private static func log(_ message: String) {
        guard ProcessInfo.processInfo.environment["NOTCH_MONITOR_DEBUG"] == "1" else { return }
        let line = "[\(ISO8601DateFormatter().string(from: Date()))] \(message)\n"
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logURL.path) {
                if let handle = try? FileHandle(forWritingTo: logURL) {
                    _ = try? handle.seekToEnd()
                    try? handle.write(contentsOf: data)
                    try? handle.close()
                }
            } else {
                try? data.write(to: logURL)
            }
        }
    }
}
