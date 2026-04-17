import Foundation
import Combine
import AppKit

final class AppBootstrapService: ObservableObject {
    static let shared = AppBootstrapService()

    @Published private(set) var checks: [BootstrapCheck] = []
    @Published private(set) var isBootstrapping = false
    @Published private(set) var isBridgeRunning = false
    @Published private(set) var lastBootstrapError: String?
    @Published var shouldPresentOnboarding = false

    private let runtimeQueue = DispatchQueue(label: "openisland.bootstrap", qos: .userInitiated)
    private var bridgeProcess: Process?
    private var diagnosticsTimer: Timer?
    private var didStart = false
    private let onboardingSuppressedKey = "OpenIslandOnboardingSuppressed"
    private let onboardingSeenKey = "OpenIslandOnboardingSeen"

    private init() {
        refreshDiagnostics()
    }

    var hasBlockingIssue: Bool {
        checks.contains(where: { $0.state == .blocking })
    }

    var hasIssues: Bool {
        checks.contains(where: { $0.state != .ready })
    }

    var headline: String {
        if let highestPriority = checks.sorted(by: { $0.state.priority < $1.state.priority }).first,
           highestPriority.state != .ready {
            return highestPriority.title
        }

        if isBootstrapping {
            return "Preparing Open Island"
        }

        return "Open Island"
    }

    func startIfNeeded() {
        guard !didStart else { return }
        didStart = true
        startDiagnosticsTimer()
        requestInitialOnboardingPresentation()
        runBootstrap()
    }

    func retrySetup() {
        shouldPresentOnboarding = true
        UserDefaults.standard.set(false, forKey: onboardingSuppressedKey)
        UserDefaults.standard.set(true, forKey: onboardingSeenKey)
        runBootstrap()
    }

    func refreshDiagnostics() {
        let nextChecks = makeChecks()
        DispatchQueue.main.async {
            self.checks = nextChecks
            self.requestOnboardingPresentationIfNeeded()
        }
    }

    func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    func dismissOnboarding() {
        shouldPresentOnboarding = false
        UserDefaults.standard.set(true, forKey: onboardingSuppressedKey)
        UserDefaults.standard.set(true, forKey: onboardingSeenKey)
    }

    func presentOnboarding() {
        shouldPresentOnboarding = true
        UserDefaults.standard.set(true, forKey: onboardingSeenKey)
    }

    func requestOnboardingPresentationIfNeeded() {
        if !hasBlockingIssue {
            shouldPresentOnboarding = false
            return
        }

        if !UserDefaults.standard.bool(forKey: onboardingSuppressedKey) {
            shouldPresentOnboarding = true
        }
    }

    private func requestInitialOnboardingPresentation() {
        let hasSeenOnboarding = UserDefaults.standard.bool(forKey: onboardingSeenKey)
        if !hasSeenOnboarding {
            shouldPresentOnboarding = true
            UserDefaults.standard.set(true, forKey: onboardingSeenKey)
            return
        }

        requestOnboardingPresentationIfNeeded()
    }

    func stop() {
        diagnosticsTimer?.invalidate()
        diagnosticsTimer = nil
        bridgeProcess?.terminate()
        bridgeProcess = nil
    }

    private func runBootstrap() {
        DispatchQueue.main.async {
            self.isBootstrapping = true
            self.lastBootstrapError = nil
            self.refreshDiagnostics()
        }

        runtimeQueue.async {
            self.installToolingIfPossible()
            self.startBridgeIfPossible()
            self.finishBootstrap()
        }
    }

    private func finishBootstrap() {
        DispatchQueue.main.async {
            self.isBootstrapping = false
            self.refreshDiagnostics()
            self.requestOnboardingPresentationIfNeeded()
        }
    }

