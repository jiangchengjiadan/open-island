import Foundation

enum UsageFetcher {
    static func fetchCodex() async -> AppUsage {
        guard let token = readCodexAccessToken() else {
            return errorPair("no codex auth")
        }

        var request = URLRequest(url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0

            if statusCode == 401 {
                return errorPair("auth expired")
            }
            guard statusCode == 200 else {
                return errorPair("http \(statusCode)")
            }
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let rateLimit = object["rate_limit"] as? [String: Any] else {
                return errorPair("parse error")
            }

            return AppUsage(
                fiveHour: parseCodexWindow(rateLimit["primary_window"]),
                weekly: parseCodexWindow(rateLimit["secondary_window"]),
                plan: object["plan_type"] as? String
            )
        } catch {
            return errorPair(error.localizedDescription)
        }
    }

    static func fetchClaude() async -> AppUsage {
        let resolution = await ClaudeCredentials.resolveUsage { token, plan in
            await fetchClaudeUsage(token: token, plan: plan)
        }

        switch resolution {
        case .usage(let usage):
            return usage
        case .reauthRequired(let message), .failed(let message):
            return errorPair(message)
        }
    }

    private static func fetchClaudeUsage(token: String, plan: String?) async -> ClaudeCredentials.ProbeOutcome {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("claude-code/2.1.121", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0

            if statusCode == 401 {
                return .unauthorized
            }
            if statusCode == 403 {
                return .scopeInsufficient
            }
            if statusCode == 429 {
                return .rateLimited
            }
            guard statusCode == 200 else {
                return .otherError("http \(statusCode)")
            }
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return .otherError("parse error")
            }
            if let error = object["error"] as? [String: Any],
               let type = error["type"] as? String,
               type == "rate_limit_error" {
                return .rateLimited
            }

            return .success(AppUsage(
                fiveHour: parseClaudeWindow(object["five_hour"]),
                weekly: parseClaudeWindow(object["seven_day"]),
                plan: plan
            ))
        } catch {
            return .otherError(error.localizedDescription)
        }
    }

    private static func errorPair(_ message: String) -> AppUsage {
        AppUsage(
            fiveHour: WindowUsage(usedPercent: 0, resetAt: nil, error: message),
            weekly: WindowUsage(usedPercent: 0, resetAt: nil, error: message),
            plan: nil
        )
    }

    private static func readCodexAccessToken() -> String? {
        let path = NSString(string: "~/.codex/auth.json").expandingTildeInPath
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tokens = json["tokens"] as? [String: Any],
              let token = tokens["access_token"] as? String,
              !token.isEmpty else {
            return nil
        }
        return token
    }

    private static func parseCodexWindow(_ value: Any?) -> WindowUsage {
        guard let object = value as? [String: Any] else {
            return .unknown
        }
        let used = (object["used_percent"] as? Double) ?? 0
        let resetAt = (object["reset_at"] as? Double).map { Date(timeIntervalSince1970: $0) }
        return WindowUsage(usedPercent: min(1, max(0, used / 100)), resetAt: resetAt, error: nil)
    }

    private static func parseClaudeWindow(_ value: Any?) -> WindowUsage {
        guard let object = value as? [String: Any] else {
            return .unknown
        }
        let raw = (object["utilization"] as? Double) ?? (object["used_percent"] as? Double) ?? 0
        let resetAt = parseResetDate(object["resets_at"])
        return WindowUsage(usedPercent: min(1, max(0, raw / 100)), resetAt: resetAt, error: nil)
    }

    private static func parseResetDate(_ value: Any?) -> Date? {
        if let timestamp = value as? Double {
            return Date(timeIntervalSince1970: timestamp)
        }
        if let string = value as? String {
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return fractional.date(from: string) ?? ISO8601DateFormatter().date(from: string)
        }
        return nil
    }
}

enum ClaudeCredentials {
    static let reauthRequiredMessage = "re-login: claude /login"

    enum ProbeOutcome {
        case success(AppUsage)
        case rateLimited
        case unauthorized
        case scopeInsufficient
        case otherError(String)
    }

