import Foundation
import Combine
import AppKit
import Darwin
import CryptoKit

final class AppBootstrapService: ObservableObject {
    static let shared = AppBootstrapService()

    @Published private(set) var checks: [BootstrapCheck] = []
    @Published private(set) var isBootstrapping = false
    @Published private(set) var isBridgeRunning = false
    @Published private(set) var isBridgeRestarting = false
    @Published private(set) var didGiveUpOnBridge = false
    @Published private(set) var lastBootstrapError: String?
    @Published var shouldPresentOnboarding = false

    private let runtimeQueue = DispatchQueue(label: "openisland.bootstrap", qos: .userInitiated)
    private var bridgeProcess: Process?
    private var diagnosticsTimer: Timer?
    private var didStart = false
    private var desiredBridgeRunning = false
    private var bridgeGeneration: UInt64 = 0
    private var consecutiveBridgeFailures = 0
    private var bridgeStartedAt: Date?
    private var restartWorkItem: DispatchWorkItem?
    private var healthyResetWorkItem: DispatchWorkItem?
    private var hasGivenUpOnBridge = false
    private let bridgeSnapshotLock = NSLock()
    private var snapshotGeneration: UInt64 = 0
    private var snapshotIsRunning = false
    private let onboardingSuppressedKey = "OpenIslandOnboardingSuppressed"
    private let onboardingSeenKey = "OpenIslandOnboardingSeen"

    private static let maxConsecutiveBridgeFailures = 5
    private static let healthyBridgeUptime: TimeInterval = 15
    private static let restartBackoffBase: TimeInterval = 0.5
    private static let restartBackoffMax: TimeInterval = 8

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
        runBootstrap(forceRestart: true)
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

    struct BridgeRuntimeSnapshot {
        let generation: UInt64
        let isRunning: Bool
    }

    func bridgeRuntimeSnapshot() -> BridgeRuntimeSnapshot {
        bridgeSnapshotLock.lock()
        defer { bridgeSnapshotLock.unlock() }
        return BridgeRuntimeSnapshot(generation: snapshotGeneration, isRunning: snapshotIsRunning)
    }

    func stop() {
        didStart = false
        diagnosticsTimer?.invalidate()
        diagnosticsTimer = nil
        runtimeQueue.sync {
            desiredBridgeRunning = false
            hasGivenUpOnBridge = false
            consecutiveBridgeFailures = 0
            cancelScheduledRestart()
            cancelHealthyReset()
            if let process = bridgeProcess {
                process.terminationHandler = nil
                _ = stopBridgeProcess(process)
            }
            bridgeProcess = nil
            bridgeStartedAt = nil
            bridgeGeneration += 1
            notifyBridgeRuntime(isRunning: false, isRestarting: false, didGiveUp: false)
        }
        isBridgeRunning = false
        isBridgeRestarting = false
        didGiveUpOnBridge = false
    }

