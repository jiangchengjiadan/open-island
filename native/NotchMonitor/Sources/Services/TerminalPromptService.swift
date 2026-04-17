import Foundation
import AppKit

enum TerminalPromptService {
    private static let logURL = URL(fileURLWithPath: "/tmp/notch-monitor-interactive.log")

    static func detectPrompt(for agent: Agent) -> InteractivePrompt? {
        guard isTerminalApp(agent.terminalApp), let ttyHint = normalizedTTYHint(from: agent) else {
            return nil
        }

        let ttyCandidates = ttyHint.candidates
        let contents = fetchTerminalContents(ttyCandidates: ttyCandidates).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !contents.isEmpty else {
            return nil
        }

        let prompt = parsePrompt(from: contents, agentId: agent.id)
        if let prompt {
            log("detected prompt agent=\(agent.id) title=\(prompt.title) options=\(prompt.options.count)")
        }
        return prompt
    }

    static func submit(option: InteractiveOption, to agent: Agent) {
        TerminalJumpService.jumpSynchronously(to: agent)

        let escapedValue = appleScriptString(option.value)
        let script = """
        tell application "System Events"
            tell process "Terminal"
                keystroke \(escapedValue)
                delay 0.05
                key code 36
            end tell
        end tell
        return "ok"
        """

        let result = run(script: script, target: "TerminalSelection")
        log("submitted option agent=\(agent.id) value=\(option.value) result=\(result ?? "nil")")
    }

    private static func isTerminalApp(_ terminalApp: String?) -> Bool {
        (terminalApp ?? "").lowercased().contains("terminal")
    }

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

    private static func fetchTerminalContents(ttyCandidates: [String]) -> String {
        let ttyList = "{\(ttyCandidates.map(appleScriptString).joined(separator: ", "))}"
        let script = """
        tell application "Terminal"
            repeat with targetTTY in \(ttyList)
                set targetTTYValue to contents of targetTTY
                repeat with theWindow in windows
                    set windowRef to contents of theWindow
                    try
                        set tabTTY to tty of selected tab of windowRef
                        set normalizedTTY to tabTTY
                        if normalizedTTY starts with "/dev/" then
                            set normalizedTTY to text 6 thru -1 of normalizedTTY
                        end if
                        if tabTTY is targetTTYValue or normalizedTTY is targetTTYValue then
                            return contents of selected tab of windowRef
                        end if
                    end try
                end repeat
            end repeat
        end tell
        return ""
        """

        return run(script: script, target: "TerminalContents") ?? ""
    }

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

    private static func run(script: String, target: String) -> String? {
        var error: NSDictionary?
        let appleScript = NSAppleScript(source: script)
        let result = appleScript?.executeAndReturnError(&error)

        if let error {
            log("applescript failed target=\(target) error=\(error)")
        }

        return result?.stringValue
    }

    private static func appleScriptString(_ string: String) -> String {
        "\"\(string.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\""
    }

    private static func log(_ message: String) {
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