    enum Resolution {
        case usage(AppUsage)
        case reauthRequired(String)
        case failed(String)
    }

    private struct ClaudeCreds {
        let account: String
        let accessToken: String
        let refreshToken: String
        let oauth: [String: Any]
        let subscriptionType: String?
    }

    static func resolveUsage(probe: (_ token: String, _ plan: String?) async -> ProbeOutcome) async -> Resolution {
        var lastError = "auth required"
        let cachedCredentials = readClaudeCreds()
        let plan = cachedCredentials?.subscriptionType

        if let envToken = ProcessInfo.processInfo.environment["CLAUDE_CODE_OAUTH_TOKEN"],
           !envToken.isEmpty {
            switch await probe(envToken, plan) {
            case .success(let usage):
                return .usage(usage)
            case .rateLimited:
                lastError = "rate limited"
            case .unauthorized:
                break
            case .scopeInsufficient:
                lastError = reauthRequiredMessage
            case .otherError(let message):
                lastError = message
            }
        }

        guard let credentials = cachedCredentials else {
            return .failed(lastError)
        }

        switch await probe(credentials.accessToken, plan) {
        case .success(let usage):
            return .usage(usage)
        case .rateLimited:
            lastError = "rate limited"
        case .unauthorized:
            break
        case .scopeInsufficient:
            return .reauthRequired(reauthRequiredMessage)
        case .otherError(let message):
            lastError = message
        }

        if let refreshed = await refreshClaudeToken(refreshToken: credentials.refreshToken) {
            var updatedOauth = credentials.oauth
            updatedOauth["accessToken"] = refreshed.accessToken
            updatedOauth["refreshToken"] = refreshed.refreshToken
            updatedOauth["expiresAt"] = refreshed.expiresAt
            writeClaudeCreds(account: credentials.account, oauth: updatedOauth)

            switch await probe(refreshed.accessToken, plan) {
            case .success(let usage):
                return .usage(usage)
            case .rateLimited:
                lastError = "rate limited"
            case .unauthorized:
                lastError = "auth expired"
            case .scopeInsufficient:
                return .reauthRequired(reauthRequiredMessage)
            case .otherError(let message):
                lastError = message
            }
        }

        return .failed(lastError)
    }

    private static func readClaudeCreds() -> ClaudeCreds? {
        guard let account = readKeychainAccount() else {
            return nil
        }

        let task = Process()
        task.launchPath = "/usr/bin/security"
        task.arguments = [
            "find-generic-password",
            "-s", "Claude Code-credentials",
            "-a", account,
            "-w",
        ]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()

        do {
            try task.run()
            task.waitUntilExit()
            guard task.terminationStatus == 0 else {
                return nil
            }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let raw = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                  let jsonData = raw.data(using: .utf8),
                  let outer = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                  let oauth = outer["claudeAiOauth"] as? [String: Any],
                  let accessToken = oauth["accessToken"] as? String,
                  let refreshToken = oauth["refreshToken"] as? String,
                  !accessToken.isEmpty else {
                return nil
            }
            return ClaudeCreds(
                account: account,
                accessToken: accessToken,
                refreshToken: refreshToken,
                oauth: oauth,
                subscriptionType: oauth["subscriptionType"] as? String
            )
        } catch {
            return nil
        }
    }

