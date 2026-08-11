import SwiftUI

struct NotchPanelView: View {
    @EnvironmentObject var socketService: SocketService
    @ObservedObject private var bootstrapService = AppBootstrapService.shared
    @State private var selectedTab: PanelTab = .agents

    var body: some View {
        VStack(spacing: 10) {
            PanelTabBar(selectedTab: $selectedTab)
                .padding(.horizontal, 14)
                .padding(.top, 12)

            if selectedTab == .agents {
                agentsContent
            } else {
                UsagePanelView()
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
            }
        }
        .frame(width: 520, height: panelHeight, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.black.opacity(0.97))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.42), radius: 24, x: 0, y: 16)
    }

    @ViewBuilder
    private var agentsContent: some View {
        if socketService.agents.isEmpty {
            EmptyStateView()
                .padding(.horizontal, 14)
                .padding(.bottom, 13)
        } else {
            ScrollView(.vertical, showsIndicators: socketService.agents.count > maxVisibleRows) {
                VStack(spacing: 0) {
                    ForEach(Array(socketService.agents.enumerated()), id: \.element.id) { index, agent in
                        CompactAgentRow(agent: agent)

                        if index < socketService.agents.count - 1 {
                            Divider()
                                .overlay(Color.white.opacity(0.05))
                                .padding(.leading, 62)
                                .padding(.trailing, 18)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(maxHeight: scrollMaxHeight)
        }
    }

    private var panelHeight: CGFloat {
        if selectedTab == .usage {
            return 286
        }
        if socketService.agents.isEmpty {
            let issueCount = bootstrapService.checks.filter { $0.state != .ready }.count
            if issueCount == 0 {
                return 286
            }
            return min(286, CGFloat(112 + (min(issueCount, 4) * 42)))
        }
        return max(286, scrollMaxHeight + 48)
    }

    private var maxVisibleRows: Int { 6 }

    private var scrollMaxHeight: CGFloat {
        let visibleAgents = Array(socketService.agents.prefix(maxVisibleRows))
        let rowsHeight = visibleAgents.reduce(CGFloat(0)) { total, agent in
            total + rowHeight(for: agent)
        }
        return 16 + rowsHeight
    }

    private func rowHeight(for agent: Agent) -> CGFloat {
        if agent.needsPermission || agent.interactivePrompt != nil {
            return 98
        }
        return 54
    }
}

private enum PanelTab: String, CaseIterable {
    case agents = "Agents"
    case usage = "Usage"
}

private struct PanelTabBar: View {
    @Binding var selectedTab: PanelTab
    @ObservedObject private var usageStore = UsageStore.shared

    var body: some View {
        HStack(spacing: 8) {
            ForEach(PanelTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.22)) {
                        selectedTab = tab
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(tab.rawValue)
                        if tab == .usage && usageStore.loading {
                            ProgressView()
                                .scaleEffect(0.42)
                                .frame(width: 10, height: 10)
                        }
                    }
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(selectedTab == tab ? Color.white.opacity(0.92) : Color.white.opacity(0.42))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(selectedTab == tab ? Color.white.opacity(0.10) : Color.white.opacity(0.035))
                            .overlay(
                                Capsule()
                                    .stroke(Color.white.opacity(selectedTab == tab ? 0.10 : 0.04), lineWidth: 0.5)
                            )
                    )
                }
                .buttonStyle(.plain)
            }

            Spacer()

            if let lastUpdated = usageStore.lastUpdated {
                Text("Updated \(relativeTime(lastUpdated))")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(Color.white.opacity(0.34))
            }

            Button {
                usageStore.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundColor(Color.white.opacity(0.62))
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Color.white.opacity(0.06)))
            }
            .buttonStyle(.plain)
            .disabled(usageStore.loading)
            .help("Refresh usage")
        }
    }

    private func relativeTime(_ date: Date) -> String {
        let seconds = max(0, Int(Date().timeIntervalSince(date)))
        if seconds < 60 {
            return "now"
        }
        if seconds < 3600 {
            return "\(seconds / 60)m ago"
        }
        return "\(seconds / 3600)h ago"
    }
}

private struct UsagePanelView: View {
    @ObservedObject private var store = UsageStore.shared

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                UsageProviderColumn(
                    name: "Claude",
                    plan: store.claude.plan,
                    tint: OpenIslandUsageColor.claude,
                    usage: store.claude,
                    supportsReauth: true
                )

                UsageHairline()