    private func runBootstrap(forceRestart: Bool = false) {
        DispatchQueue.main.async {
            self.isBootstrapping = true
            self.lastBootstrapError = nil
            self.didGiveUpOnBridge = false
            self.isBridgeRestarting = false
            self.refreshDiagnostics()
        }

        runtimeQueue.async {
            self.desiredBridgeRunning = true
            self.hasGivenUpOnBridge = false
            if forceRestart {
                self.consecutiveBridgeFailures = 0
            }
            self.startBridgeIfPossible(forceRestart: forceRestart)
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

    private func startBridgeIfPossible(forceRestart: Bool = false) {
        guard desiredBridgeRunning else { return }
        if forceRestart {
            hasGivenUpOnBridge = false
            consecutiveBridgeFailures = 0
            cancelScheduledRestart()
            cancelHealthyReset()
        }
        guard !hasGivenUpOnBridge else { return }

        if forceRestart, let process = bridgeProcess, process.isRunning {
            process.terminationHandler = nil
            guard stopBridgeProcess(process) else {
                noteBootstrapError("Existing bridge did not exit; refusing to start a second instance")
                return
            }
            bridgeProcess = nil
            bridgeStartedAt = nil
            bridgeGeneration += 1
            notifyBridgeRuntime(isRunning: false, isRestarting: false, didGiveUp: false)
        }

        guard bridgeProcess == nil else { return }
        guard validateRuntimeManifest() else {
            noteBootstrapError("Bundled runtime integrity validation failed")
            return
        }
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
        let capabilityPipe = Pipe()
        process.executableURL = nodeInvocation.executableURL
        process.arguments = nodeInvocation.arguments + [bridgeScript.path]
        var environment = runtimeEnvironment()
        environment["NOTCH_MONITOR_UI_TOKEN_FD"] = "0"
        process.environment = environment
        process.standardInput = capabilityPipe
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            bridgeGeneration += 1
            let generation = bridgeGeneration
            bridgeProcess = process
            bridgeStartedAt = Date()
            process.terminationHandler = { [weak self] terminatedProcess in
                self?.runtimeQueue.async {
                    guard let self, self.bridgeProcess === terminatedProcess else { return }
                    self.handleUnexpectedBridgeExit(terminatedProcess, generation: generation)
                }
            }
            capabilityPipe.fileHandleForReading.closeFile()
            capabilityPipe.fileHandleForWriting.write(Data(RuntimeSecurity.uiCapability.utf8))
            capabilityPipe.fileHandleForWriting.closeFile()
            notifyBridgeRuntime(isRunning: true, isRestarting: false, didGiveUp: false)
            scheduleHealthyFailureReset(generation: generation)
            print("OpenIsland bootstrap: bridge started generation=\(generation)")
        } catch {
            capabilityPipe.fileHandleForReading.closeFile()
            capabilityPipe.fileHandleForWriting.closeFile()
            handleBridgeLaunchFailure(error)
        }
    }

    private func handleUnexpectedBridgeExit(_ process: Process, generation: UInt64) {
        let status = process.terminationStatus
        let uptime = bridgeStartedAt.map { Date().timeIntervalSince($0) } ?? 0
        print("OpenIsland bootstrap: bridge exited generation=\(generation) status=\(status) uptime=\(Int(uptime))s")

        guard bridgeGeneration == generation else { return }
        bridgeProcess = nil
        bridgeStartedAt = nil
        cancelHealthyReset()

        if !desiredBridgeRunning {
            notifyBridgeRuntime(isRunning: false, isRestarting: false)
            return
        }

        if uptime >= Self.healthyBridgeUptime {
            consecutiveBridgeFailures = 0
        }
        consecutiveBridgeFailures += 1

        if consecutiveBridgeFailures >= Self.maxConsecutiveBridgeFailures {
            giveUpOnBridge(reason: "Bridge crashed \(consecutiveBridgeFailures) times in a row and will not restart automatically. Last exit status: \(status). Retry setup to start it again.")
            return
        }

        let delay = restartDelay(for: consecutiveBridgeFailures)
        let message = "Bridge exited with status \(status); restarting in \(formattedDelay(delay)) (attempt \(consecutiveBridgeFailures)/\(Self.maxConsecutiveBridgeFailures))"
        print("OpenIsland bootstrap: \(message)")
        notifyBridgeRuntime(isRunning: false, isRestarting: true, error: message)
        scheduleBridgeRestart(delay: delay, generation: generation)
    }

    private func handleBridgeLaunchFailure(_ error: Error) {
        consecutiveBridgeFailures += 1
        if consecutiveBridgeFailures >= Self.maxConsecutiveBridgeFailures {
            giveUpOnBridge(reason: "Failed to start the local bridge \(consecutiveBridgeFailures) times. Last error: \(error.localizedDescription). Retry setup to try again.")
            print("OpenIsland bootstrap: failed to start bridge - \(error.localizedDescription)")
            return
        }

        let delay = restartDelay(for: consecutiveBridgeFailures)
        let message = "Failed to start the local bridge; retrying in \(formattedDelay(delay)) (attempt \(consecutiveBridgeFailures)/\(Self.maxConsecutiveBridgeFailures))"
        print("OpenIsland bootstrap: failed to start bridge - \(error.localizedDescription)")
        notifyBridgeRuntime(isRunning: false, isRestarting: true, error: message)
        scheduleBridgeRestart(delay: delay, generation: bridgeGeneration)
    }

    private func giveUpOnBridge(reason: String) {
        hasGivenUpOnBridge = true
        cancelScheduledRestart()
        print("OpenIsland bootstrap: \(reason)")
        notifyBridgeRuntime(isRunning: false, isRestarting: false, didGiveUp: true, error: reason)
    }

    private func scheduleBridgeRestart(delay: TimeInterval, generation: UInt64) {
        cancelScheduledRestart()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard self.desiredBridgeRunning, !self.hasGivenUpOnBridge else { return }
            guard self.bridgeGeneration == generation else { return }
            guard self.bridgeProcess == nil else { return }
            print("OpenIsland bootstrap: respawning bridge")
            self.startBridgeIfPossible()
        }
        restartWorkItem = workItem
        runtimeQueue.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func scheduleHealthyFailureReset(generation: UInt64) {
        cancelHealthyReset()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard self.bridgeGeneration == generation, self.bridgeProcess?.isRunning == true else { return }
            self.consecutiveBridgeFailures = 0
            DispatchQueue.main.async {
                self.lastBootstrapError = nil
                self.refreshDiagnostics()
            }
        }
        healthyResetWorkItem = workItem
        runtimeQueue.asyncAfter(deadline: .now() + Self.healthyBridgeUptime, execute: workItem)
    }

