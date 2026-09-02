import Foundation

public struct CodexProcessRecord: Equatable {
    public var pid: String
    public var tty: String
    public var command: String
    public var args: String
    public var cwd: String?

    public init(pid: String, tty: String, command: String, args: String, cwd: String? = nil) {
        self.pid = pid
        self.tty = tty
        self.command = command
        self.args = args
        self.cwd = cwd
    }
}

public struct CodexSessionRecord: Equatable {
    public var sessionID: String
    public var cwd: String
    public var originator: String
    public var jsonlPath: String
    public var currentTask: String
    public var name: String
    public var lastUpdate: Date
    public var pid: String?

    public init(
        sessionID: String,
        cwd: String,
        originator: String,
        jsonlPath: String,
        currentTask: String,
        name: String,
        lastUpdate: Date,
        pid: String? = nil
    ) {
        self.sessionID = sessionID
        self.cwd = cwd
        self.originator = originator
        self.jsonlPath = jsonlPath
        self.currentTask = currentTask
        self.name = name
        self.lastUpdate = lastUpdate
        self.pid = pid
    }
}

public struct CodexPairedSession: Equatable {
    public var process: CodexProcessRecord
    public var session: CodexSessionRecord

    public init(process: CodexProcessRecord, session: CodexSessionRecord) {
        self.process = process
        self.session = session
    }
}

public struct CodexPairingResult: Equatable {
    public var paired: [CodexPairedSession]
    public var unpairedProcesses: [CodexProcessRecord]
    public var unpairedSessions: [CodexSessionRecord]

    public init(
        paired: [CodexPairedSession],
        unpairedProcesses: [CodexProcessRecord],
        unpairedSessions: [CodexSessionRecord]
    ) {
        self.paired = paired
        self.unpairedProcesses = unpairedProcesses
        self.unpairedSessions = unpairedSessions
    }
}

/// Matches Codex processes to jsonl sessions by stable keys (pid, session id, jsonl path, cwd).
/// Never zips two independently ordered arrays by index.
public enum CodexSessionPairing {
    public static func pair(
        processes: [CodexProcessRecord],
        sessions: [CodexSessionRecord]
    ) -> CodexPairingResult {
        var processUsed = Array(repeating: false, count: processes.count)
        var sessionUsed = Array(repeating: false, count: sessions.count)
        var paired: [CodexPairedSession] = []

        func claim(_ processIndex: Int, _ sessionIndex: Int) {
            guard !processUsed[processIndex], !sessionUsed[sessionIndex] else { return }
            processUsed[processIndex] = true
            sessionUsed[sessionIndex] = true
            paired.append(
                CodexPairedSession(process: processes[processIndex], session: sessions[sessionIndex])
            )
        }

        func uniqueMatch(_ matches: (CodexProcessRecord, CodexSessionRecord) -> Bool) {
            var assignments: [(Int, Int)] = []
            for processIndex in processes.indices where !processUsed[processIndex] {
                let candidates = sessions.indices.filter { sessionIndex in
                    !sessionUsed[sessionIndex] && matches(processes[processIndex], sessions[sessionIndex])
                }
                guard candidates.count == 1 else { continue }
                let sessionIndex = candidates[0]
                let reverse = processes.indices.filter { otherProcess in
                    !processUsed[otherProcess] && matches(processes[otherProcess], sessions[sessionIndex])
                }
                guard reverse.count == 1 else { continue }
                assignments.append((processIndex, sessionIndex))
            }

            var claimedProcesses = Set<Int>()
            var claimedSessions = Set<Int>()
            for (processIndex, sessionIndex) in assignments {
                if claimedProcesses.contains(processIndex) || claimedSessions.contains(sessionIndex) {
                    continue
                }
                claimedProcesses.insert(processIndex)
                claimedSessions.insert(sessionIndex)
                claim(processIndex, sessionIndex)
            }
        }

        uniqueMatch { process, session in
            guard let sessionPID = normalizedPID(session.pid) else { return false }
            return normalizedPID(process.pid) == sessionPID
        }

        uniqueMatch { process, session in
            argsContainToken(process.args, session.sessionID)
        }

        uniqueMatch { process, session in
            !session.jsonlPath.isEmpty && argsContainToken(process.args, session.jsonlPath)
        }

        uniqueMatch { process, session in
            guard let processCWD = normalizedCWD(process.cwd),
                  let sessionCWD = normalizedCWD(session.cwd) else {
                return false
            }
            return processCWD == sessionCWD
        }

        var processesByCWD: [String: [Int]] = [:]
        var sessionsByCWD: [String: [Int]] = [:]
        for processIndex in processes.indices where !processUsed[processIndex] {
            if let cwd = normalizedCWD(processes[processIndex].cwd) {
                processesByCWD[cwd, default: []].append(processIndex)
            }
        }
        for sessionIndex in sessions.indices where !sessionUsed[sessionIndex] {
            if let cwd = normalizedCWD(sessions[sessionIndex].cwd) {
                sessionsByCWD[cwd, default: []].append(sessionIndex)
            }
        }

        for cwd in processesByCWD.keys.sorted() {
            guard var sessionIndices = sessionsByCWD[cwd] else { continue }
            var processIndices = processesByCWD[cwd] ?? []
            processIndices.sort { processes[$0].pid < processes[$1].pid }
            sessionIndices.sort {
                if sessions[$0].lastUpdate != sessions[$1].lastUpdate {
                    return sessions[$0].lastUpdate > sessions[$1].lastUpdate
                }
                return sessions[$0].sessionID < sessions[$1].sessionID
            }
            let count = min(processIndices.count, sessionIndices.count)
            for index in 0..<count {
                claim(processIndices[index], sessionIndices[index])
            }
        }

        return CodexPairingResult(
            paired: paired,
            unpairedProcesses: processes.indices.filter { !processUsed[$0] }.map { processes[$0] },
            unpairedSessions: sessions.indices.filter { !sessionUsed[$0] }.map { sessions[$0] }
        )
    }

    public static func normalizedCWD(_ cwd: String?) -> String? {
        guard let cwd else { return nil }
        var trimmed = cwd.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.count > 1 && trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }
        return trimmed.lowercased()
    }

    public static func normalizedPID(_ pid: String?) -> String? {
        guard let pid else { return nil }
        let trimmed = pid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed
    }

    static func argsContainToken(_ args: String, _ token: String) -> Bool {
        let needle = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return false }
        return args.contains(needle)
    }
}
