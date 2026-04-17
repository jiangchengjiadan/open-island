import Foundation
import Combine
import SwiftUI
import Darwin

class SocketService: ObservableObject {
    static let shared = SocketService()

    @Published var agents: [Agent] = []
    @Published var isConnected = false

    private let socketPath = "/tmp/notch-monitor.sock"
    private let socketQueue = DispatchQueue(label: "notchmonitor.socket")
    private let processQueue = DispatchQueue(label: "notchmonitor.process-scan", qos: .utility)
    private let homeDirectory = FileManager.default.homeDirectoryForCurrentUser

    private var socketFD: Int32 = -1
    private var readSource: DispatchSourceRead?
    private var reconnectWorkItem: DispatchWorkItem?
    private var incomingBuffer = Data()
    private var didRegisterObservers = false
    private var processPollTimer: Timer?
    private var socketAgents: [String: Agent] = [:]
    private var processAgents: [String: Agent] = [:]
    private var codexAgents: [String: Agent] = [:]
    private var promptCache: [String: PromptCacheEntry] = [:]
    private var pendingPermissionRequests: [String: PermissionRequest] = [:]
    private var isRefreshingProcesses = false

    private init() {}

    func startListening() {
        registerObserversIfNeeded()
        print("SocketService: startListening")
        refreshCodexAgents(activeProcesses: [])
        startProcessPolling()
        connectToSocket()
    }

    private func registerObserversIfNeeded() {
        guard !didRegisterObservers else { return }
        didRegisterObservers = true

        NotificationCenter.default.addObserver(
            forName: .init("PermissionResponse"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard
                let self,
                let agentId = notification.userInfo?["agentId"] as? String,
                let allowed = notification.userInfo?["allowed"] as? Bool
            else {
                return
            }

            self.sendPermissionResponse(agentId: agentId, allowed: allowed)
        }
    }

    private func connectToSocket() {
        socketQueue.async {
            guard self.socketFD == -1 else { return }

            let fd = socket(AF_UNIX, SOCK_STREAM, 0)
            guard fd >= 0 else {
                print("Socket create failed")
                self.scheduleReconnect()
                return
            }

            var address = sockaddr_un()
            #if os(macOS)
            address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
            #endif
            address.sun_family = sa_family_t(AF_UNIX)

            let maxPathLength = MemoryLayout.size(ofValue: address.sun_path)
            _ = withUnsafeMutablePointer(to: &address.sun_path.0) { pointer in
                self.socketPath.withCString { pathPointer in
                    strncpy(pointer, pathPointer, maxPathLength - 1)
                }
            }

            let result = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }

            guard result == 0 else {
                let errorDescription = String(cString: strerror(errno))
                print("Socket connect failed: \(errorDescription)")
                close(fd)
                self.scheduleReconnect()
                return
            }

            self.socketFD = fd
            self.incomingBuffer.removeAll(keepingCapacity: true)
            self.setupReadSource(for: fd)

            DispatchQueue.main.async {
                self.isConnected = true
                print("Socket connected")
            }
        }
    }

    private func setupReadSource(for fd: Int32) {
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: socketQueue)

        source.setEventHandler { [weak self] in
            self?.readAvailableData()
        }

        source.setCancelHandler {
            close(fd)
        }