    private func cancelScheduledRestart() {
        restartWorkItem?.cancel()
        restartWorkItem = nil
    }

    private func cancelHealthyReset() {
        healthyResetWorkItem?.cancel()
        healthyResetWorkItem = nil
    }

    private func restartDelay(for failureCount: Int) -> TimeInterval {
        let exponent = max(0, failureCount - 1)
        return min(Self.restartBackoffMax, Self.restartBackoffBase * pow(2.0, Double(exponent)))
    }

    private func formattedDelay(_ delay: TimeInterval) -> String {
        if delay < 1 {
            return "0.5s"
        }
        return "\(Int(delay))s"
    }

    private func notifyBridgeRuntime(isRunning: Bool, isRestarting: Bool, didGiveUp: Bool? = nil, error: String? = nil) {
        storeBridgeSnapshot(isRunning: isRunning)
        SocketService.shared.noteBridgeRuntime(generation: bridgeGeneration, isRunning: isRunning)
        DispatchQueue.main.async {
            self.isBridgeRunning = isRunning
            self.isBridgeRestarting = isRestarting
            if let didGiveUp {
                self.didGiveUpOnBridge = didGiveUp
            }
            if let error {
                self.lastBootstrapError = error
            }
            self.refreshDiagnostics()
        }
    }

    private func storeBridgeSnapshot(isRunning: Bool) {
        bridgeSnapshotLock.lock()
        snapshotGeneration = bridgeGeneration
        snapshotIsRunning = isRunning
        bridgeSnapshotLock.unlock()
    }