                UsageProviderColumn(
                    name: "Codex",
                    plan: store.codex.plan,
                    tint: OpenIslandUsageColor.codex,
                    usage: store.codex,
                    supportsReauth: false
                )
            }
            .frame(maxHeight: .infinity, alignment: .top)

            UsageFooter(loading: store.loading, lastUpdated: store.lastUpdated)
                .padding(.top, 7)
        }
        .padding(.horizontal, 8)
        .padding(.top, 2)
        .padding(.bottom, 2)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.055),
                            Color.white.opacity(0.022),
                            Color.white.opacity(0.040)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.055), lineWidth: 1)
        )
    }
}

private enum OpenIslandUsageColor {
    static let claude = Color(red: 204 / 255, green: 120 / 255, blue: 92 / 255)
    static let codex = Color(red: 90 / 255, green: 168 / 255, blue: 240 / 255)
    static let amber = Color(red: 245 / 255, green: 165 / 255, blue: 36 / 255)
}

private struct UsageProviderColumn: View {
    let name: String
    let plan: String?
    let tint: Color
    let usage: AppUsage
    let supportsReauth: Bool
    @ObservedObject private var store = UsageStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            providerHeader

            HStack(spacing: 12) {
                UsageRingTile(title: "5h", window: usage.fiveHour, tint: tint)
                UsageRingTile(title: "week", window: usage.weekly, tint: tint)
            }

            if shouldShowReauth {
                Button {
                    store.reauthenticateClaude()
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: store.claudeReauthInProgress ? "clock" : "arrow.triangle.2.circlepath")
                            .font(.system(size: 9.5, weight: .bold))
                        Text(store.claudeReauthInProgress ? "waiting for browser" : "Re-authenticate")
                            .font(.system(size: 10.5, weight: .semibold))
                    }
                    .foregroundColor(Color.white.opacity(store.claudeReauthInProgress ? 0.48 : 0.78))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.055))
                            .overlay(
                                Capsule()
                                    .stroke(OpenIslandUsageColor.amber.opacity(0.22), lineWidth: 0.5)
                            )
                    )
                }
                .buttonStyle(.plain)
                .disabled(store.claudeReauthInProgress)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.horizontal, 13)
        .padding(.vertical, 12)
    }

    private var shouldShowReauth: Bool {
        supportsReauth
            && usage.fiveHour.error == ClaudeCredentials.reauthRequiredMessage
            && usage.weekly.error == ClaudeCredentials.reauthRequiredMessage
            && ClaudeCredentials.canPromptReauth()
    }

    private var providerHeader: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.20))
                    .frame(width: 20, height: 20)
                    .shadow(color: tint.opacity(0.38), radius: 9)
                Circle()
                    .fill(tint)
                    .frame(width: 8, height: 8)
            }

            Text(name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)

            if let plan {
                Text(plan.uppercased())
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundColor(Color.white.opacity(0.64))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                            .overlay(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                            )
                    )
            }

            Spacer(minLength: 0)
        }
    }
}

private struct UsageRingTile: View {
    let title: String
    let window: WindowUsage
    let tint: Color

    private var value: Double {
        min(1, max(0, window.usedPercent))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.07), lineWidth: 4)

                Circle()
                    .trim(from: 0, to: max(0.001, value))
                    .stroke(tint, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: tint.opacity(0.45), radius: 8)
                    .animation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.28), value: value)

                VStack(spacing: 0) {
                    Text("\(window.percentInt)")
                        .font(.system(size: 18, weight: .semibold, design: .monospaced))
                        .foregroundColor(valueColor)
                    Text("%")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.45))
                }
            }
            .frame(width: 58, height: 58)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.55))
                    .textCase(.lowercase)
                Text(caption)
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundColor(captionColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var valueColor: Color {
        if window.error != nil {
            return OpenIslandUsageColor.amber
        }
        if value >= 0.9 {
            return Color(hex: "#E5484D")
        }
        if value >= 0.75 {
            return OpenIslandUsageColor.amber
        }
        return .white
    }

    private var caption: String {
        if let error = window.error, error != "no data" {
            return error
        }
        if let resetAt = window.resetAt {
            return "↻ \(resetLabel(resetAt))"
        }
        return ""
    }

    private var captionColor: Color {
        if let error = window.error, error != "no data" {
            return OpenIslandUsageColor.amber.opacity(0.88)
        }
        return Color.white.opacity(0.40)
    }

    private func resetLabel(_ date: Date) -> String {
        let seconds = max(0, Int(date.timeIntervalSince(Date())))
        if seconds < 3600 {
            return "\(max(1, seconds / 60))m"
        }
        if seconds < 86400 {
            return "\(seconds / 3600)h"
        }
        return "\(seconds / 86400)d"
    }
}