        readSource = source
        source.resume()
    }

    private func readAvailableData() {
        guard socketFD >= 0 else { return }

        var buffer = [UInt8](repeating: 0, count: 4096)
        let bytesRead = read(socketFD, &buffer, buffer.count)

        if bytesRead > 0 {
            incomingBuffer.append(contentsOf: buffer.prefix(bytesRead))
            processIncomingBuffer()
            return
        }

        handleDisconnect()
    }

    private func processIncomingBuffer() {
        while let newlineIndex = incomingBuffer.firstIndex(of: 0x0A) {
            let line = incomingBuffer.prefix(upTo: newlineIndex)
            incomingBuffer.removeSubrange(...newlineIndex)

            guard !line.isEmpty else { continue }

            do {
                let message = try JSONDecoder().decode(ServerMessage.self, from: line)
                DispatchQueue.main.async {
                    print("Socket message received: \(message.type)")
                    self.handleMessage(message)
                }
            } catch {
                print("Socket decode error: \(error)")
            }
        }
    }

    private func handleMessage(_ message: ServerMessage) {
        switch message.type {
        case "agent_snapshot":
            socketAgents = Dictionary(
                uniqueKeysWithValues: (message.data?.compactMap { payload in
                    payload.asAgent().map { ($0.id, $0) }
                } ?? [])
            )
            applyPendingPermissionsToSocketAgents()
            publishAgents()
        case "agent_registered", "agent_updated":
            guard let agent = message.data?.first?.asAgent() else { return }
            var mergedAgent = agent
            if let pendingRequest = pendingPermissionRequests[agent.id] {
                mergedAgent.needsPermission = true
                mergedAgent.permissionRequest = pendingRequest
            }
            socketAgents[mergedAgent.id] = mergedAgent
            publishAgents()
        case "agent_unregistered":
            guard let id = message.data?.first?.id else { return }
            socketAgents.removeValue(forKey: id)
            pendingPermissionRequests.removeValue(forKey: id)
            publishAgents()
        case "permission_requested":
            guard
                let payload = message.data?.first,
                let agentId = payload.agentId,
                let request = payload.request?.asPermissionRequest()
            else {
                return
            }

            pendingPermissionRequests[agentId] = request
            if var agent = socketAgents[agentId] {
                agent.needsPermission = true
                agent.permissionRequest = request
                socketAgents[agentId] = agent
            }
            print("Permission requested for agent \(agentId): \(request.type) \(request.message)")
            publishAgents()
        case "permission_responded":
            guard let requestId = message.data?.first?.requestId else { return }
            print("Permission responded for request \(requestId)")
            clearPermissionState(for: requestId)
        default:
            break
        }
    }

    private func clearPermissionState(for requestId: String) {
        for (id, var agent) in socketAgents where agent.permissionRequest?.id == requestId {
            agent.needsPermission = false
            agent.permissionRequest = nil
            socketAgents[id] = agent
            pendingPermissionRequests.removeValue(forKey: id)
        }
        publishAgents()
    }

    private func applyPendingPermissionsToSocketAgents() {
        guard !pendingPermissionRequests.isEmpty else { return }
        for (id, request) in pendingPermissionRequests {
            if var agent = socketAgents[id] {
                agent.needsPermission = true
                agent.permissionRequest = request
                socketAgents[id] = agent
            }
        }
    }

    func sendPermissionResponse(agentId: String, allowed: Bool) {
        guard let agent = agents.first(where: { $0.id == agentId }) else { return }

        let payload = PermissionResponseMessage(
            type: "permission_response",
            data: PermissionResponseData(
                agentId: agentId,
                requestId: agent.permissionRequest?.id ?? agentId,
                allowed: allowed
            )
        )
        send(payload)
    }

    func clearInteractivePrompt(agentId: String) {
        promptCache.removeValue(forKey: agentId)

        if var agent = socketAgents[agentId] {
            agent.interactivePrompt = nil
            socketAgents[agentId] = agent
        }
        if var agent = processAgents[agentId] {
            agent.interactivePrompt = nil
            processAgents[agentId] = agent
        }
        if var agent = codexAgents[agentId] {
            agent.interactivePrompt = nil
            codexAgents[agentId] = agent
        }

        publishAgents()
    }

    private func send<T: Encodable>(_ value: T) {
        socketQueue.async {
            guard self.socketFD >= 0 else { return }

            do {
                let data = try JSONEncoder().encode(value) + Data([0x0A])
                _ = data.withUnsafeBytes { bytes in
                    write(self.socketFD, bytes.baseAddress, bytes.count)
                }
            } catch {
                print("Socket encode error: \(error)")
            }
        }
    }

    private func handleDisconnect() {
        readSource?.cancel()
        readSource = nil
        socketFD = -1

        DispatchQueue.main.async {
            self.isConnected = false
            self.socketAgents = [:]
            self.publishAgents()
        }

        scheduleReconnect()
    }

    private func scheduleReconnect() {
        reconnectWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            self?.connectToSocket()
        }

        reconnectWorkItem = workItem
        socketQueue.asyncAfter(deadline: .now() + 1, execute: workItem)
    }

    private func startProcessPolling() {
        guard processPollTimer == nil else { return }
        print("SocketService: startProcessPolling")

        refreshProcessAgents()

        processPollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.refreshProcessAgents()
        }
    }

    private func refreshProcessAgents() {
        guard !isRefreshingProcesses else { return }
        isRefreshingProcesses = true

        processQueue.async { [weak self] in
            guard let self else { return }

            defer {
                DispatchQueue.main.async {
                    self.isRefreshingProcesses = false
                }
            }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/ps")
            process.arguments = ["-axo", "pid=,tty=,comm=,args="]

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()

            do {
                try process.run()
            } catch {
                print("Process scan failed: \(error)")
                return
            }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            guard let output = String(data: data, encoding: .utf8) else {
                return
            }

            var detected: [String: Agent] = [:]
            var activeCodexProcesses: [CodexProcessSnapshot] = []

            for line in output.split(separator: "\n") {
                let columns = line.split(maxSplits: 3, whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
                guard columns.count == 4 else { continue }

                let pid = columns[0].trimmingCharacters(in: .whitespaces)
                let tty = columns[1].trimmingCharacters(in: .whitespaces)
                let command = URL(fileURLWithPath: columns[2]).lastPathComponent.lowercased()
                let args = columns[3].trimmingCharacters(in: .whitespaces)

                guard let agentType = self.inferredAgentType(command: command, args: args) else { continue }

                if agentType == .codex, self.isInteractiveCodexProcess(command: command, args: args, tty: tty) {
                    activeCodexProcesses.append(
                        CodexProcessSnapshot(
                            pid: pid,
                            tty: tty == "??" ? "background" : tty,
                            command: command,
                            args: args
                        )
                    )
                }

                let id = "process-\(pid)"
                let name = self.inferredDisplayName(agentType: agentType, args: args, fallback: command)
                detected[id] = Agent(
                    id: id,
                    name: name,
                    type: agentType,
                    status: .running,
                    terminal: tty == "??" ? "background" : tty,
                    tty: tty == "??" ? nil : tty,
                    currentTask: args,
                    lastUpdate: Date()
                )
            }

            DispatchQueue.main.async {
                self.processAgents = detected
                self.refreshCodexAgents(activeProcesses: activeCodexProcesses)
                self.publishAgents()
            }
        }
    }

    private func publishAgents() {
        var merged = Array(socketAgents.values)
        let existingNames = Set(merged.map { "\($0.type.rawValue)|\($0.name.lowercased())" })

        for agent in processAgents.values {
            let key = "\(agent.type.rawValue)|\(agent.name.lowercased())"
            if !existingNames.contains(key) {
                merged.append(agent)
            }
        }

        let namesAfterProcessMerge = Set(merged.map { "\($0.type.rawValue)|\($0.name.lowercased())" })
        for agent in codexAgents.values {
            let key = "\(agent.type.rawValue)|\(agent.name.lowercased())"
            if !namesAfterProcessMerge.contains(key) {
                merged.append(agent)
            }
        }

        merged = merged.map { agent in
            var updatedAgent = agent
            if shouldInspectInteractivePrompt(agent: agent) {
                updatedAgent.interactivePrompt = promptCache[agent.id]?.prompt
            } else {
                updatedAgent.interactivePrompt = nil
                promptCache.removeValue(forKey: agent.id)
            }
            return updatedAgent
        }

        merged = deduplicatedAgents(from: merged)

        agents = merged.sorted {
            if $0.needsPermission != $1.needsPermission {
                return $0.needsPermission && !$1.needsPermission
            }
            return $0.lastUpdate > $1.lastUpdate
        }

        refreshInteractivePrompts(for: agents)
    }

    private func deduplicatedAgents(from merged: [Agent]) -> [Agent] {
        var selectedByKey: [String: Agent] = [:]

        for agent in merged {
            let key = dedupeKey(for: agent)
            if let existing = selectedByKey[key] {
                selectedByKey[key] = preferredAgent(existing, agent)
            } else {
                selectedByKey[key] = agent
            }
        }

        return Array(selectedByKey.values)
    }

    private func dedupeKey(for agent: Agent) -> String {
        if let tty = normalizedTTY(agent.tty ?? agent.terminal), !tty.isEmpty {
            return "\(agent.type.rawValue)|tty:\(tty)"
        }
        if let pid = agent.pid {
            return "\(agent.type.rawValue)|pid:\(pid)"
        }
        if let cwd = agent.cwd?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !cwd.isEmpty {
            return "\(agent.type.rawValue)|cwd:\(cwd)"
        }
        return "\(agent.type.rawValue)|name:\(agent.name.lowercased())"
    }

    private func normalizedTTY(_ tty: String?) -> String? {
        guard let tty else { return nil }
        let trimmed = tty.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("/dev/") {
            return String(trimmed.dropFirst("/dev/".count))
        }
        return trimmed
    }

    private func preferredAgent(_ lhs: Agent, _ rhs: Agent) -> Agent {
        let lhsScore = preferenceScore(for: lhs)
        let rhsScore = preferenceScore(for: rhs)
        if lhsScore != rhsScore {
            return lhsScore > rhsScore ? lhs : rhs
        }
        return lhs.lastUpdate >= rhs.lastUpdate ? lhs : rhs
    }

    private func preferenceScore(for agent: Agent) -> Int {
        var score = 0
        if agent.needsPermission { score += 1000 }
        if agent.interactivePrompt != nil { score += 400 }
        if agent.permissionRequest != nil { score += 250 }
        if agent.terminalApp != nil { score += 120 }
        if agent.tty != nil { score += 120 }
        if agent.pid != nil { score += 80 }
        if agent.cwd != nil { score += 60 }
        if let currentTask = agent.currentTask, !currentTask.isEmpty { score += min(currentTask.count, 80) }
        return score
    }

    private func refreshInteractivePrompts(for agents: [Agent]) {
        let candidates = agents.filter(shouldInspectInteractivePrompt)
        guard !candidates.isEmpty else { return }

        processQueue.async { [weak self] in
            guard let self else { return }

            var updates: [(String, String, InteractivePrompt?)] = []
            for agent in candidates {
                let fingerprint = self.promptFingerprint(for: agent)
                if self.promptCache[agent.id]?.fingerprint == fingerprint {
                    continue
                }

                updates.append((agent.id, fingerprint, TerminalPromptService.detectPrompt(for: agent)))
            }

            guard !updates.isEmpty else { return }

            DispatchQueue.main.async {
                var didChange = false
                for (agentID, fingerprint, prompt) in updates {
                    let previousPrompt = self.promptCache[agentID]?.prompt
                    self.promptCache[agentID] = PromptCacheEntry(fingerprint: fingerprint, prompt: prompt)
                    if self.applyInteractivePrompt(prompt, toAgentID: agentID, previousPrompt: previousPrompt) {
                        didChange = true
                    }
                }

                if didChange {
                    self.publishAgents()
                }
            }
        }
    }

    private func shouldInspectInteractivePrompt(agent: Agent) -> Bool {
        guard !agent.needsPermission else { return false }
        guard let terminalApp = agent.terminalApp?.lowercased(), terminalApp.contains("terminal") else { return false }
        guard let tty = agent.tty, !tty.isEmpty else { return false }
        return agent.status == .waiting || agent.type == .codex
    }

    private func promptFingerprint(for agent: Agent) -> String {
        [
            agent.terminalApp ?? "",
            agent.tty ?? "",
            agent.status.rawValue,
            agent.currentTask ?? "",
            String(agent.lastUpdate.timeIntervalSince1970)
        ].joined(separator: "|")
    }

    @discardableResult
    private func applyInteractivePrompt(_ prompt: InteractivePrompt?, toAgentID agentID: String, previousPrompt: InteractivePrompt?) -> Bool {
        if var agent = socketAgents[agentID] {
            agent.interactivePrompt = prompt
            socketAgents[agentID] = agent
        }
        if var agent = processAgents[agentID] {
            agent.interactivePrompt = prompt
            processAgents[agentID] = agent
        }
        if var agent = codexAgents[agentID] {
            agent.interactivePrompt = prompt
            codexAgents[agentID] = agent
        }

        return !interactivePromptEquals(previousPrompt, prompt)
    }

    private func interactivePromptEquals(_ lhs: InteractivePrompt?, _ rhs: InteractivePrompt?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil):
            return true
        case let (lhs?, rhs?):
            return lhs.id == rhs.id &&
                lhs.title == rhs.title &&
                lhs.options.map(\.value) == rhs.options.map(\.value) &&
                lhs.options.map(\.title) == rhs.options.map(\.title) &&
                lhs.options.map(\.detail) == rhs.options.map(\.detail)
        default:
            return false
        }
    }

    private func refreshCodexAgents(activeProcesses: [CodexProcessSnapshot]) {
        guard !activeProcesses.isEmpty else {
            codexAgents = [:]
            return
        }

        let historyPath = homeDirectory.appendingPathComponent(".codex/history.jsonl").path
        let sessionsRoot = homeDirectory.appendingPathComponent(".codex/sessions").path

        guard
            let historyText = try? String(contentsOfFile: historyPath, encoding: .utf8),
            let sessionFiles = try? FileManager.default.subpathsOfDirectory(atPath: sessionsRoot)
        else {
            print("Codex monitor: failed to read history or sessions directory")
            codexAgents = Dictionary(
                uniqueKeysWithValues: activeProcesses.map { process in
                    let agent = Agent(
                        id: "codex-process:\(process.pid)",
                        name: "codex",
                        type: .codex,
                        status: .running,
                        terminal: process.tty,
                        tty: process.tty,
                        currentTask: process.args,
                        lastUpdate: Date()
                    )
                    return (agent.id, agent)
                }
            )
            return
        }

        print("Codex monitor: loaded history and \(sessionFiles.count) session file(s)")

        let now = Date()
        var recentPromptsBySession: [String: CodexHistoryEntry] = [:]

        for line in historyText.split(separator: "\n").suffix(300) {
            guard
                let data = line.data(using: .utf8),
                let entry = try? JSONDecoder().decode(CodexHistoryEntry.self, from: data)
            else {
                continue
            }

            recentPromptsBySession[entry.sessionID] = entry
        }

        print("Codex monitor: collected \(recentPromptsBySession.count) recent prompt(s)")

        let sortedSessionFiles = sessionFiles
            .filter { $0.hasSuffix(".jsonl") }
            .sorted()
            .suffix(40)

        var recentSessions: [Agent] = []

        for relativePath in sortedSessionFiles.reversed() {
            let absolutePath = "\(sessionsRoot)/\(relativePath)"
            guard
                let fileText = try? String(contentsOfFile: absolutePath, encoding: .utf8),
                let metaLine = fileText.split(separator: "\n").first(where: { $0.contains("\"type\":\"session_meta\"") }),
                let metaData = metaLine.data(using: .utf8),
                let sessionEvent = try? JSONDecoder().decode(CodexSessionEvent.self, from: metaData)
            else {
                continue
            }

            let cwdName = URL(fileURLWithPath: sessionEvent.payload.cwd).lastPathComponent
            let sessionID = sessionEvent.payload.id
            let historyEntry = recentPromptsBySession[sessionID]
            let historyLastUpdate = historyEntry.map { Date(timeIntervalSince1970: $0.ts) }
            let latestSessionTimestamp = sessionEvent.payload.timestamp ?? sessionEvent.timestamp ?? historyLastUpdate ?? now
            if now.timeIntervalSince(latestSessionTimestamp) > 60 * 5 {
                continue
            }
            let task = historyEntry?.text
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let compactTask = String(task.prefix(120))
            let name = "codex — \(cwdName)"
            recentSessions.append(
                Agent(
                id: "codex-session:\(sessionID)",
                name: name,
                type: .codex,
                status: .running,
                terminal: sessionEvent.payload.originator,
                cwd: sessionEvent.payload.cwd,
                currentTask: compactTask.isEmpty ? "Session started in \(cwdName)" : compactTask,
                lastUpdate: latestSessionTimestamp
                )
            )
        }

        recentSessions.sort { $0.lastUpdate > $1.lastUpdate }

        var detected: [String: Agent] = [:]
        for (index, process) in activeProcesses.enumerated() {
            if index < recentSessions.count {
                let sessionAgent = recentSessions[index]
                let agent = Agent(
                    id: "codex-process:\(process.pid)",
                    name: sessionAgent.name,
                    type: sessionAgent.type,
                    status: sessionAgent.status,
                    terminal: process.tty,
                    terminalApp: sessionAgent.terminalApp,
                    tty: process.tty,
                    cwd: sessionAgent.cwd,
                    pid: Int(process.pid),
                    currentTask: sessionAgent.currentTask,
                    lastUpdate: sessionAgent.lastUpdate,
                    needsPermission: sessionAgent.needsPermission,
                    permissionRequest: sessionAgent.permissionRequest
                )
                detected[agent.id] = agent
            } else {
                let agent = Agent(
                    id: "codex-process:\(process.pid)",
                    name: "codex",
                    type: .codex,
                    status: .running,
                    terminal: process.tty,
                    tty: process.tty,
                    pid: Int(process.pid),
                    currentTask: process.args,
                    lastUpdate: now
                )
                detected[agent.id] = agent
            }
        }

        codexAgents = detected
        print("Codex monitor: built \(detected.count) visible codex agent(s) from \(activeProcesses.count) active codex process(es)")
    }

    private func inferredAgentType(command: String, args: String) -> AgentType? {
        let haystack = "\(command) \(args)".lowercased()

        if haystack.contains("claude") {
            return .claude
        }
        if haystack.contains("codex") {
            return .codex
        }
        if haystack.contains("cursor") {
            return .cursor
        }
        if haystack.contains("gemini") {
            return .gemini
        }
        if haystack.contains("opencode") || haystack.contains("open_code") {
            return .openCode
        }

        return nil
    }

    private func isInteractiveCodexProcess(command: String, args: String, tty: String) -> Bool {
        let haystack = "\(command) \(args)".lowercased()
        if !haystack.contains("codex") {
            return false
        }
        if haystack.contains("codex-wrapper.js") {
            return false
        }
        if haystack.contains("app-server") {
            return false
        }
        if tty == "??" {
            return false
        }
        return true
    }

    private func inferredDisplayName(agentType: AgentType, args: String, fallback: String) -> String {
        let trimmedArgs = args.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedArgs.isEmpty {
            return trimmedArgs
        }
        return fallback.isEmpty ? agentType.rawValue : fallback
    }
}

