import Foundation

enum BootstrapCheckState {
    case ready
    case running
    case warning
    case blocking

    var priority: Int {
        switch self {
        case .blocking: return 0
        case .warning: return 1
        case .running: return 2
        case .ready: return 3
        }
    }

    var label: String {
        switch self {
        case .ready: return "Ready"
        case .running: return "Checking"
        case .warning: return "Attention"
        case .blocking: return "Required"
        }
    }
}

enum BootstrapAction: String {
    case retrySetup
    case recheck
    case openAccessibility
}

struct BootstrapCheck: Identifiable {
    let id: String
    let title: String
    let detail: String
    let state: BootstrapCheckState
    let action: BootstrapAction?
    let actionTitle: String?
}