private struct UsageHairline: View {
    var body: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [.clear, .white.opacity(0.07), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: 1)
            .padding(.vertical, 13)
    }
}

private struct UsageFooter: View {
    let loading: Bool
    let lastUpdated: Date?

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(loading ? OpenIslandUsageColor.codex : Color(hex: "#3DD68C"))
                .frame(width: 6, height: 6)
                .shadow(color: (loading ? OpenIslandUsageColor.codex : Color(hex: "#3DD68C")).opacity(0.7), radius: 6)

            Text(statusText)
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundColor(Color.white.opacity(0.36))

            Spacer()

            Text("reference: codex-island")
                .font(.system(size: 9.5, weight: .medium))
                .foregroundColor(Color.white.opacity(0.18))
        }
        .padding(.horizontal, 11)
        .padding(.bottom, 8)
    }

    private var statusText: String {
        if loading {
            return "syncing usage"
        }
        guard let lastUpdated else {
            return "usage not synced"
        }
        return "synced \(relativeTime(lastUpdated))"
    }

    private func relativeTime(_ date: Date) -> String {
        let seconds = max(0, Int(Date().timeIntervalSince(date)))
        if seconds < 60 {
            return "now"
        }
        if seconds < 3600 {
            return "\(seconds / 60)m ago"
        }
        return "\(seconds / 3600)h ago"
    }
}

struct EmptyStateView: View {
    @EnvironmentObject var socketService: SocketService
    @ObservedObject private var bootstrapService = AppBootstrapService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Circle()
                    .fill(statusTint.opacity(0.22))
                    .frame(width: 18, height: 18)
                    .overlay(
                        Circle()
                            .fill(statusTint)
                            .frame(width: 8, height: 8)
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(headline)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(Color(hex: "#f3efe4"))

                    Text(subheadline)
                        .font(.system(size: 10.5, weight: .medium, design: .rounded))
                        .foregroundColor(Color.white.opacity(0.42))
                        .lineLimit(2)
                }

                Spacer()
            }

            if !visibleChecks.isEmpty {
                VStack(spacing: 8) {
                    ForEach(visibleChecks) { check in
                        DiagnosticCheckRow(check: check)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var headline: String {
        if bootstrapService.hasBlockingIssue {
            return "Finish setup before monitoring"
        }
        return socketService.isConnected ? "Open Island is waiting for agents" : "Connecting Open Island"
    }

    private var subheadline: String {
        if bootstrapService.hasBlockingIssue {
            return "Open Island found a few setup gaps. Fix the required items below so new Claude and Codex sessions can register reliably."
        }
        if bootstrapService.isBootstrapping {
            return "Installing hooks, wrapper, and local bridge support."
        }
        return socketService.isConnected
            ? "Launch Claude Code, Codex, or Gemini CLI and they will appear here."
            : "Waiting for the local bridge to reconnect."
    }

    private var statusTint: Color {
        if bootstrapService.hasBlockingIssue {
            return Color(hex: "#f59e0b")
        }
        return socketService.isConnected ? Color(hex: "#22c55e") : Color(hex: "#64748b")
    }

    private var visibleChecks: [BootstrapCheck] {
        bootstrapService.checks
            .filter { $0.state != .ready }
            .sorted { $0.state.priority < $1.state.priority }
            .prefix(4)
            .map { $0 }
    }
}

struct DiagnosticCheckRow: View {
    let check: BootstrapCheck

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(color.opacity(0.22))
                .frame(width: 16, height: 16)
                .overlay(
                    Circle()
                        .fill(color)
                        .frame(width: 7, height: 7)
                )
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(check.title)
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                        .foregroundColor(Color(hex: "#f3efe4"))

                    Text(check.state.label.uppercased())
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundColor(color.opacity(0.92))
                }

                Text(check.detail)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(Color.white.opacity(0.45))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 10)

            if let action = check.action, let actionTitle = check.actionTitle {
                Button(actionTitle) {
                    perform(action)
                }
                .buttonStyle(.plain)
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .foregroundColor(Color(hex: "#edf3ff"))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(0.08))
                )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        )
    }

    private var color: Color {
        switch check.state {
        case .ready:
            return Color(hex: "#22c55e")
        case .running:
            return Color(hex: "#60a5fa")
        case .warning:
            return Color(hex: "#f59e0b")
        case .blocking:
            return Color(hex: "#ef4444")
        }
    }

    private func perform(_ action: BootstrapAction) {
        switch action {
        case .retrySetup:
            AppBootstrapService.shared.retrySetup()
        case .recheck:
            AppBootstrapService.shared.refreshDiagnostics()
        case .openAccessibility:
            AppBootstrapService.shared.openAccessibilitySettings()
        }
    }
}