    private func stopBridgeProcess(_ process: Process, grace: TimeInterval = 2) -> Bool {
        guard process.isRunning else { return true }
        process.terminate()
        var deadline = Date().addingTimeInterval(grace)
        while process.isRunning && Date() < deadline {
            usleep(20_000)
        }
        guard process.isRunning else { return true }

        guard kill(process.processIdentifier, SIGKILL) == 0 || errno == ESRCH else { return false }
        deadline = Date().addingTimeInterval(1)
        while process.isRunning && Date() < deadline {
            usleep(20_000)
        }
        return !process.isRunning
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

    private func validateRuntimeManifest() -> Bool {
        guard let baseURL = resourceBaseURL() else { return false }
        let manifestURL = baseURL.appendingPathComponent("runtime-manifest.json")
        guard
            let data = try? Data(contentsOf: manifestURL),
            let manifest = try? JSONDecoder().decode(RuntimeManifest.self, from: data),
            manifest.version == 1,
            manifest.protocolVersion == 1
        else { return false }

        for (relativePath, expectedHash) in manifest.files {
            let fileURL = baseURL.appendingPathComponent(relativePath)
            guard let fileData = try? Data(contentsOf: fileURL) else { return false }
            let actualHash = SHA256.hash(data: fileData).map { String(format: "%02x", $0) }.joined()
            guard actualHash == expectedHash else { return false }
        }
        return true
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
        let codexHooksInstalled = codexHookInstalled()
        let codexWrapperInstalled = codexWrapperExists()
        let pathConfigured = shellConfigMentionsLocalBin() || currentEnvironmentContainsLocalBin()
        let socketReachable = SocketService.shared.isConnected
        let bridgeRunning = isBridgeRunning
        let tools = relevantTools(
            claudeHookInstalled: claudeInstalled,
            codexHookInstalled: codexHooksInstalled,
            codexWrapperInstalled: codexWrapperInstalled
        )

        var checks: [BootstrapCheck] = [
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
                    : "Recommended for hover-to-expand and jumping back to a terminal or IDE. The rest of Open Island still works without it.",
                state: accessibilityGranted ? .ready : .warning,
                action: accessibilityGranted ? .recheck : .openAccessibility,
                actionTitle: accessibilityGranted ? "Recheck" : "Open Settings"
            )
        ]

        if tools.contains("claude") {
            checks.append(
                BootstrapCheck(
                    id: "claude-hooks",
                    title: claudeInstalled ? "Claude hook is installed" : "Install Claude hook",
                    detail: claudeInstalled
                        ? "New Claude Code sessions will register automatically."
                        : "Open Island could not confirm the Claude hook in ~/.claude/settings.json.",
                    state: claudeInstalled ? .ready : .warning,
                    action: .recheck,
                    actionTitle: "Recheck"
                )
            )
        }

        if tools.contains("codex") {
            checks.append(contentsOf: [
                BootstrapCheck(
                    id: "codex-wrapper",
                    title: codexWrapperInstalled ? "Codex wrapper is installed" : "Install Codex wrapper",
                    detail: codexWrapperInstalled
                        ? "New Codex sessions can register silently through ~/.local/bin/codex."
                        : "Open Island could not confirm the managed Codex wrapper in ~/.local/bin/codex.",
                    state: codexWrapperInstalled ? .ready : .warning,
                    action: .recheck,
                    actionTitle: "Recheck"
                ),
                BootstrapCheck(
                    id: "codex-hooks",
                    title: codexHooksInstalled ? "Codex hooks are installed" : "Install Codex hooks",
                    detail: codexHooksInstalled
                        ? "Codex permission and lifecycle events should reach Open Island automatically."
                        : "Open Island could not confirm the managed Codex hooks in ~/.codex/hooks.json.",
                    state: codexHooksInstalled ? .ready : .warning,
                    action: .recheck,
                    actionTitle: "Recheck"
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
                )
            ])
        }

        checks.append(
            BootstrapCheck(
                id: "bridge",
                title: bridgeCheckTitle(socketReachable: socketReachable, bridgeRunning: bridgeRunning),
                detail: bridgeCheckDetail(socketReachable: socketReachable, bridgeRunning: bridgeRunning),
                state: bridgeCheckState(socketReachable: socketReachable, bridgeRunning: bridgeRunning),
                action: .retrySetup,
                actionTitle: socketReachable ? "Restart" : "Retry Setup"
            )
        )
        return checks
    }

    private func relevantTools(claudeHookInstalled: Bool, codexHookInstalled: Bool, codexWrapperInstalled: Bool) -> Set<String> {
        let selected = parseToolList(ProcessInfo.processInfo.environment["OPEN_ISLAND_TOOLS"])
        if !selected.isEmpty {
            return selected
        }

        let manifest = hookManifestTools()
        if !manifest.isEmpty {
            return manifest
        }

        var installed = installedToolHints()
        if claudeHookInstalled { installed.insert("claude") }
        if codexHookInstalled || codexWrapperInstalled { installed.insert("codex") }
        return installed
    }

    private func parseToolList(_ raw: String?) -> Set<String> {
        guard let raw else { return [] }
        var tools = Set<String>()
        for part in raw.split(separator: ",") {
            let tool = part.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if tool.isEmpty { continue }
            if tool == "codex-wrapper" {
                tools.insert("codex")
            } else {
                tools.insert(tool)
            }
        }
        return tools
    }

