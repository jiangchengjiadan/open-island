import XCTest
@testable import OpenIslandCore

final class CodexSessionPairingTests: XCTestCase {
    func testSwappedCollectionOrderStillMapsByCWD() {
        let processes = [
            CodexProcessRecord(pid: "200", tty: "ttys002", command: "codex", args: "codex", cwd: "/Users/a/beta"),
            CodexProcessRecord(pid: "100", tty: "ttys001", command: "codex", args: "codex", cwd: "/Users/a/alpha"),
        ]
        let newer = Date(timeIntervalSince1970: 200)
        let older = Date(timeIntervalSince1970: 100)
        let sessions = [
            CodexSessionRecord(
                sessionID: "sess-beta",
                cwd: "/Users/a/beta",
                originator: "codex",
                jsonlPath: "/tmp/beta.jsonl",
                currentTask: "work in beta",
                name: "codex -- beta",
                lastUpdate: newer
            ),
            CodexSessionRecord(
                sessionID: "sess-alpha",
                cwd: "/Users/a/alpha",
                originator: "codex",
                jsonlPath: "/tmp/alpha.jsonl",
                currentTask: "work in alpha",
                name: "codex -- alpha",
                lastUpdate: older
            ),
        ]

        let swappedSessions = Array(sessions.reversed())
        let result = CodexSessionPairing.pair(processes: processes, sessions: swappedSessions)

        XCTAssertEqual(result.paired.count, 2)
        XCTAssertTrue(result.unpairedProcesses.isEmpty)
        XCTAssertTrue(result.unpairedSessions.isEmpty)

        let sessionIDByPID = Dictionary(uniqueKeysWithValues: result.paired.map { ($0.process.pid, $0.session.sessionID) })
        XCTAssertEqual(sessionIDByPID["100"], "sess-alpha")
        XCTAssertEqual(sessionIDByPID["200"], "sess-beta")
        let nameByPID = Dictionary(uniqueKeysWithValues: result.paired.map { ($0.process.pid, $0.session.name) })
        XCTAssertEqual(nameByPID["100"], "codex -- alpha")
        XCTAssertEqual(nameByPID["200"], "codex -- beta")
    }

    func testLeftoverProcessWithNoSession() {
        let processes = [
            CodexProcessRecord(pid: "11", tty: "ttys001", command: "codex", args: "codex", cwd: "/Users/a/alpha"),
            CodexProcessRecord(pid: "22", tty: "ttys002", command: "codex", args: "codex", cwd: "/Users/a/orphan"),
        ]
        let sessions = [
            CodexSessionRecord(
                sessionID: "sess-alpha",
                cwd: "/Users/a/alpha",
                originator: "codex",
                jsonlPath: "/tmp/alpha.jsonl",
                currentTask: "alpha",
                name: "codex -- alpha",
                lastUpdate: Date(timeIntervalSince1970: 1)
            )
        ]

        let result = CodexSessionPairing.pair(processes: processes, sessions: sessions)

        XCTAssertEqual(result.paired.count, 1)
        XCTAssertEqual(result.paired[0].process.pid, "11")
        XCTAssertEqual(result.paired[0].session.sessionID, "sess-alpha")
        XCTAssertEqual(result.unpairedProcesses.map(\.pid), ["22"])
        XCTAssertTrue(result.unpairedSessions.isEmpty)
    }

    func testLeftoverSessionWithNoProcess() {
        let processes = [
            CodexProcessRecord(pid: "11", tty: "ttys001", command: "codex", args: "codex", cwd: "/Users/a/alpha"),
        ]
        let sessions = [
            CodexSessionRecord(
                sessionID: "sess-alpha",
                cwd: "/Users/a/alpha",
                originator: "codex",
                jsonlPath: "/tmp/alpha.jsonl",
                currentTask: "alpha",
                name: "codex -- alpha",
                lastUpdate: Date(timeIntervalSince1970: 2)
            ),
            CodexSessionRecord(
                sessionID: "sess-ghost",
                cwd: "/Users/a/ghost",
                originator: "codex",
                jsonlPath: "/tmp/ghost.jsonl",
                currentTask: "ghost",
                name: "codex -- ghost",
                lastUpdate: Date(timeIntervalSince1970: 1)
            ),
        ]

        let result = CodexSessionPairing.pair(processes: processes, sessions: sessions)

        XCTAssertEqual(result.paired.count, 1)
        XCTAssertEqual(result.paired[0].process.pid, "11")
        XCTAssertEqual(result.paired[0].session.sessionID, "sess-alpha")
        XCTAssertTrue(result.unpairedProcesses.isEmpty)
        XCTAssertEqual(result.unpairedSessions.map(\.sessionID), ["sess-ghost"])
    }

    func testPidMatchBeatsSwappedCWDOrder() {
        let processes = [
            CodexProcessRecord(pid: "100", tty: "ttys001", command: "codex", args: "codex", cwd: "/Users/a/alpha"),
            CodexProcessRecord(pid: "200", tty: "ttys002", command: "codex", args: "codex", cwd: "/Users/a/beta"),
        ]
        let sessions = [
            CodexSessionRecord(
                sessionID: "sess-beta",
                cwd: "/Users/a/beta",
                originator: "codex",
                jsonlPath: "/tmp/beta.jsonl",
                currentTask: "beta",
                name: "codex -- beta",
                lastUpdate: Date(timeIntervalSince1970: 2),
                pid: "100"
            ),
            CodexSessionRecord(
                sessionID: "sess-alpha",
                cwd: "/Users/a/alpha",
                originator: "codex",
                jsonlPath: "/tmp/alpha.jsonl",
                currentTask: "alpha",
                name: "codex -- alpha",
                lastUpdate: Date(timeIntervalSince1970: 1),
                pid: "200"
            ),
        ]
        let result = CodexSessionPairing.pair(processes: processes, sessions: sessions)
        let sessionIDByPID = Dictionary(uniqueKeysWithValues: result.paired.map { ($0.process.pid, $0.session.sessionID) })
        XCTAssertEqual(sessionIDByPID["100"], "sess-beta")
        XCTAssertEqual(sessionIDByPID["200"], "sess-alpha")
        XCTAssertTrue(result.unpairedProcesses.isEmpty)
        XCTAssertTrue(result.unpairedSessions.isEmpty)
    }
}