struct CompactAgentRow: View {
    let agent: Agent
    @ObservedObject private var socketService = SocketService.shared
    @State private var isHovering = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 11) {
                statusOrb

                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(primaryTitle)
                            .font(.system(size: 13.5, weight: .medium, design: .rounded))
                            .foregroundColor(Color(hex: "#f3efe4"))
                            .lineLimit(1)

                        Spacer(minLength: 0)

                        metaText
                    }

                    Text(secondaryLine)
                        .font(.system(size: 10.5, weight: .medium, design: .rounded))
                        .foregroundColor(Color.white.opacity(0.42))
                        .lineLimit(1)

                    if let accentLine {
                        Text(accentLine.text)
                            .font(.system(size: 10.5, weight: .medium, design: .rounded))
                            .foregroundColor(accentLine.color)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 9)

            if let request = agent.permissionRequest, agent.needsPermission {
                InlineApprovalBar(
                    request: request,
                    isSubmitting: socketService.submittingPermissionRequestIDs.contains(request.id),
                    onAllow: { respondToPermission(agent.id, allowed: true) },
                    onAllowSimilar: { respondToPermission(agent.id, allowed: true, scope: "session_similar") },
                    onDeny: { respondToPermission(agent.id, allowed: false) }
                )
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
            } else if let prompt = agent.interactivePrompt {
                InlinePromptBar(
                    prompt: prompt,
                    onSelect: { submitInteractiveOption($0, for: agent) }
                )
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(isHovering ? Color.white.opacity(0.025) : Color.clear)
        )
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .onTapGesture {
            if !agent.needsPermission && agent.interactivePrompt == nil {
                jumpToTerminal(agent)
            }
        }
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.14)) {
                isHovering = hovering
            }
        }
        .contextMenu {
            Button("Jump to Terminal") {
                jumpToTerminal(agent)
            }
            if agent.needsPermission {
                Button("Allow") {
                    respondToPermission(agent.id, allowed: true)
                }
                Button("Allow Similar") {
                    respondToPermission(agent.id, allowed: true, scope: "session_similar")
                }
                Button("Deny") {
                    respondToPermission(agent.id, allowed: false)
                }
            }
        }
        .disabled(agent.permissionRequest.map { socketService.submittingPermissionRequestIDs.contains($0.id) } ?? false)
    }

    private var primaryTitle: String {
        if agent.needsPermission, let request = agent.permissionRequest {
            return request.message
        }
        if let prompt = agent.interactivePrompt {
            return prompt.title
        }
        let trimmedName = agent.name.replacingOccurrences(of: "—", with: "").trimmingCharacters(in: .whitespaces)
        if (trimmedName == "claude-session" || trimmedName == "codex" || trimmedName == "cursor-session"),
           let cwd = agent.cwd?.trimmingCharacters(in: .whitespacesAndNewlines),
           !cwd.isEmpty {
            return URL(fileURLWithPath: cwd).lastPathComponent
        }
        return trimmedName
    }

    private var secondaryLine: String {
        if agent.needsPermission {
            return "Approval requested in \(terminalLabel)"
        }
        if agent.interactivePrompt != nil {
            return "Select an option without switching context"
        }
        return agent.currentTask ?? "Waiting for activity"
    }

    private var accentLine: (text: String, color: Color)? {
        if agent.needsPermission {
            return ("Approval needed — respond from the island", Color(hex: "#f5c36b"))
        }
        if agent.status == .completed {
            return ("Done — click to jump", Color(hex: "#22c55e"))
        }
        if agent.interactivePrompt != nil {
            return ("Choose directly from Open Island", Color(hex: "#60a5fa"))
        }
        return nil
    }

    private var statusOrb: some View {
        ZStack {
            Circle()
                .fill(statusColor.opacity(0.22))
                .frame(width: 18, height: 18)
                .shadow(color: statusColor.opacity(0.7), radius: 10, x: 0, y: 0)

            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
        }
        .frame(width: 20, height: 20)
        .padding(.top, 4)
    }

    private var metaText: some View {
        HStack(spacing: 10) {
            Text(agent.type.rawValue.capitalized)
            Text(terminalLabel)
            Text(durationLabel)
        }
        .font(.system(size: 10, weight: .medium, design: .rounded))
        .foregroundColor(Color.white.opacity(0.45))
    }

    private var terminalLabel: String {
        let raw = inferredTerminalLabelSource().lowercased()
        if raw.contains("iterm") { return "iTerm" }
        if raw.contains("terminal") { return "Terminal" }
        if raw.contains("ghostty") { return "Ghostty" }
        if raw.contains("warp") { return "Warp" }
        if raw.contains("cursor") { return "Cursor" }
        if raw.contains("vscode") || raw.contains("visual studio code") || raw == "code" { return "VS Code" }
        if raw.contains("jetbrains") || raw.contains("jediterm") { return "JetBrains" }
        if raw.contains("pycharm") { return "PyCharm" }
        if raw.contains("idea") { return "IDEA" }
        return "Shell"
    }

    private func inferredTerminalLabelSource() -> String {
        let candidates = [
            agent.terminalApp,
            agent.environmentHints?["TERM_PROGRAM_APP"],
            agent.environmentHints?["TERM_PROGRAM"],
            inferredTerminalAppFromProcessChain()
        ]

        for candidate in candidates {
            let trimmed = candidate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !trimmed.isEmpty {
                return trimmed
            }
        }

        return agent.terminal
    }

    private func inferredTerminalAppFromProcessChain() -> String? {
        let joined = (agent.processChain ?? []).joined(separator: " ").lowercased()
        if joined.contains("cursor") { return "Cursor" }
        if joined.contains("visual studio code") || joined.contains("vscode") || joined.contains(":code ") || joined.hasSuffix(":code") {
            return "Visual Studio Code"
        }
        if joined.contains("iterm") { return "iTerm" }
        if joined.contains("terminal") { return "Terminal" }
        return nil
    }

    private var durationLabel: String {
        let minutes = max(1, Int(Date().timeIntervalSince(agent.lastUpdate) / 60))
        if minutes >= 60 {
            return "\(minutes / 60)h"
        }
        return "\(minutes)m"
    }

    private var statusColor: Color {
        if agent.needsPermission {
            return Color(hex: "#f59e0b")
        }
        if agent.interactivePrompt != nil {
            return Color(hex: "#60a5fa")
        }
        return Color(hex: agent.status.colorHex)
    }

    func jumpToTerminal(_ agent: Agent) {
        TerminalJumpService.jump(to: agent)
    }

    func respondToPermission(_ agentId: String, allowed: Bool, scope: String = "once") {
        NotificationCenter.default.post(
            name: .init("PermissionResponse"),
            object: nil,
            userInfo: ["agentId": agentId, "allowed": allowed, "scope": scope]
        )
    }

    func submitInteractiveOption(_ option: InteractiveOption, for agent: Agent) {
        if TerminalPromptService.submit(option: option, to: agent) {
            SocketService.shared.clearInteractivePrompt(agentId: agent.id)
        }
    }
}