    private func hookManifestTools() -> Set<String> {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let stateHome = ProcessInfo.processInfo.environment["XDG_STATE_HOME"]
            ?? home.appendingPathComponent(".local/state").path
        let manifestURL = URL(fileURLWithPath: stateHome)
            .appendingPathComponent("open-island")
            .appendingPathComponent("hook-manifest.json")
        guard
            let data = try? Data(contentsOf: manifestURL),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let tools = json["tools"] as? [String]
        else {
            return []
        }
        return parseToolList(tools.joined(separator: ","))
    }

    private func installedToolHints() -> Set<String> {
        var tools = Set<String>()
        let home = FileManager.default.homeDirectoryForCurrentUser
        let fm = FileManager.default
        if fm.fileExists(atPath: home.appendingPathComponent(".claude").path) || binaryExists("claude") {
            tools.insert("claude")
        }
        if fm.fileExists(atPath: home.appendingPathComponent(".codex").path) || binaryExists("codex") {
            tools.insert("codex")
        }
        if fm.fileExists(atPath: home.appendingPathComponent(".cursor").path) || fm.fileExists(atPath: "/Applications/Cursor.app") {
            tools.insert("cursor")
        }
        if fm.fileExists(atPath: home.appendingPathComponent(".gemini").path) || binaryExists("gemini") {
            tools.insert("gemini")
        }
        if fm.fileExists(atPath: home.appendingPathComponent(".qoder").path) || binaryExists("qoder") || binaryExists("qodercli") {
            tools.insert("qoder")
        }
        return tools
    }

    private func binaryExists(_ name: String) -> Bool {
        let fm = FileManager.default
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            "/usr/bin/\(name)",
            home.appendingPathComponent(".local/bin/\(name)").path
        ]
        return candidates.contains { fm.isExecutableFile(atPath: $0) }
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

    private func codexHookInstalled() -> Bool {
        let hooksURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex")
            .appendingPathComponent("hooks.json")

        guard
            let data = try? Data(contentsOf: hooksURL),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let hooks = json["hooks"] as? [String: Any]
        else {
            return false
        }

        return hooks.values.contains { value in
            guard let entries = value as? [[String: Any]] else { return false }
            return entries.contains { entry in
                if let hooks = entry["hooks"] as? [[String: Any]] {
                    return hooks.contains { ($0["command"] as? String)?.contains("hook.js event codex") == true }
                }
                return false
            }
        }
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

    private func bridgeCheckTitle(socketReachable: Bool, bridgeRunning: Bool) -> String {
        if socketReachable {
            return "Local bridge connected"
        }
        if didGiveUpOnBridge {
            return "Local bridge stopped after repeated crashes"
        }
        if isBridgeRestarting {
            return "Restarting local bridge"
        }
        if bridgeRunning {
            return "Waiting for bridge connection"
        }
        return "Start the local bridge"
    }

    private func bridgeCheckDetail(socketReachable: Bool, bridgeRunning: Bool) -> String {
        if socketReachable {
            return "The app is connected to its private local bridge socket."
        }
        if didGiveUpOnBridge {
            return bridgeFailureDetail()
        }
        if isBridgeRestarting {
            if let lastBootstrapError, !lastBootstrapError.isEmpty {
                return lastBootstrapError
            }
            return "The local bridge exited and Open Island is restarting it."
        }
        if bridgeRunning {
            return "The bridge process is running, but the app has not connected yet."
        }
        return bridgeFailureDetail()
    }

    private func bridgeCheckState(socketReachable: Bool, bridgeRunning: Bool) -> BootstrapCheckState {
        if socketReachable {
            return .ready
        }
        if didGiveUpOnBridge {
            return .blocking
        }
        if isBridgeRestarting || bridgeRunning {
            return .running
        }
        return .warning
    }

    private func bridgeFailureDetail() -> String {
        if let lastBootstrapError, !lastBootstrapError.isEmpty {
            return "Open Island could not reach the bundled bridge. Last error: \(lastBootstrapError)"
        }
        return "Open Island could not reach the bundled bridge. Retry setup if this persists."
    }
}

private struct NodeInvocation {
    let executableURL: URL
    let arguments: [String]
}

private struct RuntimeManifest: Decodable {
    let version: Int
    let protocolVersion: Int
    let files: [String: String]
}
