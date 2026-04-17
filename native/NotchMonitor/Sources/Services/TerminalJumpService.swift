import Foundation
import AppKit

enum TerminalJumpService {
    private static let logURL = URL(fileURLWithPath: "/tmp/notch-monitor-jump.log")

    static func jump(to agent: Agent) {
        DispatchQueue.global(qos: .userInitiated).async {
            performJump(to: agent)
        }
    }

    static func jumpSynchronously(to agent: Agent) {
        performJump(to: agent)
    }

    private static func performJump(to agent: Agent) {
        let descriptor = AppDescriptor.resolve(for: agent)
        let ttyCandidates = normalizedTTYCandidates(from: agent.tty ?? agent.terminal)
        let cwd = agent.cwd?.trimmingCharacters(in: .whitespacesAndNewlines)
        let terminalHint = (agent.terminalApp ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let terminalTitleToken = agent.terminalTitleToken?.trimmingCharacters(in: .whitespacesAndNewlines)

        log("jump requested agent=\(agent.name) terminalHint=\(terminalHint) titleToken=\(terminalTitleToken ?? "") app=\(descriptor.debugName) bundle=\(descriptor.bundleIdentifier ?? "") tty=\(ttyCandidates.joined(separator: ",")) cwd=\(cwd ?? "") pid=\(agent.pid.map(String.init) ?? "")")

        for attempt in 1...3 {
            if let bundleIdentifier = descriptor.bundleIdentifier {
                activateApplication(bundleIdentifier: bundleIdentifier)
            }

            if attempt > 1 {
                usleep(100_000)
            } else {
                usleep(35_000)
            }

            for target in descriptor.preferredTargets {
                if jump(to: target, ttyCandidates: ttyCandidates, terminalTitleToken: terminalTitleToken, cwd: cwd, descriptor: descriptor) {
                    log("jump succeeded target=\(target.rawValue) attempt=\(attempt)")
                    return
                }
            }

            log("jump retry scheduled attempt=\(attempt) app=\(descriptor.debugName)")
        }

        if ttyCandidates.isEmpty || descriptor.requiresActivationFallback {
            activateBestEffort(for: descriptor)
            log("jump fell back to app activation for app=\(descriptor.debugName)")
        } else {
            log("jump aborted without activation because no exact target matched after retries")
        }
    }

    private static func normalizedTTYCandidates(from hint: String) -> [String] {
        let raw = hint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return [] }

        var values = Set<String>()
        values.insert(raw)
        if raw.hasPrefix("/dev/") {
            values.insert(String(raw.dropFirst("/dev/".count)))
        } else if raw.hasPrefix("ttys") || raw.hasPrefix("pts/") {
            values.insert("/dev/\(raw)")
        }

        return Array(values)
    }

    private static func jump(to target: JumpTarget, ttyCandidates: [String], terminalTitleToken: String?, cwd: String?, descriptor: AppDescriptor) -> Bool {
        let script = target.script(ttyCandidates: ttyCandidates, terminalTitleToken: terminalTitleToken, cwd: cwd, descriptor: descriptor)
        let result = run(script: script, target: target.rawValue)
        return result == "ok"
    }

    private static func run(script: String, target: String) -> String? {
        var error: NSDictionary?
        let appleScript = NSAppleScript(source: script)
        let result = appleScript?.executeAndReturnError(&error)

        if let error {
            log("applescript failed target=\(target) error=\(error)")
        }

        if let stringValue = result?.stringValue {
            log("applescript result target=\(target) result=\(stringValue)")
            return stringValue
        }

        return nil
    }

    private static func activateApplication(bundleIdentifier: String) {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first else {
            return
        }

        let activated = app.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        log("activated bundle=\(bundleIdentifier) success=\(activated)")
    }