private struct CodexProcessSnapshot {
    let pid: String
    let tty: String
    let command: String
    let args: String
}

private struct PromptCacheEntry {
    let fingerprint: String
    let prompt: InteractivePrompt?
}

private struct CodexHistoryEntry: Decodable {
    let sessionID: String
    let ts: TimeInterval
    let text: String

    private enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case ts
        case text
    }
}

private struct CodexSessionEvent: Decodable {
    let timestamp: Date?
    let payload: CodexSessionPayload

    private enum CodingKeys: String, CodingKey {
        case timestamp
        case payload
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let rawTimestamp = try? container.decode(String.self, forKey: .timestamp) {
            timestamp = ISO8601DateFormatter().date(from: rawTimestamp)
        } else {
            timestamp = nil
        }
        payload = try container.decode(CodexSessionPayload.self, forKey: .payload)
    }
}

private struct CodexSessionPayload: Decodable {
    let id: String
    let cwd: String
    let originator: String
    let timestamp: Date?

    private enum CodingKeys: String, CodingKey {
        case id
        case cwd
        case originator
        case timestamp
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        cwd = try container.decode(String.self, forKey: .cwd)
        originator = try container.decode(String.self, forKey: .originator)
        if let rawTimestamp = try? container.decode(String.self, forKey: .timestamp) {
            timestamp = ISO8601DateFormatter().date(from: rawTimestamp)
        } else {
            timestamp = nil
        }
    }
}