    private static func readKeychainAccount() -> String? {
        let task = Process()
        task.launchPath = "/usr/bin/security"
        task.arguments = ["find-generic-password", "-s", "Claude Code-credentials"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()

        do {
            try task.run()
            task.waitUntilExit()
            guard task.terminationStatus == 0 else {
                return nil
            }
            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            for line in output.split(separator: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard trimmed.hasPrefix("\"acct\""),
                      let equals = trimmed.firstIndex(of: "=") else {
                    continue
                }
                let value = trimmed[trimmed.index(after: equals)...]
                guard value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 else {
                    return nil
                }
                let account = value.dropFirst().dropLast()
                return account.isEmpty ? nil : String(account)
            }
            return nil
        } catch {
            return nil
        }
    }

    @discardableResult
    private static func writeClaudeCreds(account: String, oauth: [String: Any]) -> Bool {
        let payload: [String: Any] = ["claudeAiOauth": oauth]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: []),
              let json = String(data: data, encoding: .utf8) else {
            NSLog("OpenIsland: failed to serialize rotated Claude token")
            return false
        }

        let task = Process()
        task.launchPath = "/usr/bin/security"
        task.arguments = [
            "add-generic-password",
            "-U",
            "-s", "Claude Code-credentials",
            "-a", account,
            "-w", json,
        ]
        task.standardOutput = Pipe()
        task.standardError = Pipe()

        do {
            try task.run()
            task.waitUntilExit()
            if task.terminationStatus != 0 {
                NSLog("OpenIsland: failed to write rotated Claude token (security exit %d)", task.terminationStatus)
                return false
            }
            return true
        } catch {
            NSLog("OpenIsland: failed to spawn security for Claude token write: %@", error.localizedDescription)
            return false
        }
    }

    private struct RefreshedTokens {
        let accessToken: String
        let refreshToken: String
        let expiresAt: Int64
    }

    private static func refreshClaudeToken(refreshToken: String) async -> RefreshedTokens? {
        var request = URLRequest(url: URL(string: "https://platform.claude.com/v1/oauth/token")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": "9d1c250a-e61b-44d9-88ed-5944d1962f5e",
        ])

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let accessToken = object["access_token"] as? String,
                  let refreshToken = object["refresh_token"] as? String else {
                return nil
            }
            let expiresIn = (object["expires_in"] as? Double) ?? 28_800
            let expiresAt = Int64((Date().timeIntervalSince1970 + expiresIn) * 1000)
            return RefreshedTokens(accessToken: accessToken, refreshToken: refreshToken, expiresAt: expiresAt)
        } catch {
            return nil
        }
    }

    static func canPromptReauth() -> Bool {
        guard readKeychainAccount() != nil else {
            return false
        }
        return locateClaudeBinary() != nil
    }

    @discardableResult
    static func spawnReauth() -> Bool {
        guard let path = locateClaudeBinary() else {
            return false
        }

        guard let scriptURL = writeClaudeReauthScript(binaryPath: path) else {
            return false
        }

        let task = Process()
        task.launchPath = "/usr/bin/open"
        task.arguments = ["-a", "Terminal", scriptURL.path]
        task.standardOutput = Pipe()
        task.standardError = Pipe()

        do {
            try task.run()
            return true
        } catch {
            NSLog("OpenIsland: failed to spawn claude auth login: %@", error.localizedDescription)
            return false
        }
    }

    /// Launches Claude re-auth in a real Terminal session so the CLI still has a TTY.
    private static func writeClaudeReauthScript(binaryPath: String) -> URL? {
        let tempDirectory = FileManager.default.temporaryDirectory
        let scriptURL = tempDirectory.appendingPathComponent("open-island-claude-reauth.sh")
        let script = """
        #!/bin/bash
        clear
        echo "Open Island launched Claude re-authentication."
        echo ""
        exec \(shellQuoted(binaryPath)) auth login
        """

        do {
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: scriptURL.path
            )
            return scriptURL
        } catch {
            NSLog("OpenIsland: failed to prepare Claude reauth script: %@", error.localizedDescription)
            return nil
        }
    }

    /// Performs the minimal shell escaping needed for a binary path embedded in a script.
    private static func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private static func locateClaudeBinary() -> String? {
        let home = NSHomeDirectory()
        let candidates = [
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
            "\(home)/.bun/bin/claude",
            "\(home)/.npm-global/bin/claude",
            "\(home)/.local/bin/claude",
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }

        let nvmRoot = "\(home)/.nvm/versions/node"
        if let versions = try? FileManager.default.contentsOfDirectory(atPath: nvmRoot) {
            for version in versions.sorted(by: >) {
                let candidate = "\(nvmRoot)/\(version)/bin/claude"
                if FileManager.default.isExecutableFile(atPath: candidate) {
                    return candidate
                }
            }
        }

        return nil
    }
}