    private static func activateBestEffort(for descriptor: AppDescriptor) {
        if let bundleIdentifier = descriptor.bundleIdentifier {
            activateApplication(bundleIdentifier: bundleIdentifier)
            return
        }

        guard let appName = descriptor.localizedName else { return }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: descriptor.fallbackBundleIdentifier ?? bundleIdentifier(for: appName)) else {
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
            if let error {
                log("best-effort activation failed app=\(appName) error=\(error.localizedDescription)")
            }
        }
    }

    private static func bundleIdentifier(for appName: String) -> String {
        switch appName {
        case "iTerm":
            return "com.googlecode.iterm2"
        case "Terminal":
            return "com.apple.Terminal"
        default:
            return appName
        }
    }

    private static func parentProcessInfo(for pid: Int32) -> (ppid: Int32, command: String)? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-p", String(pid), "-o", "ppid=,comm="]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            log("ps lookup failed pid=\(pid) error=\(error.localizedDescription)")
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard let output = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !output.isEmpty
        else {
            return nil
        }

        let columns = output.split(maxSplits: 1, whereSeparator: \.isWhitespace).map(String.init)
        guard columns.count == 2, let ppid = Int32(columns[0].trimmingCharacters(in: .whitespaces)) else {
            return nil
        }

        return (ppid, URL(fileURLWithPath: columns[1].trimmingCharacters(in: .whitespaces)).lastPathComponent)
    }

    private static func applicationForProcessTree(pid: Int) -> NSRunningApplication? {
        var currentPID = Int32(pid)
        var visited = Set<Int32>()
        var chain: [String] = []

        for _ in 0..<12 {
            guard currentPID > 1, !visited.contains(currentPID) else { break }
            visited.insert(currentPID)

            if let app = NSRunningApplication(processIdentifier: currentPID),
               app.activationPolicy == .regular || app.activationPolicy == .accessory {
                let appName = app.localizedName ?? app.bundleIdentifier ?? "unknown"
                chain.append("\(currentPID):\(appName)")
                log("process tree resolved pid=\(pid) chain=\(chain.joined(separator: " -> "))")
                return app
            }

            guard let info = parentProcessInfo(for: currentPID) else { break }
            chain.append("\(currentPID):\(info.command)")
            currentPID = info.ppid
        }

        if !chain.isEmpty {
            log("process tree exhausted pid=\(pid) chain=\(chain.joined(separator: " -> "))")
        }
        return nil
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

    fileprivate struct AppDescriptor {
        let kind: AppKind
        let localizedName: String?
        let bundleIdentifier: String?

        var debugName: String {
            localizedName ?? bundleIdentifier ?? kind.rawValue
        }

        var fallbackBundleIdentifier: String? {
            bundleIdentifier
        }

        var preferredTargets: [JumpTarget] {
            switch kind {
            case .terminal:
                return [.terminalApp]
            case .iTerm:
                return [.iTerm]
            case .jetBrains:
                return [.jetBrains]
            case .unknown:
                return [.terminalApp, .iTerm]
            }
        }

        var requiresActivationFallback: Bool {
            switch kind {
            case .jetBrains:
                return true
            default:
                return false
            }
        }

        static func resolve(for agent: Agent) -> AppDescriptor {
            let explicit = fromTerminalHint(agent.terminalApp)

            if shouldPreferProcessTree(for: explicit), let pid = agent.pid, let app = applicationForProcessTree(pid: pid) {
                let resolved = fromRunningApplication(app)
                log("resolved via process tree for ambiguous terminal hint hint=\(agent.terminalApp ?? "") app=\(resolved.debugName) bundle=\(resolved.bundleIdentifier ?? "") pid=\(pid)")
                return resolved
            }

            if let explicit {
                log("resolved via terminal hint hint=\(agent.terminalApp ?? "") app=\(explicit.debugName) bundle=\(explicit.bundleIdentifier ?? "")")
                return explicit
            }

            if let pid = agent.pid, let app = applicationForProcessTree(pid: pid) {
                let resolved = fromRunningApplication(app)
                log("resolved via process tree app=\(resolved.debugName) bundle=\(resolved.bundleIdentifier ?? "") pid=\(pid)")
                return resolved
            }

            if shouldTryJetBrainsFallback(for: agent.terminalApp),
               let fallback = singleRunningJetBrainsApplication(cwd: agent.cwd) {
                log("resolved via JetBrains fallback hint=\(agent.terminalApp ?? "") app=\(fallback.debugName) bundle=\(fallback.bundleIdentifier ?? "") cwd=\(agent.cwd ?? "")")
                return fallback
            }

            log("resolved as unknown hint=\(agent.terminalApp ?? "") pid=\(agent.pid.map(String.init) ?? "")")
            return AppDescriptor(kind: .unknown, localizedName: agent.terminalApp, bundleIdentifier: nil)
        }

        private static func shouldPreferProcessTree(for descriptor: AppDescriptor?) -> Bool {
            guard let descriptor else { return false }
            return descriptor.kind == .jetBrains || descriptor.kind == .unknown
        }

        private static func shouldTryJetBrainsFallback(for hint: String?) -> Bool {
            let value = (hint ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !value.isEmpty else { return false }
            return genericTerminalHints.contains(value) || value.contains("jetbrains") || value.contains("jediterm")
        }

        private static func singleRunningJetBrainsApplication(cwd: String?) -> AppDescriptor? {
            let jetBrainsApps = NSWorkspace.shared.runningApplications.filter { app in
                let identity = "\(app.bundleIdentifier ?? "") \(app.localizedName ?? "")".lowercased()
                return identity.contains("com.jetbrains.") ||
                    identity.contains("pycharm") ||
                    identity.contains("intellij") ||
                    identity.contains("webstorm") ||
                    identity.contains("goland") ||
                    identity.contains("rubymine") ||
                    identity.contains("clion")
            }

            guard !jetBrainsApps.isEmpty else { return nil }

            if let cwd, let matched = bestJetBrainsMatch(in: jetBrainsApps, cwd: cwd) {
                return fromRunningApplication(matched)
            }

            guard jetBrainsApps.count == 1, let app = jetBrainsApps.first else { return nil }
            return fromRunningApplication(app)
        }

        private static func bestJetBrainsMatch(in apps: [NSRunningApplication], cwd: String) -> NSRunningApplication? {
            let projectName = URL(fileURLWithPath: cwd).lastPathComponent.lowercased()
            guard !projectName.isEmpty else { return nil }

            return apps.first(where: { app in
                let name = (app.localizedName ?? "").lowercased()
                let bundle = (app.bundleIdentifier ?? "").lowercased()
                return name.contains(projectName) || bundle.contains(projectName)
            })
        }

        private static func fromTerminalHint(_ hint: String?) -> AppDescriptor? {
            let value = (hint ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { return nil }
            let lowercased = value.lowercased()

            if genericTerminalHints.contains(lowercased) {
                return nil
            }

            if lowercased.contains("iterm") {
                return AppDescriptor(kind: .iTerm, localizedName: "iTerm", bundleIdentifier: "com.googlecode.iterm2")
            }
            if lowercased.contains("terminal") {
                return AppDescriptor(kind: .terminal, localizedName: "Terminal", bundleIdentifier: "com.apple.Terminal")
            }
            if lowercased.contains("jetbrains") || lowercased.contains("jediterm") || lowercased.contains("idea") || lowercased.contains("pycharm") {
                return AppDescriptor(kind: .jetBrains, localizedName: value, bundleIdentifier: nil)
            }

            return AppDescriptor(kind: .unknown, localizedName: value, bundleIdentifier: nil)
        }

        private static func fromRunningApplication(_ app: NSRunningApplication) -> AppDescriptor {
            let bundleIdentifier = app.bundleIdentifier
            let localizedName = app.localizedName
            let lowercased = "\(bundleIdentifier ?? "") \(localizedName ?? "")".lowercased()

            if lowercased.contains("iterm") {
                return AppDescriptor(kind: .iTerm, localizedName: localizedName ?? "iTerm", bundleIdentifier: bundleIdentifier ?? "com.googlecode.iterm2")
            }
            if lowercased.contains("terminal") {
                return AppDescriptor(kind: .terminal, localizedName: localizedName ?? "Terminal", bundleIdentifier: bundleIdentifier ?? "com.apple.Terminal")
            }
            if lowercased.contains("com.jetbrains.") || lowercased.contains("intellij") || lowercased.contains("pycharm") || lowercased.contains("webstorm") || lowercased.contains("goland") || lowercased.contains("rubymine") || lowercased.contains("clion") {
                return AppDescriptor(kind: .jetBrains, localizedName: localizedName, bundleIdentifier: bundleIdentifier)
            }

            return AppDescriptor(kind: .unknown, localizedName: localizedName, bundleIdentifier: bundleIdentifier)
        }

        private static let genericTerminalHints: Set<String> = [
            "xterm",
            "xterm-256color",
            "vt100",
            "ansi",
            "screen",
            "screen-256color",
            "tmux",
            "tmux-256color",
            "dumb"
        ]
    }

    fileprivate enum AppKind: String {
        case terminal
        case iTerm
        case jetBrains
        case unknown
    }
}

private enum JumpTarget: String {
    case terminalApp = "Terminal"
    case iTerm = "iTerm"
    case jetBrains = "JetBrains"

    func script(ttyCandidates: [String], terminalTitleToken: String?, cwd: String?, descriptor: TerminalJumpService.AppDescriptor) -> String {
        switch self {
        case .terminalApp:
            return terminalScript(ttyCandidates: ttyCandidates, cwd: cwd)
        case .iTerm:
            return iTermScript(ttyCandidates: ttyCandidates, cwd: cwd)
        case .jetBrains:
            return jetBrainsScript(terminalTitleToken: terminalTitleToken, cwd: cwd, descriptor: descriptor)
        }
    }

    private func terminalScript(ttyCandidates: [String], cwd: String?) -> String {
        let ttyList = appleScriptList(ttyCandidates)
        let escapedCwd = appleScriptString(cwd ?? "")
        return """
        set targetWindowName to ""
        set targetTabIndex to -1
        tell application "Terminal"
            activate
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
                                set targetWindowName to name of windowRef
                                set targetTabIndex to tabIndex
                                exit repeat
                            end if
                        end try
                    end repeat
                    if targetWindowName is not "" then exit repeat
                end repeat
                if targetWindowName is not "" then exit repeat
            end repeat

            if targetWindowName is "" and \(escapedCwd) is not "" then
                repeat with theWindow in windows
                    set windowRef to contents of theWindow
                    try
                        if name of windowRef contains \(escapedCwd) then
                            set targetWindowName to name of windowRef
                            set targetTabIndex to index of selected tab of windowRef
                            exit repeat
                        end if
                    end try
                end repeat
            end if

            if targetWindowName is not "" and targetTabIndex is not -1 then
                repeat with theWindow in windows
                    set windowRef to contents of theWindow
                    if name of windowRef is targetWindowName then
                        set selected tab of windowRef to tab targetTabIndex of windowRef
                        exit repeat
                    end if
                end repeat
            end if
        end tell

        if targetWindowName is not "" then
            tell application "System Events"
                tell process "Terminal"
                    set frontmost to true
                    repeat with uiWindow in windows
                        if name of uiWindow is targetWindowName then
                            perform action "AXRaise" of uiWindow
                            return "ok"
                        end if
                    end repeat
                end tell
            end tell
        end if
        return "miss"
        """
    }

    private func iTermScript(ttyCandidates: [String], cwd: String?) -> String {
        let ttyList = appleScriptList(ttyCandidates)
        let escapedCwd = appleScriptString(cwd ?? "")
        return """
        tell application "iTerm"
            activate
            repeat with targetTTY in \(ttyList)
                set targetTTYValue to contents of targetTTY
                repeat with theWindow in windows
                    set windowRef to contents of theWindow
                    repeat with theTab in tabs of windowRef
                        set tabRef to contents of theTab
                        repeat with theSession in sessions of tabRef
                            set sessionRef to contents of theSession
                            try
                                set sessionTTY to tty of sessionRef
                                set normalizedTTY to sessionTTY
                                if normalizedTTY starts with "/dev/" then
                                    set normalizedTTY to text 6 thru -1 of normalizedTTY
                                end if
                                if sessionTTY is targetTTYValue or normalizedTTY is targetTTYValue then
                                    tell windowRef
                                        set current tab to tabRef
                                    end tell
                                    tell tabRef
                                        select
                                    end tell
                                    return "ok"
                                end if
                            end try
                        end repeat
                    end repeat
                end repeat
            end repeat

            if \(escapedCwd) is not "" then
                repeat with theWindow in windows
                    set windowRef to contents of theWindow
                    repeat with theTab in tabs of windowRef
                        set tabRef to contents of theTab
                        repeat with theSession in sessions of tabRef
                            set sessionRef to contents of theSession
                            try
                                set sessionName to name of sessionRef
                                if sessionName contains \(escapedCwd) then
                                    tell windowRef
                                        set current tab to tabRef
                                    end tell
                                    tell tabRef
                                        select
                                    end tell
                                    return "ok"
                                end if
                            end try
                        end repeat
                    end repeat
                end repeat
            end if
        end tell
        return "miss"
        """
    }

    private func jetBrainsScript(terminalTitleToken: String?, cwd: String?, descriptor: TerminalJumpService.AppDescriptor) -> String {
        let appReference: String
        if let bundleIdentifier = descriptor.bundleIdentifier, !bundleIdentifier.isEmpty {
            appReference = "id \(appleScriptString(bundleIdentifier))"
        } else {
            appReference = appleScriptString(descriptor.localizedName ?? "IntelliJ IDEA")
        }
        let processName = appleScriptString(descriptor.localizedName ?? "IntelliJ IDEA")
        let terminalToken = appleScriptString(terminalTitleToken ?? "")
        let projectTokens = appleScriptList(projectWindowTokens(from: cwd))
        return """
        set matchedWindowName to ""
        tell application \(appReference)
            activate
        end tell
        delay 0.08
        tell application "System Events"
            if exists process \(processName) then
                tell process \(processName)
                    set frontmost to true
                    if \(terminalToken) is not "" then
                        repeat with uiWindow in windows
                            try
                                set windowName to name of uiWindow
                                if windowName contains \(terminalToken) then
                                    perform action "AXRaise" of uiWindow
                                    set matchedWindowName to windowName
                                    exit repeat
                                end if
                            end try
                        end repeat
                    end if
                    repeat with targetToken in \(projectTokens)
                        if matchedWindowName is "" then
                            set tokenValue to contents of targetToken
                            if tokenValue is not "" then
                                repeat with uiWindow in windows
                                    try
                                        set windowName to name of uiWindow
                                        if windowName contains tokenValue then
                                            perform action "AXRaise" of uiWindow
                                            set matchedWindowName to windowName
                                            exit repeat
                                        end if
                                    end try
                                end repeat
                            end if
                        end if
                    end repeat
                end tell
            end if
        end tell
        if matchedWindowName is not "" then
            return "ok"
        end if
        return "miss"
        """
    }

    private func projectWindowTokens(from cwd: String?) -> [String] {
        guard let cwd, !cwd.isEmpty else { return [] }

        let url = URL(fileURLWithPath: cwd)
        var tokens: [String] = []

        let projectName = url.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        if !projectName.isEmpty {
            tokens.append(projectName)
        }

        let parentName = url.deletingLastPathComponent().lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        if !parentName.isEmpty, !tokens.contains(parentName) {
            tokens.append(parentName)
        }

        let fullPath = cwd.trimmingCharacters(in: .whitespacesAndNewlines)
        if !fullPath.isEmpty, !tokens.contains(fullPath) {
            tokens.append(fullPath)
        }

        return tokens
    }

    private func appleScriptList(_ strings: [String]) -> String {
        let quoted = strings.map(appleScriptString)
        return "{\(quoted.joined(separator: ", "))}"
    }

    private func appleScriptString(_ string: String) -> String {
        "\"\(string.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\""
    }
}
