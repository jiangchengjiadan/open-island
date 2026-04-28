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
        let iTermSessionTokens = iTermSessionTokens(from: agent)
        let tmuxTarget = agent.environmentHints?["TMUX_TARGET"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let tmuxSocketPath = agent.environmentHints?["TMUX_SOCKET_PATH"]?.trimmingCharacters(in: .whitespacesAndNewlines)

        log("jump requested agent=\(agent.name) terminalHint=\(terminalHint) titleToken=\(terminalTitleToken ?? "") app=\(descriptor.debugName) bundle=\(descriptor.bundleIdentifier ?? "") tty=\(ttyCandidates.joined(separator: ",")) cwd=\(cwd ?? "") iTermSession=\(iTermSessionTokens.joined(separator: ",")) tmuxTarget=\(tmuxTarget ?? "") pid=\(agent.pid.map(String.init) ?? "")")

        let tmuxPaneSelected = jumpToTmuxPane(tmuxTarget: tmuxTarget, tmuxSocketPath: tmuxSocketPath, ttyCandidates: ttyCandidates)
        if tmuxPaneSelected {
            log("tmux pane selected target=\(tmuxTarget ?? "")")
        }

        for attempt in 1...3 {
            activatePreferredApplication(for: descriptor)

            if attempt > 1 {
                usleep(100_000)
            } else {
                usleep(35_000)
            }

            for target in descriptor.preferredTargets {
                if jump(to: target, ttyCandidates: ttyCandidates, iTermSessionTokens: iTermSessionTokens, terminalTitleToken: terminalTitleToken, cwd: cwd, descriptor: descriptor) {
                    log("jump succeeded target=\(target.rawValue) attempt=\(attempt)")
                    return
                }
            }

            log("jump retry scheduled attempt=\(attempt) app=\(descriptor.debugName)")
        }

        if tmuxPaneSelected {
            activateBestEffort(for: descriptor)
            log("jump completed via tmux pane selection with app activation for app=\(descriptor.debugName)")
            return
        }

        if ttyCandidates.isEmpty || descriptor.requiresActivationFallback {
            activateBestEffort(for: descriptor)
            log("jump fell back to app activation for app=\(descriptor.debugName)")
        } else {
            log("jump aborted without activation because no exact target matched after retries")
        }
    }

    private static func activatePreferredApplication(for descriptor: AppDescriptor) {
        if let bundleIdentifier = descriptor.bundleIdentifier {
            activateApplication(bundleIdentifier: bundleIdentifier)
            return
        }

        if let appName = descriptor.localizedName {
            _ = activateApplication(named: appName)
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

    private static func iTermSessionTokens(from agent: Agent) -> [String] {
        guard let rawValue = agent.environmentHints?["ITERM_SESSION_ID"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawValue.isEmpty else {
            return []
        }

        var tokens = [rawValue]
        if let prefix = rawValue.split(separator: ":").first.map(String.init),
           !prefix.isEmpty,
           !tokens.contains(prefix) {
            tokens.append(prefix)
        }
        return tokens
    }

    private static func jump(to target: JumpTarget, ttyCandidates: [String], iTermSessionTokens: [String], terminalTitleToken: String?, cwd: String?, descriptor: AppDescriptor) -> Bool {
        if target == .editorIDE,
           jumpToEditorWorkspace(cwd: cwd, descriptor: descriptor) {
            return true
        }

        let script = target.script(ttyCandidates: ttyCandidates, iTermSessionTokens: iTermSessionTokens, terminalTitleToken: terminalTitleToken, cwd: cwd, descriptor: descriptor)
        let result = run(script: script, target: target.rawValue)
        return result == "ok"
    }

    private static func jumpToTmuxPane(tmuxTarget: String?, tmuxSocketPath: String?, ttyCandidates: [String]) -> Bool {
        guard let tmuxTarget, !tmuxTarget.isEmpty else { return false }
        guard let tmuxPath = resolveTmuxPath() else {
            log("tmux jump skipped because tmux executable could not be resolved")
            return false
        }

        let socketArgs: [String]
        if let tmuxSocketPath, !tmuxSocketPath.isEmpty {
            socketArgs = ["-S", tmuxSocketPath]
        } else {
            socketArgs = []
        }

        let sessionWindow: String
        if let dotIndex = tmuxTarget.lastIndex(of: ".") {
            sessionWindow = String(tmuxTarget[..<dotIndex])
        } else {
            sessionWindow = tmuxTarget
        }

        let sessionName: String
        if let colonIndex = tmuxTarget.firstIndex(of: ":") {
            sessionName = String(tmuxTarget[..<colonIndex])
        } else {
            sessionName = tmuxTarget
        }

        let clientTTY = runTmuxCommand(tmuxPath: tmuxPath, socketArgs: socketArgs, args: ["list-clients", "-F", "#{client_tty}"])?
            .split(separator: "\n")
            .map(String.init)
            .first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })

        if let clientTTY, !clientTTY.isEmpty {
            _ = runTmuxCommand(tmuxPath: tmuxPath, socketArgs: socketArgs, args: ["switch-client", "-c", clientTTY, "-t", sessionName])
        } else {
            log("tmux client tty missing for target=\(tmuxTarget); skipping switch-client")
        }

        _ = runTmuxCommand(tmuxPath: tmuxPath, socketArgs: socketArgs, args: ["select-window", "-t", sessionWindow])
        let result = runTmuxCommand(tmuxPath: tmuxPath, socketArgs: socketArgs, args: ["select-pane", "-t", tmuxTarget])
        return result != nil
    }

    private static func runTmuxCommand(tmuxPath: String, socketArgs: [String], args: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tmuxPath)
        process.arguments = socketArgs + args

        let outPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            log("tmux command failed to launch args=\((socketArgs + args).joined(separator: " ")) error=\(error.localizedDescription)")
            return nil
        }

        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            if let errorText = String(data: errorData, encoding: .utf8), !errorText.isEmpty {
                log("tmux command failed args=\((socketArgs + args).joined(separator: " ")) output=\(errorText.trimmingCharacters(in: .whitespacesAndNewlines))")
            }
            return nil
        }

        let output = outPipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: output, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func resolveTmuxPath() -> String? {
        let candidates = [
            "/opt/homebrew/bin/tmux",
            "/usr/local/bin/tmux",
            "/usr/bin/tmux",
        ]

        if let found = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return found
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["tmux"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return nil
        }

        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        let path = String(data: output, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return path.isEmpty ? nil : path
    }

    private static func normalizedTTYCandidate(_ tty: String?) -> String? {
        guard let tty else { return nil }
        let trimmed = tty.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("/dev/") {
            return String(trimmed.dropFirst("/dev/".count))
        }
        return trimmed
    }

    private static func jumpToEditorWorkspace(cwd: String?, descriptor: AppDescriptor) -> Bool {
        guard let cwd, !cwd.isEmpty else { return false }
        guard FileManager.default.fileExists(atPath: cwd) else { return false }
        guard let cliPath = editorCLIPath(for: descriptor) else {
            log("editor workspace jump skipped because cli could not be resolved app=\(descriptor.debugName)")
            return false
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: cliPath)
        process.arguments = ["-r", cwd]
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            log("editor workspace jump failed to launch app=\(descriptor.debugName) cli=\(cliPath) error=\(error.localizedDescription)")
            return false
        }

        process.waitUntilExit()
        if process.terminationStatus == 0 {
            log("editor workspace jump succeeded app=\(descriptor.debugName) cli=\(cliPath) cwd=\(cwd)")
            return true
        }

        let errorData = (process.standardError as? Pipe)?.fileHandleForReading.readDataToEndOfFile() ?? Data()
        let errorText = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        log("editor workspace jump failed app=\(descriptor.debugName) cli=\(cliPath) cwd=\(cwd) status=\(process.terminationStatus) error=\(errorText)")
        return false
    }

    private static func editorCLIPath(for descriptor: AppDescriptor) -> String? {
        let executableName: String
        switch descriptor.kind {
        case .vscode:
            executableName = "code"
        case .cursor:
            executableName = "cursor"
        default:
            return nil
        }

        if let bundleIdentifier = descriptor.bundleIdentifier,
           let runningApp = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first,
           let bundleURL = runningApp.bundleURL {
            let bundleCLI = bundleURL
                .appendingPathComponent("Contents/Resources/app/bin")
                .appendingPathComponent(executableName)
                .path
            if FileManager.default.isExecutableFile(atPath: bundleCLI) {
                return bundleCLI
            }
        }

        let candidates = [
            "/opt/homebrew/bin/\(executableName)",
            "/usr/local/bin/\(executableName)",
            "/usr/bin/\(executableName)",
            "\(NSHomeDirectory())/.local/bin/\(executableName)",
            "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code",
            "/Applications/Visual Studio Code - Insiders.app/Contents/Resources/app/bin/code-insiders",
            "/Applications/Cursor.app/Contents/Resources/app/bin/cursor",
            "\(NSHomeDirectory())/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code",
            "\(NSHomeDirectory())/Applications/Visual Studio Code - Insiders.app/Contents/Resources/app/bin/code-insiders",
            "\(NSHomeDirectory())/Applications/Cursor.app/Contents/Resources/app/bin/cursor",
        ]

        if let found = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return found
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [executableName]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return nil
        }

        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        let path = String(data: output, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return path.isEmpty ? nil : path
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

    private static func activateApplication(named appName: String) -> Bool {
        guard let app = NSWorkspace.shared.runningApplications.first(where: {
            ($0.localizedName ?? "").caseInsensitiveCompare(appName) == .orderedSame
        }) else {
            return false
        }

        let activated = app.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        log("activated appName=\(appName) success=\(activated)")
        return activated
    }

    private static func activateBestEffort(for descriptor: AppDescriptor) {
        if let bundleIdentifier = descriptor.bundleIdentifier {
            activateApplication(bundleIdentifier: bundleIdentifier)
            return
        }

        guard let appName = descriptor.localizedName else { return }
        if activateApplication(named: appName) {
            return
        }

        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: descriptor.fallbackBundleIdentifier ?? bundleIdentifier(for: appName))

        guard let url else {
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
        case "Ghostty":
            return "com.mitchellh.ghostty"
        case "Warp":
            return "dev.warp.Warp-Stable"
        case "Visual Studio Code":
            return "com.microsoft.VSCode"
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
            case .ghostty:
                return [.ghostty]
            case .warp:
                return [.warp]
            case .vscode, .cursor:
                return [.editorIDE]
            case .jetBrains:
                return [.jetBrains]
            case .unknown:
                return [.terminalApp, .iTerm]
            }
        }

        var requiresActivationFallback: Bool {
            switch kind {
            case .jetBrains, .vscode, .cursor:
                return true
            default:
                return false
            }
        }

        static func resolve(for agent: Agent) -> AppDescriptor {
            let inferredHint = preferredTerminalHint(for: agent)
            let explicit = fromTerminalHint(inferredHint)

            if shouldPreferProcessTree(for: explicit), let pid = agent.pid, let app = applicationForProcessTree(pid: pid) {
                let resolved = fromRunningApplication(app)
                log("resolved via process tree for ambiguous terminal hint hint=\(inferredHint ?? "") app=\(resolved.debugName) bundle=\(resolved.bundleIdentifier ?? "") pid=\(pid)")
                return resolved
            }

            if let explicit {
                log("resolved via terminal hint hint=\(inferredHint ?? "") app=\(explicit.debugName) bundle=\(explicit.bundleIdentifier ?? "")")
                return explicit
            }

            if let pid = agent.pid, let app = applicationForProcessTree(pid: pid) {
                let resolved = fromRunningApplication(app)
                log("resolved via process tree app=\(resolved.debugName) bundle=\(resolved.bundleIdentifier ?? "") pid=\(pid)")
                return resolved
            }

            if shouldTryJetBrainsFallback(for: inferredHint),
               let fallback = singleRunningJetBrainsApplication(cwd: agent.cwd) {
                log("resolved via JetBrains fallback hint=\(inferredHint ?? "") app=\(fallback.debugName) bundle=\(fallback.bundleIdentifier ?? "") cwd=\(agent.cwd ?? "")")
                return fallback
            }

            log("resolved as unknown hint=\(inferredHint ?? "") pid=\(agent.pid.map(String.init) ?? "")")
            return AppDescriptor(kind: .unknown, localizedName: inferredHint, bundleIdentifier: nil)
        }

        private static func preferredTerminalHint(for agent: Agent) -> String? {
            let explicit = normalizedHint(agent.terminalApp)
            if let explicit, !genericTerminalHints.contains(explicit.lowercased()) {
                return explicit
            }

            if let envHints = agent.environmentHints {
                if let app = normalizedHint(envHints["TERM_PROGRAM_APP"]) {
                    return app
                }

                if let program = normalizedHint(envHints["TERM_PROGRAM"]) {
                    if program.lowercased() == "vscode", envHints["VSCODE_GIT_IPC_HANDLE"] != nil {
                        return inferredEditorHost(from: agent.processChain) ?? "Visual Studio Code"
                    }
                    return program
                }

                if envHints["ITERM_SESSION_ID"] != nil {
                    return "iTerm"
                }
            }

            if let inferred = inferredEditorHost(from: agent.processChain) {
                return inferred
            }

            return explicit
        }

        private static func inferredEditorHost(from processChain: [String]?) -> String? {
            let joined = (processChain ?? []).joined(separator: " ").lowercased()
            if joined.contains("cursor") {
                return "Cursor"
            }
            if joined.contains("visual studio code") || joined.contains("vscode") || joined.contains(":code ") || joined.hasSuffix(":code") {
                return "Visual Studio Code"
            }
            if joined.contains("iterm") {
                return "iTerm"
            }
            if joined.contains("terminal") {
                return "Terminal"
            }
            return nil
        }

        private static func normalizedHint(_ value: String?) -> String? {
            guard let value else { return nil }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
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
            if lowercased.contains("ghostty") {
                return AppDescriptor(kind: .ghostty, localizedName: "Ghostty", bundleIdentifier: "com.mitchellh.ghostty")
            }
            if lowercased.contains("warp") {
                return AppDescriptor(kind: .warp, localizedName: "Warp", bundleIdentifier: "dev.warp.Warp-Stable")
            }
            if lowercased.contains("visual studio code") || lowercased == "code" || lowercased.contains("vscode") {
                return AppDescriptor(kind: .vscode, localizedName: "Visual Studio Code", bundleIdentifier: "com.microsoft.VSCode")
            }
            if lowercased.contains("cursor") {
                return AppDescriptor(kind: .cursor, localizedName: "Cursor", bundleIdentifier: nil)
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
            if lowercased.contains("ghostty") || bundleIdentifier == "com.mitchellh.ghostty" {
                return AppDescriptor(kind: .ghostty, localizedName: localizedName ?? "Ghostty", bundleIdentifier: bundleIdentifier ?? "com.mitchellh.ghostty")
            }
            if lowercased.contains("warp") || bundleIdentifier == "dev.warp.Warp-Stable" {
                return AppDescriptor(kind: .warp, localizedName: localizedName ?? "Warp", bundleIdentifier: bundleIdentifier ?? "dev.warp.Warp-Stable")
            }
            if lowercased.contains("visual studio code") || bundleIdentifier == "com.microsoft.VSCode" || bundleIdentifier == "com.microsoft.vscode" || lowercased.contains("vscode") {
                return AppDescriptor(kind: .vscode, localizedName: localizedName ?? "Visual Studio Code", bundleIdentifier: bundleIdentifier ?? "com.microsoft.VSCode")
            }
            if lowercased.contains("cursor") {
                return AppDescriptor(kind: .cursor, localizedName: localizedName ?? "Cursor", bundleIdentifier: bundleIdentifier)
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
        case ghostty
        case warp
        case vscode
        case cursor
        case jetBrains
        case unknown
    }
}

private enum JumpTarget: String {
    case terminalApp = "Terminal"
    case iTerm = "iTerm"
    case ghostty = "Ghostty"
    case warp = "Warp"
    case editorIDE = "EditorIDE"
    case jetBrains = "JetBrains"

    func script(ttyCandidates: [String], iTermSessionTokens: [String], terminalTitleToken: String?, cwd: String?, descriptor: TerminalJumpService.AppDescriptor) -> String {
        switch self {
        case .terminalApp:
            return terminalScript(ttyCandidates: ttyCandidates, cwd: cwd)
        case .iTerm:
            return iTermScript(ttyCandidates: ttyCandidates, iTermSessionTokens: iTermSessionTokens, terminalTitleToken: terminalTitleToken, cwd: cwd)
        case .ghostty:
            return ghosttyScript(cwd: cwd)
        case .warp:
            return warpScript(cwd: cwd)
        case .editorIDE:
            return editorIDEScript(cwd: cwd, descriptor: descriptor)
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
                set targetTTYValue to targetTTY
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

    private func iTermScript(ttyCandidates: [String], iTermSessionTokens: [String], terminalTitleToken: String?, cwd: String?) -> String {
        let ttyList = appleScriptList(ttyCandidates)
        let sessionIDList = appleScriptList(iTermSessionTokens)
        let titleToken = appleScriptString(terminalTitleToken ?? "")
        let escapedCwd = appleScriptString(cwd ?? "")
        return """
        tell application "iTerm"
            if not (it is running) then return "miss"
            activate
            repeat with targetSessionID in \(sessionIDList)
                set targetSessionValue to targetSessionID
                if targetSessionValue is not "" then
                    repeat with aWindow in windows
                        repeat with aTab in tabs of aWindow
                            repeat with aSession in sessions of aTab
                                try
                                    if (id of aSession as text) is targetSessionValue then
                                        select aWindow
                                        tell aWindow to select aTab
                                        select aSession
                                        return "ok"
                                    end if
                                end try
                            end repeat
                        end repeat
                    end repeat
                end if
            end repeat

            repeat with targetTTY in \(ttyList)
                set targetTTYValue to targetTTY
                repeat with aWindow in windows
                    repeat with aTab in tabs of aWindow
                        repeat with aSession in sessions of aTab
                            try
                                set sessionTTY to tty of aSession
                                set normalizedTTY to sessionTTY
                                if normalizedTTY starts with "/dev/" then
                                    set normalizedTTY to text 6 thru -1 of normalizedTTY
                                end if
                                if sessionTTY is targetTTYValue or normalizedTTY is targetTTYValue then
                                    select aWindow
                                    tell aWindow to select aTab
                                    select aSession
                                    return "ok"
                                end if
                            end try
                        end repeat
                    end repeat
                end repeat
            end repeat

            if \(titleToken) is not "" then
                repeat with aWindow in windows
                    repeat with aTab in tabs of aWindow
                        repeat with aSession in sessions of aTab
                            try
                                if (name of aSession as text) contains \(titleToken) then
                                    select aWindow
                                    tell aWindow to select aTab
                                    select aSession
                                    return "ok"
                                end if
                            end try
                        end repeat
                    end repeat
                end repeat
            end if

            if \(escapedCwd) is not "" then
                repeat with aWindow in windows
                    repeat with aTab in tabs of aWindow
                        repeat with aSession in sessions of aTab
                            try
                                set sessionName to name of aSession
                                if sessionName contains \(escapedCwd) then
                                    select aWindow
                                    tell aWindow to select aTab
                                    select aSession
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

    private func ghosttyScript(cwd: String?) -> String {
        let workingDirectories = ghosttyWorkingDirectoryTokens(from: cwd)
        let nameTokens = projectWindowTokens(from: cwd)
        let directoryList = appleScriptList(workingDirectories)
        let nameTokenList = appleScriptList(nameTokens)
        return """
        tell application "Ghostty"
            activate
            repeat with targetDirectory in \(directoryList)
                set directoryValue to contents of targetDirectory
                if directoryValue is not "" then
                    try
                        set matches to every terminal whose working directory contains directoryValue
                        if (count of matches) > 0 then
                            focus item 1 of matches
                            return "ok"
                        end if
                    end try
                end if
            end repeat

            repeat with targetToken in \(nameTokenList)
                set tokenValue to contents of targetToken
                if tokenValue is not "" then
                    try
                        set matches to every terminal whose name contains tokenValue
                        if (count of matches) > 0 then
                            focus item 1 of matches
                            return "ok"
                        end if
                    end try
                end if
            end repeat
        end tell
        return "miss"
        """
    }

    private func warpScript(cwd: String?) -> String {
        let projectTokens = appleScriptList(projectWindowTokens(from: cwd))
        let processName = appleScriptString("Warp")
        return """
        set matchedWindowName to ""
        tell application "Warp"
            activate
        end tell
        delay 0.08
        tell application "System Events"
            if exists process \(processName) then
                tell process \(processName)
                    set frontmost to true
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

    private func editorIDEScript(cwd: String?, descriptor: TerminalJumpService.AppDescriptor) -> String {
        let processNames = appleScriptList(editorProcessNames(for: descriptor))
        let projectTokens = appleScriptList(projectWindowTokens(from: cwd))
        return """
        set matchedWindowName to ""
        set didActivate to false
        tell application "System Events"
            repeat with targetProcess in \(processNames)
                if matchedWindowName is "" then
                    set processValue to contents of targetProcess
                    if exists process processValue then
                        tell process processValue
                            set frontmost to true
                            set didActivate to true
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
                            if matchedWindowName is "" then
                                try
                                    if (count of windows) > 0 then
                                        perform action "AXRaise" of window 1
                                        try
                                            set matchedWindowName to name of window 1
                                        on error
                                            set matchedWindowName to "__frontmost__"
                                        end try
                                    else
                                        set matchedWindowName to "__frontmost__"
                                    end if
                                end try
                            end if
                        end tell
                    end if
                end if
            end repeat
        end tell
        if matchedWindowName is not "" or didActivate then
            return "ok"
        end if
        return "miss"
        """
    }

    private func editorProcessNames(for descriptor: TerminalJumpService.AppDescriptor) -> [String] {
        switch descriptor.kind {
        case .vscode:
            return ["Code", "Visual Studio Code"]
        case .cursor:
            return ["Cursor"]
        default:
            if let localizedName = descriptor.localizedName, !localizedName.isEmpty {
                return [localizedName]
            }
            return ["Cursor"]
        }
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

    private func ghosttyWorkingDirectoryTokens(from cwd: String?) -> [String] {
        guard let cwd else { return [] }

        let normalized = cwd.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return [] }

        var tokens = [normalized]
        let parent = URL(fileURLWithPath: normalized).deletingLastPathComponent().path
        if !parent.isEmpty, parent != normalized {
            tokens.append(parent)
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
