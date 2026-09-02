import Combine
import Foundation
import Network

@MainActor
final class UsageStore: ObservableObject {
    static let shared = UsageStore()

    @Published var claude: AppUsage = .empty
    @Published var codex: AppUsage = .empty
    @Published var lastUpdated: Date?
    @Published var loading = false
    @Published var claudeReauthInProgress = false

    private var refreshTask: Task<Void, Never>?
    private var reauthPollTask: Task<Void, Never>?
    private var pollTimer: Timer?
    private var netMonitor: NWPathMonitor?
    private let netQueue = DispatchQueue(label: "OpenIsland.UsageStore.network")
    private var lastNetStatus: NWPath.Status?
    private var pendingRefresh = false

    private init() {}

    func startAutoRefresh() {
        if pollTimer == nil {
            pollTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.refresh()
                }
            }
            startNetworkMonitor()
        }

        let stale = lastUpdated.map { Date().timeIntervalSince($0) >= 300 } ?? true
        if stale {
            refresh()
        }
    }

    func stopAutoRefresh() {
        pollTimer?.invalidate()
        pollTimer = nil
        refreshTask?.cancel()
        refreshTask = nil
        reauthPollTask?.cancel()
        reauthPollTask = nil
        netMonitor?.cancel()
        netMonitor = nil
        lastNetStatus = nil
        pendingRefresh = false
        loading = false
        claudeReauthInProgress = false
    }

    func refresh() {
        guard !loading else {
            pendingRefresh = true
            return
        }

        loading = true
        pendingRefresh = false
        refreshTask?.cancel()
        refreshTask = Task {
            async let claudeResult = UsageFetcher.fetchClaude()
            async let codexResult = UsageFetcher.fetchCodex()
            let (newClaude, newCodex) = await (claudeResult, codexResult)

            guard !Task.isCancelled else {
                self.loading = false
                self.consumePendingRefreshIfNeeded()
                return
            }

            if !Self.isErrorOnly(newClaude) || Self.isErrorOnly(claude) {
                claude = newClaude
            }
            if !Self.isErrorOnly(newCodex) || Self.isErrorOnly(codex) {
                codex = newCodex
            }
            lastUpdated = Date()
            loading = false
            consumePendingRefreshIfNeeded()
        }
    }

    func reauthenticateClaude() {
        guard !claudeReauthInProgress else { return }
        guard ClaudeCredentials.spawnReauth() else { return }

        claudeReauthInProgress = true
        reauthPollTask?.cancel()
        reauthPollTask = Task { [weak self] in
            for _ in 0..<24 {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                if Task.isCancelled { return }

                let usage = await UsageFetcher.fetchClaude()
                if Task.isCancelled { return }

                if usage.fiveHour.error == nil || usage.weekly.error == nil {
                    await MainActor.run {
                        self?.claude = usage
                        self?.lastUpdated = Date()
                        self?.claudeReauthInProgress = false
                    }
                    return
                }
            }

            await MainActor.run {
                self?.claudeReauthInProgress = false
            }
        }
    }

    private static func isErrorOnly(_ usage: AppUsage) -> Bool {
        usage.fiveHour.error != nil
            && usage.weekly.error != nil
            && usage.fiveHour.usedPercent == 0
            && usage.weekly.usedPercent == 0
    }

    private func startNetworkMonitor() {
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let previous = self.lastNetStatus
                self.lastNetStatus = path.status
                guard path.status == .satisfied,
                      let previous,
                      previous != .satisfied else {
                    return
                }

                self.refreshTask?.cancel()
                await self.refreshTask?.value
                self.refresh()
            }
        }
        monitor.start(queue: netQueue)
        netMonitor = monitor
    }

    /// Runs exactly one queued refresh after the current request finishes, so overlapping triggers coalesce.
    private func consumePendingRefreshIfNeeded() {
        guard pendingRefresh else { return }
        pendingRefresh = false
        refresh()
    }
}
