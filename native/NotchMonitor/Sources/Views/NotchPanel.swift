import SwiftUI

struct NotchPanelView: View {
    @EnvironmentObject var socketService: SocketService
    @ObservedObject private var bootstrapService = AppBootstrapService.shared

    var body: some View {
        VStack(spacing: 0) {
            if socketService.agents.isEmpty {
                EmptyStateView()
                    .padding(.horizontal, 14)
                    .padding(.vertical, 13)
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
                    .padding(.vertical, 8)
                }
                .frame(maxHeight: CGFloat(maxVisibleRows * 54 + 16))
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

    private var panelHeight: CGFloat {
        if socketService.agents.isEmpty {
            let issueCount = bootstrapService.checks.filter { $0.state != .ready }.count
            if issueCount == 0 {
                return 132
            }
            return min(286, CGFloat(112 + (min(issueCount, 4) * 42)))
        }
        let rowCount = min(max(socketService.agents.count, 1), maxVisibleRows)
        return CGFloat(24 + (rowCount * 54))
    }

    private var maxVisibleRows: Int { 6 }
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
                    onAllow: { respondToPermission(agent.id, allowed: true) },
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
                Button("Deny") {
                    respondToPermission(agent.id, allowed: false)
                }
            }
        }
    }

    private var primaryTitle: String {
        if agent.needsPermission, let request = agent.permissionRequest {
            return request.message
        }
        if let prompt = agent.interactivePrompt {
            return prompt.title
        }
        return agent.name.replacingOccurrences(of: "—", with: "").trimmingCharacters(in: .whitespaces)
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
        let raw = (agent.terminalApp ?? agent.terminal).lowercased()
        if raw.contains("iterm") { return "iTerm" }
        if raw.contains("terminal") { return "Terminal" }
        if raw.contains("ghostty") { return "Ghostty" }
        if raw.contains("pycharm") { return "PyCharm" }
        if raw.contains("idea") { return "IDEA" }
        return "Shell"
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

    func respondToPermission(_ agentId: String, allowed: Bool) {
        NotificationCenter.default.post(
            name: .init("PermissionResponse"),
            object: nil,
            userInfo: ["agentId": agentId, "allowed": allowed]
        )
    }

    func submitInteractiveOption(_ option: InteractiveOption, for agent: Agent) {
        SocketService.shared.clearInteractivePrompt(agentId: agent.id)
        TerminalPromptService.submit(option: option, to: agent)
    }
}

struct InlineApprovalBar: View {
    let request: PermissionRequest
    let onAllow: () -> Void
    let onDeny: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text(request.type)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(Color(hex: "#f5c36b"))
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color(hex: "#3c2c14")))

            Spacer()

            InlineActionButton(title: "Deny", tint: Color(hex: "#7c2d2b"), foreground: Color(hex: "#ffe7e4"), action: onDeny)
            InlineActionButton(title: "Allow", tint: Color(hex: "#9ddab4"), foreground: Color(hex: "#08281d"), action: onAllow)
        }
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