    private func startDiagnosticsTimer() {
        DispatchQueue.main.async {
            self.diagnosticsTimer?.invalidate()
            self.diagnosticsTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak self] _ in
                self?.refreshDiagnostics()
            }
        }
    }

    private func installToolingIfPossible() {
        guard let nodeInvocation = nodeInvocation() else {
            noteBootstrapError("Node.js not found")
            print("OpenIsland bootstrap: Node.js not found, skipping hook installation")
            return
        }

        guard
            let autoInstallScript = runtimeScriptURL(named: "auto-install-hooks.js"),
            let codexWrapperScript = runtimeScriptURL(named: "install-codex-wrapper.js")
        else {
            noteBootstrapError("Bundled setup scripts are missing")
            print("OpenIsland bootstrap: bundled install scripts not found")
            return
        }

        runNodeScript(nodeInvocation: nodeInvocation, scriptURL: autoInstallScript)
        runNodeScript(nodeInvocation: nodeInvocation, scriptURL: codexWrapperScript)
    }

    private func startBridgeIfPossible() {
        guard bridgeProcess == nil else { return }
        guard let nodeInvocation = nodeInvocation() else {
            noteBootstrapError("Node.js not found")
            print("OpenIsland bootstrap: Node.js not found, bridge not started")
            return
        }
        guard let bridgeScript = runtimeBridgeURL(named: "server.js") else {
            noteBootstrapError("Bundled bridge runtime is missing")
            print("OpenIsland bootstrap: bundled bridge server not found")
            return
        }

        let process = Process()
        process.executableURL = nodeInvocation.executableURL
        process.arguments = nodeInvocation.arguments + [bridgeScript.path]
        process.environment = runtimeEnvironment()
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        do {
            try process.run()
            bridgeProcess = process
            DispatchQueue.main.async {
                self.isBridgeRunning = true
            }
            print("OpenIsland bootstrap: bridge started")

            process.terminationHandler = { [weak self] terminatedProcess in
                print("OpenIsland bootstrap: bridge exited with status \(terminatedProcess.terminationStatus)")
                self?.bridgeProcess = nil
                DispatchQueue.main.async {
                    self?.isBridgeRunning = false
                }
                self?.noteBootstrapError("Bridge exited with status \(terminatedProcess.terminationStatus)")
                self?.refreshDiagnostics()
            }
        } catch {
            DispatchQueue.main.async {
                self.isBridgeRunning = false
            }
            noteBootstrapError("Failed to start the local bridge")
            print("OpenIsland bootstrap: failed to start bridge - \(error.localizedDescription)")
        }
    }

    private func runNodeScript(nodeInvocation: NodeInvocation, scriptURL: URL) {
        let process = Process()
        process.executableURL = nodeInvocation.executableURL
        process.arguments = nodeInvocation.arguments + [scriptURL.path]
        process.environment = runtimeEnvironment()
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus != 0 {
                noteBootstrapError("\(scriptURL.lastPathComponent) failed")
                print("OpenIsland bootstrap: script failed \(scriptURL.lastPathComponent) status=\(process.terminationStatus)")
            }
        } catch {
            noteBootstrapError("Failed to run \(scriptURL.lastPathComponent)")
            print("OpenIsland bootstrap: failed to run \(scriptURL.lastPathComponent) - \(error.localizedDescription)")
        }
    }

    private func runtimeEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let currentPath = environment["PATH"] ?? ""
        environment["PATH"] = ["/opt/homebrew/bin", "/usr/local/bin", currentPath]
            .filter { !$0.isEmpty }
            .joined(separator: ":")
        return environment
    }

    private func nodeInvocation() -> NodeInvocation? {
        let fm = FileManager.default
        let candidatePaths = [
            "/opt/homebrew/bin/node",
            "/usr/local/bin/node",
            "/usr/bin/node"
        ]

        if let match = candidatePaths.first(where: { fm.isExecutableFile(atPath: $0) }) {
            return NodeInvocation(executableURL: URL(fileURLWithPath: match), arguments: [])
        }

        let envURL = URL(fileURLWithPath: "/usr/bin/env")
        if fm.isExecutableFile(atPath: envURL.path) {
            return NodeInvocation(executableURL: envURL, arguments: ["node"])
        }

        return nil
    }

    private func runtimeBridgeURL(named name: String) -> URL? {
        resourceBaseURL()?.appendingPathComponent("bridge").appendingPathComponent(name)
    }

    private func runtimeScriptURL(named name: String) -> URL? {
        resourceBaseURL()?.appendingPathComponent("scripts").appendingPathComponent(name)
    }

    private func resourceBaseURL() -> URL? {
        if let resourcesURL = Bundle.main.resourceURL?.appendingPathComponent("AppRuntime"),
           FileManager.default.fileExists(atPath: resourcesURL.path) {
            return resourcesURL
        }

        let sourceRuntimeURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("AppRuntime")
        if FileManager.default.fileExists(atPath: sourceRuntimeURL.path) {
            return sourceRuntimeURL
        }

        return nil
    }

    private func noteBootstrapError(_ message: String) {
        DispatchQueue.main.async {
            self.lastBootstrapError = message
        }
    }

    private func makeChecks() -> [BootstrapCheck] {
        let nodeInstalled = nodeInvocation() != nil
        let accessibilityGranted = AXIsProcessTrusted()
        let claudeInstalled = claudeHookInstalled()
        let codexWrapperInstalled = codexWrapperExists()
        let pathConfigured = shellConfigMentionsLocalBin() || currentEnvironmentContainsLocalBin()
        let socketReachable = SocketService.shared.isConnected
        let bridgeRunning = bridgeProcess?.isRunning == true

        return [
            BootstrapCheck(
                id: "node",
                title: nodeInstalled ? "Node.js is available" : "Install Node.js",
                detail: nodeInstalled
                    ? "Open Island can run the local bridge and setup scripts."
                    : "The app bundles the bridge, but it still needs Node.js on this Mac.",
                state: nodeInstalled ? .ready : .blocking,
                action: nodeInstalled ? .recheck : .retrySetup,
                actionTitle: nodeInstalled ? "Recheck" : "Retry Setup"
            ),
            BootstrapCheck(
                id: "accessibility",
                title: accessibilityGranted ? "Accessibility permission granted" : "Grant Accessibility access",
                detail: accessibilityGranted
                    ? "Jumping to Terminal, iTerm, and IDE windows is enabled."
                    : "Open Island needs Accessibility permission for hover, jump, and approval interactions.",
                state: accessibilityGranted ? .ready : .blocking,
                action: accessibilityGranted ? .recheck : .openAccessibility,
                actionTitle: accessibilityGranted ? "Recheck" : "Open Settings"
            ),
            BootstrapCheck(
                id: "claude-hooks",
                title: claudeInstalled ? "Claude hook is installed" : "Install Claude hook",
                detail: claudeInstalled
                    ? "New Claude Code sessions will register automatically."
                    : "Open Island could not confirm the Claude hook in ~/.claude/settings.json.",
                state: claudeInstalled ? .ready : (nodeInstalled ? .warning : .blocking),
                action: .retrySetup,
                actionTitle: claudeInstalled ? "Reinstall" : "Install"
            ),
            BootstrapCheck(
                id: "codex-wrapper",
                title: codexWrapperInstalled ? "Codex wrapper is installed" : "Install Codex wrapper",
                detail: codexWrapperInstalled
                    ? "New Codex sessions can register silently through ~/.local/bin/codex."
                    : "Open Island could not confirm the managed Codex wrapper in ~/.local/bin/codex.",
                state: codexWrapperInstalled ? .ready : (nodeInstalled ? .warning : .blocking),
                action: .retrySetup,
                actionTitle: codexWrapperInstalled ? "Reinstall" : "Install"
            ),
            BootstrapCheck(
                id: "shell-path",
                title: pathConfigured ? "~/.local/bin is in shell startup" : "Add ~/.local/bin to shell startup",
                detail: pathConfigured
                    ? "New terminals should resolve the Codex wrapper automatically."
                    : "New terminals may still bypass the wrapper. Add export PATH=\"$HOME/.local/bin:$PATH\" to ~/.zprofile or ~/.zshrc, then open a new shell.",
                state: pathConfigured ? .ready : .warning,
                action: .recheck,
                actionTitle: "Recheck"
            ),
            BootstrapCheck(
                id: "bridge",
                title: socketReachable ? "Local bridge connected" : (bridgeRunning ? "Waiting for bridge connection" : "Start the local bridge"),
                detail: socketReachable
                    ? "The app is connected to /tmp/notch-monitor.sock."
                    : (bridgeRunning
                        ? "The bridge process is running, but the app has not connected yet."
                        : "Open Island could not reach the bundled bridge. Retry setup if this persists."),
                state: socketReachable ? .ready : (bridgeRunning ? .running : .warning),
                action: .retrySetup,
                actionTitle: socketReachable ? "Restart" : "Retry Setup"
            )
        ]
    }

    private func claudeHookInstalled() -> Bool {
        let settingsURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude")
            .appendingPathComponent("settings.json")

        guard
            let data = try? Data(contentsOf: settingsURL),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let hooks = json["hooks"] as? [String: Any]
        else {
            return false
        }

        return hooks.values.contains { value in
            guard let entries = value as? [[String: Any]] else { return false }
            return entries.contains { entry in
                if let hooks = entry["hooks"] as? [[String: Any]] {
                    return hooks.contains { ($0["command"] as? String)?.contains("hook.js event claude") == true }
                }
                return false
            }
        }
    }

    private func codexWrapperExists() -> Bool {
        let wrapperURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local")
            .appendingPathComponent("bin")
            .appendingPathComponent("codex")

        guard let content = try? String(contentsOf: wrapperURL) else {
            return false
        }

        return content.contains("codex-wrapper.js")
    }

    private func shellConfigMentionsLocalBin() -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [".zprofile", ".zshrc", ".bash_profile", ".bashrc", ".profile"]

        return candidates.contains { fileName in
            let fileURL = home.appendingPathComponent(fileName)
            guard let content = try? String(contentsOf: fileURL) else { return false }
            return content.contains(".local/bin")
        }
    }

    private func currentEnvironmentContainsLocalBin() -> Bool {
        let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
        return path.contains("/.local/bin")
    }
}

private struct NodeInvocation {
    let executableURL: URL
    let arguments: [String]
}
