import Foundation

enum AgentStatus: String, Codable, CaseIterable {
    case running = "running"
    case waiting = "waiting"
    case error = "error"
    case completed = "completed"
    
    var colorHex: String {
        switch self {
        case .running: return "#10b981"
        case .waiting: return "#f59e0b"
        case .error: return "#ef4444"
        case .completed: return "#6366f1"
        }
    }
}

struct Agent: Identifiable, Codable {
    let id: String
    var name: String
    var type: AgentType
    var status: AgentStatus
    var terminal: String
    var terminalApp: String?
    var tty: String?
    var cwd: String?
    var pid: Int?
    var terminalTitleToken: String?
    var parentPid: Int?
    var parentCommand: String?
    var processChain: [String]?
    var environmentHints: [String: String]?
    var jetbrainsContext: [String: String]?
    var currentTask: String?
    var lastUpdate: Date
    var needsPermission: Bool
    var permissionRequest: PermissionRequest?
    var interactivePrompt: InteractivePrompt?
    
    init(id: String = UUID().uuidString,
         name: String, 
         type: AgentType, 
         status: AgentStatus = .running,
         terminal: String,
         terminalApp: String? = nil,
         tty: String? = nil,
         cwd: String? = nil,
         pid: Int? = nil,
         terminalTitleToken: String? = nil,
         parentPid: Int? = nil,
         parentCommand: String? = nil,
         processChain: [String]? = nil,
         environmentHints: [String: String]? = nil,
         jetbrainsContext: [String: String]? = nil,
         currentTask: String? = nil,
         lastUpdate: Date = Date(),
         needsPermission: Bool = false,
         permissionRequest: PermissionRequest? = nil,
         interactivePrompt: InteractivePrompt? = nil) {
        self.id = id
        self.name = name
        self.type = type
        self.status = status
        self.terminal = terminal
        self.terminalApp = terminalApp
        self.tty = tty
        self.cwd = cwd
        self.pid = pid
        self.terminalTitleToken = terminalTitleToken
        self.parentPid = parentPid
        self.parentCommand = parentCommand
        self.processChain = processChain
        self.environmentHints = environmentHints
        self.jetbrainsContext = jetbrainsContext
        self.currentTask = currentTask
        self.lastUpdate = lastUpdate
        self.needsPermission = needsPermission
        self.permissionRequest = permissionRequest
        self.interactivePrompt = interactivePrompt
    }
}

enum AgentType: String, Codable, CaseIterable {
    case claude
    case codex
    case cursor
    case gemini
    case openCode

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        switch rawValue.lowercased() {
        case "claude":
            self = .claude
        case "codex":
            self = .codex
        case "cursor":
            self = .cursor
        case "gemini":
            self = .gemini
        case "opencode", "open_code":
            self = .openCode
        default:
            self = .claude
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
    
    var icon: String {
        switch self {
        case .claude: return "sparkles"
        case .codex: return "brain"
        case .cursor: return "cursorarrow"
        case .gemini: return "star.fill"
        case .openCode: return "code"
        }
    }
    
    var color: String {
        switch self {
        case .claude: return "#d97757"
        case .codex: return "#10b981"
        case .cursor: return "#6366f1"
        case .gemini: return "#8b5cf6"
        case .openCode: return "#3b82f6"
        }
    }
}

struct PermissionRequest: Codable {
    let id: String
    let type: String
    let message: String
    let filePath: String?
    let command: String?
    let permissionKey: String?
    let timestamp: Date
}

struct InteractivePrompt: Codable {
    let id: String
    let title: String
    let message: String?
    let options: [InteractiveOption]
    let timestamp: Date
}

struct InteractiveOption: Codable, Identifiable {
    let id: String
    let value: String
    let title: String
    let detail: String?
}