struct InlineApprovalBar: View {
    let request: PermissionRequest
    let isSubmitting: Bool
    let onAllow: () -> Void
    let onAllowSimilar: () -> Void
    let onDeny: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text(isSubmitting ? "Submitting…" : request.type)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(Color(hex: "#f5c36b"))
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color(hex: "#3c2c14")))

            Spacer()

            InlineActionButton(title: "Deny", tint: Color(hex: "#7c2d2b"), foreground: Color(hex: "#ffe7e4"), action: onDeny)
            InlineActionButton(title: "Allow", tint: Color(hex: "#9ddab4"), foreground: Color(hex: "#08281d"), action: onAllow)
            InlineActionButton(title: "Allow Similar", tint: Color(hex: "#f5c36b"), foreground: Color(hex: "#2a1805"), action: onAllowSimilar)
                .help("Approve matching requests in this session")
        }
        .disabled(isSubmitting)
    }
}

struct InlinePromptBar: View {
    let prompt: InteractivePrompt
    let onSelect: (InteractiveOption) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(prompt.options) { option in
                    Button(action: { onSelect(option) }) {
                        HStack(spacing: 7) {
                            Text(option.value)
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundColor(Color(hex: "#8fb4ff"))
                            Text(option.title)
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundColor(Color(hex: "#edf3ff"))
                        }
                        .padding(.horizontal, 11)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(Color(hex: "#172236"))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct InlineActionButton: View {
    let title: String
    let tint: Color
    let foreground: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(foreground)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    Capsule()
                        .fill(tint)
                )
        }
        .buttonStyle(.plain)
    }
}