private struct ServerMessage: Decodable {
    let type: String
    let data: [MessagePayload]?

    private enum CodingKeys: String, CodingKey {
        case type
        case data
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)

        if let payloads = try? container.decode([MessagePayload].self, forKey: .data) {
            data = payloads
        } else if let payload = try? container.decode(MessagePayload.self, forKey: .data) {
            data = [payload]
        } else {
            data = nil
        }
    }
}

private struct MessagePayload: Decodable {
    let id: String?
    let name: String?
    let type: String?
    let status: String?
    let terminal: String?
    let terminalApp: String?
    let tty: String?
    let cwd: String?
    let pid: Int?
    let terminalTitleToken: String?
    let parentPid: Int?
    let parentCommand: String?
    let processChain: [String]?
    let environmentHints: [String: String]?
    let jetbrainsContext: [String: String]?
    let currentTask: String?
    let lastUpdate: Double?
    let needsPermission: Bool?
    let permissionRequest: PermissionRequestPayload?
    let agentId: String?
    let request: PermissionRequestPayload?
    let requestId: String?

    func asAgent() -> Agent? {
        guard
            let id,
            let name,
            let type,
            let terminal
        else {
            return nil
        }

        let agentType = (try? JSONDecoder().decode(AgentType.self, from: Data("\"\(type)\"".utf8))) ?? .claude
        let agentStatus = AgentStatus(rawValue: status ?? "running") ?? .running
        let lastUpdateDate = lastUpdate.map { Date(timeIntervalSince1970: $0 / 1000) } ?? Date()

        return Agent(
            id: id,
            name: name,
            type: agentType,
            status: agentStatus,
            terminal: terminal,
            terminalApp: terminalApp,
            tty: tty,
            cwd: cwd,
            pid: pid,
            terminalTitleToken: terminalTitleToken,
            parentPid: parentPid,
            parentCommand: parentCommand,
            processChain: processChain,
            environmentHints: environmentHints,
            jetbrainsContext: jetbrainsContext,
            currentTask: currentTask,
            lastUpdate: lastUpdateDate,
            needsPermission: needsPermission ?? false,
            permissionRequest: permissionRequest?.asPermissionRequest()
        )
    }
}

private struct PermissionRequestPayload: Decodable {
    let id: String
    let type: String
    let message: String
    let filePath: String?
    let timestamp: Double?

    func asPermissionRequest() -> PermissionRequest {
        PermissionRequest(
            id: id,
            type: type,
            message: message,
            filePath: filePath,
            timestamp: timestamp.map { Date(timeIntervalSince1970: $0 / 1000) } ?? Date()
        )
    }
}

private struct PermissionResponseMessage: Encodable {
    let type: String
    let data: PermissionResponseData
}

private struct PermissionResponseData: Encodable {
    let agentId: String
    let requestId: String
    let allowed: Bool
}

// MARK: - Color Extension
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
