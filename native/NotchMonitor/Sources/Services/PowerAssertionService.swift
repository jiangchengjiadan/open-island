import Combine
import Foundation
import IOKit.pwr_mgt
import IOKit.ps

final class PowerAssertionService: ObservableObject {
    static let shared = PowerAssertionService()

    @Published private(set) var isKeepingAwake = false
    @Published private(set) var isPausedForPower = false
    @Published private(set) var activeAgentCount = 0

    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey)
            reevaluate(with: lastAgents)
        }
    }

    @Published var onlyOnPowerAdapter: Bool {
        didSet {
            UserDefaults.standard.set(onlyOnPowerAdapter, forKey: Self.onlyOnPowerAdapterKey)
            reevaluate(with: lastAgents)
        }
    }

    private static let enabledKey = "OpenIsland.keepAwake.enabled"
    private static let onlyOnPowerAdapterKey = "OpenIsland.keepAwake.onlyOnPowerAdapter"

    private var assertionID = IOPMAssertionID(0)
    private var lastAgents: [Agent] = []
    private var powerSourceRunLoopSource: CFRunLoopSource?

    private init() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: Self.enabledKey) == nil {
            defaults.set(false, forKey: Self.enabledKey)
        }
        if defaults.object(forKey: Self.onlyOnPowerAdapterKey) == nil {
            defaults.set(true, forKey: Self.onlyOnPowerAdapterKey)
        }
        isEnabled = defaults.bool(forKey: Self.enabledKey)
        onlyOnPowerAdapter = defaults.bool(forKey: Self.onlyOnPowerAdapterKey)
        startPowerSourceMonitoring()
    }

    deinit {
        stopPowerSourceMonitoring()
    }

    func reevaluate(with agents: [Agent]) {
        lastAgents = agents
        let activeAgents = agents.filter(Self.shouldKeepAwake(for:))
        activeAgentCount = activeAgents.count

        guard isEnabled, !activeAgents.isEmpty else {
            isPausedForPower = false
            releaseAssertion()
            return
        }

        guard !onlyOnPowerAdapter || Self.isOnExternalPower() else {
            isPausedForPower = true
            releaseAssertion()
            return
        }

        isPausedForPower = false
        createAssertion(reason: Self.reason(for: activeAgents))
    }

    func disableForShutdown() {
        releaseAssertion()
    }

    /// Reevaluates keep-awake state immediately after macOS reports a power source change.
    private func handlePowerSourceChanged() {
        reevaluate(with: lastAgents)
    }

    /// Subscribes to IOKit power source notifications so adapter changes do not wait for the next agent update.
    private func startPowerSourceMonitoring() {
        guard powerSourceRunLoopSource == nil else { return }

        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let service = Unmanaged<PowerAssertionService>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.async {
                service.handlePowerSourceChanged()
            }
        }, context)?.takeRetainedValue() else {
            return
        }

        powerSourceRunLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, CFRunLoopMode.defaultMode)
    }

    private func stopPowerSourceMonitoring() {
        guard let source = powerSourceRunLoopSource else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), source, CFRunLoopMode.defaultMode)
        powerSourceRunLoopSource = nil
    }

    private func createAssertion(reason: String) {
        if isKeepingAwake {
            return
        }

        var newAssertionID = IOPMAssertionID(0)
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypeNoIdleSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &newAssertionID
        )

        if result == kIOReturnSuccess {
            assertionID = newAssertionID
            isKeepingAwake = true
            print("Keep Awake enabled: \(reason)")
        } else {
            assertionID = 0
            isKeepingAwake = false
            print("Keep Awake failed with IOKit result: \(result)")
        }
    }

    private func releaseAssertion() {
        guard isKeepingAwake else { return }
        IOPMAssertionRelease(assertionID)
        assertionID = 0
        isKeepingAwake = false
        print("Keep Awake released")
    }

    private static func shouldKeepAwake(for agent: Agent) -> Bool {
        guard agent.status == .running else {
            return false
        }

        switch agent.type {
        case .claude, .codex, .gemini, .qoder:
            return true
        case .cursor, .openCode:
            return false
        }
    }

    private static func reason(for agents: [Agent]) -> String {
        let names = agents
            .map { $0.type.rawValue.capitalized }
            .uniqued()
            .prefix(3)
            .joined(separator: ", ")
        return names.isEmpty
            ? "Open Island: active AI agent session"
            : "Open Island: active \(names) session"
    }

    private static func isOnExternalPower() -> Bool {
        guard let details = IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() as? [String: Any] else {
            return false
        }
        return !details.isEmpty
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
