import SwiftUI

struct OnboardingSetupView: View {
    @ObservedObject private var bootstrapService = AppBootstrapService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    Text("Open Island Setup")
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                        .foregroundColor(Color(hex: "#f8f4ec"))

                    Spacer()

                    Button("Later") {
                        AppBootstrapService.shared.dismissOnboarding()
                    }
                    .buttonStyle(SetupSecondaryButtonStyle())
                }

                Text(subtitle)
                    .font(.system(size: 13.5, weight: .medium, design: .rounded))
                    .foregroundColor(Color.white.opacity(0.58))
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    statusPill(title: blockingCount > 0 ? "\(blockingCount) required" : "No blockers", tint: blockingCount > 0 ? Color(hex: "#f59e0b") : Color(hex: "#22c55e"))
                    statusPill(title: bootstrapService.isBootstrapping ? "Installing" : "Monitoring", tint: bootstrapService.isBootstrapping ? Color(hex: "#60a5fa") : Color(hex: "#94a3b8"))
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 18)

            ScrollView(.vertical, showsIndicators: visibleChecks.count > 4) {
                VStack(spacing: 10) {
                    ForEach(visibleChecks) { check in
                        SetupDiagnosticCard(check: check)
                    }
                }
                .padding(.horizontal, 18)
            }

            Spacer(minLength: 18)

            HStack(spacing: 12) {
                Button("Run Setup Again") {
                    AppBootstrapService.shared.retrySetup()
                }
                .buttonStyle(SetupPrimaryButtonStyle())

                Button("Refresh Checks") {
                    AppBootstrapService.shared.refreshDiagnostics()
                }
                .buttonStyle(SetupSecondaryButtonStyle())

                Spacer()

                Text(footerText)
                    .font(.system(size: 11.5, weight: .medium, design: .rounded))
                    .foregroundColor(Color.white.opacity(0.38))
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 18)
        }
        .frame(width: 560, height: 460, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.97),
                            Color(hex: "#0b0b0c").opacity(0.98)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.07), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.36), radius: 28, x: 0, y: 18)
    }

    private var visibleChecks: [BootstrapCheck] {
        let issues = bootstrapService.checks
            .filter { $0.state != .ready }
            .sorted { $0.state.priority < $1.state.priority }
        return issues.isEmpty ? bootstrapService.checks : issues
    }

    private var blockingCount: Int {
        bootstrapService.checks.filter { $0.state == .blocking }.count
    }

    private var subtitle: String {
        if blockingCount > 0 {
            return "Finish the required steps below so new Claude Code and Codex sessions can register, approve actions, and jump back reliably."
        }
        return "Open Island is installed. These checks show whether hooks, wrapper, permissions, and the local bridge are all in a healthy state."
    }

    private var footerText: String {
        if bootstrapService.isBootstrapping {
            return "Applying local setup"
        }
        return blockingCount > 0 ? "Setup still needs attention" : "Setup looks healthy"
    }

    private func statusPill(title: String, tint: Color) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundColor(tint.opacity(0.95))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(tint.opacity(0.12))
            )
    }
}

struct SetupDiagnosticCard: View {
    let check: BootstrapCheck

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(color.opacity(0.22))
                .frame(width: 18, height: 18)
                .overlay(
                    Circle()
                        .fill(color)
                        .frame(width: 8, height: 8)
                )
                .padding(.top, 3)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(check.title)
                        .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                        .foregroundColor(Color(hex: "#f8f4ec"))

                    Text(check.state.label.uppercased())
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundColor(color.opacity(0.95))
                }

                Text(check.detail)
                    .font(.system(size: 11.5, weight: .medium, design: .rounded))
                    .foregroundColor(Color.white.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            if let action = check.action, let actionTitle = check.actionTitle {
                Button(actionTitle) {
                    perform(action)
                }
                .buttonStyle(SetupSecondaryButtonStyle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
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

struct SetupPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .semibold, design: .rounded))
            .foregroundColor(Color.black.opacity(0.88))
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                Capsule()
                    .fill(Color(hex: "#f3efe4").opacity(configuration.isPressed ? 0.78 : 1))
            )
    }
}

struct SetupSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundColor(Color(hex: "#f3efe4"))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(Color.white.opacity(configuration.isPressed ? 0.05 : 0.08))
            )
    }
}
