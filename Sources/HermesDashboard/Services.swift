import AppKit
import Foundation
import ImageIO

private final class ProcessRunner {
    static func run(executable: String, arguments: [String], timeout: TimeInterval = 4) -> String? {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return nil
        }

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        if process.isRunning {
            process.terminate()
            return nil
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private final class AppleScriptRunner {
    static func run(_ source: String, timeout: TimeInterval = 5) -> String? {
        ProcessRunner.run(executable: "/usr/bin/osascript", arguments: ["-e", source], timeout: timeout)
    }
}

final class AppleMusicService {
    private let queue = DispatchQueue(label: "hermes-dashboard.music", qos: .utility)

    func fetch(completion: @escaping (MusicSnapshot) -> Void) {
        queue.async {
            let snapshot = self.readCurrentTrack() ?? .notPlaying
            DispatchQueue.main.async { completion(snapshot) }
        }
    }

    private func readCurrentTrack() -> MusicSnapshot? {
        let isRunning = NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == "com.apple.Music"
        }
        guard isRunning else { return .notPlaying }

        let script = #"""
        tell application "Music"
            set currentState to (player state as text)
            if currentState is "stopped" then return "stopped"
            set separator to ASCII character 9
            set trackName to name of current track as text
            set artistName to artist of current track as text
            set albumName to album of current track as text
            set positionText to player position as text
            set durationText to duration of current track as text
            return currentState & separator & trackName & separator & artistName & separator & albumName & separator & positionText & separator & durationText
        end tell
        """#

        guard let output = AppleScriptRunner.run(script), !output.isEmpty else { return nil }
        let values = output.components(separatedBy: "\t")
        guard values.count >= 6 else { return nil }
        let state = values[0].lowercased()
        return MusicSnapshot(
            artist: values[2].isEmpty ? "UNKNOWN ARTIST" : values[2].uppercased(),
            title: values[1].isEmpty ? "UNTITLED" : values[1].uppercased(),
            album: values[3],
            isPlaying: state == "playing",
            position: Double(values[4]) ?? 0,
            duration: Double(values[5]) ?? 0
        )
    }
}

final class SystemWeatherService {
    private let queue = DispatchQueue(label: "hermes-dashboard.weather", qos: .utility)
    private let fileManager = FileManager.default

    func fetch(city: String = "", completion: @escaping (WeatherSnapshot) -> Void) {
        queue.async {
            if !city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if let live = self.fetchFromOpenMeteo(city: city) ?? self.fetchFromWttr(city: city) {
                    DispatchQueue.main.async { completion(live) }
                    return
                }
            }
            if let cached = self.readWeatherCache() {
                DispatchQueue.main.async { completion(cached) }
                return
            }

            let bridgeOutput = self.readWeatherAppAccessibilityTree()
            let parsed = self.parseWeatherText(bridgeOutput) ?? .demo
            DispatchQueue.main.async { completion(parsed) }
        }
    }

    private func jsonObject(from url: URL, timeout: TimeInterval = 8) -> [String: Any]? {
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.setValue("HermesDashboard/1.0", forHTTPHeaderField: "User-Agent")
        let semaphore = DispatchSemaphore(value: 0)
        var result: [String: Any]?
        let task = URLSession.shared.dataTask(with: request) { data, response, _ in
            defer { semaphore.signal() }
            guard let data, (response as? HTTPURLResponse)?.statusCode == 200,
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
            result = object
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + timeout + 1)
        return result
    }

    private func jsonNumber(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let number = value as? Double { return number }
        if let text = value as? String { return Double(text) }
        return nil
    }

    private func geocodeOpenMeteo(city: String) -> (lat: Double, lon: Double)? {
        let key = city.trimmingCharacters(in: .whitespacesAndNewlines)
        let aliases: [String: (Double, Double)] = [
            "fuzhou": (26.0745, 119.2965),
            "福州": (26.0745, 119.2965),
            "福州市": (26.0745, 119.2965)
        ]
        if let known = aliases[key.lowercased()] ?? aliases[key] {
            return (known.0, known.1)
        }
        var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")
        components?.queryItems = [
            URLQueryItem(name: "name", value: key),
            URLQueryItem(name: "count", value: "8"),
            URLQueryItem(name: "language", value: "zh")
        ]
        guard let url = components?.url, let object = jsonObject(from: url),
              let results = object["results"] as? [[String: Any]], !results.isEmpty else { return nil }
        let preferred = results.first { ($0["country_code"] as? String) == "CN" } ?? results[0]
        guard let lat = jsonNumber(preferred["latitude"]), let lon = jsonNumber(preferred["longitude"]) else { return nil }
        return (lat, lon)
    }

    private func conditionFromWMO(_ code: Int) -> WeatherCondition {
        switch code {
        case 0, 1: return .clear
        case 2: return .partlyCloudy
        case 3: return .cloudy
        case 45, 48: return .fog
        case 51, 53, 55, 56, 57: return .drizzle
        case 61, 63, 65, 66, 67, 80, 81, 82: return .rain
        case 71, 73, 75, 77, 85, 86: return .snow
        case 95, 96, 99: return .thunderstorm
        default: return .unknown
        }
    }

    private func fetchFromOpenMeteo(city: String) -> WeatherSnapshot? {
        guard let coords = geocodeOpenMeteo(city: city) else { return nil }
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(coords.lat)),
            URLQueryItem(name: "longitude", value: String(coords.lon)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code"),
            URLQueryItem(name: "timezone", value: "auto")
        ]
        guard let url = components?.url, let object = jsonObject(from: url),
              let current = object["current"] as? [String: Any],
              let temp = jsonNumber(current["temperature_2m"]) else { return nil }
        let code = Int(jsonNumber(current["weather_code"]) ?? -1)
        let rounded = Int(temp.rounded())
        return WeatherSnapshot(temperature: "\(rounded)°C", condition: conditionFromWMO(code), location: city, isLive: true)
    }

    private func fetchFromWttr(city: String) -> WeatherSnapshot? {
        let encoded = city.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? city
        guard let url = URL(string: "https://wttr.in/\(encoded)?format=j1"),
              let object = jsonObject(from: url, timeout: 6),
              let current = (object["current_condition"] as? [[String: Any]])?.first else { return nil }
        let temp = (current["temp_C"] as? String) ?? (current["temp_C"] as? NSNumber)?.stringValue ?? "--"
        let description = ((current["weatherDesc"] as? [[String: Any]])?.first?["value"] as? String ?? "").lowercased()
        let condition: WeatherCondition
        if description.contains("thunder") || description.contains("storm") { condition = .thunderstorm }
        else if description.contains("snow") { condition = .snow }
        else if description.contains("drizzle") { condition = .drizzle }
        else if description.contains("rain") { condition = .rain }
        else if description.contains("fog") || description.contains("mist") { condition = .fog }
        else if description.contains("overcast") { condition = .cloudy }
        else if description.contains("cloud") { condition = .partlyCloudy }
        else if description.contains("clear") || description.contains("sun") { condition = .clear }
        else { condition = .unknown }
        return WeatherSnapshot(temperature: "\(temp)°C", condition: condition, location: city, isLive: true)
    }

    private func readWeatherAppAccessibilityTree() -> String? {
        let script = #"""
        tell application "System Events"
            if not (exists process "Weather") then
                try
                    tell application "Weather" to launch
                    delay 1
                end try
            end if
            if exists process "Weather" then
                tell process "Weather"
                    if exists window 1 then
                        set collected to {}
                        repeat with itemRef in (every static text of window 1)
                            try
                                set end of collected to (value of itemRef as text)
                            end try
                        end repeat
                        set AppleScript's text item delimiters to " | "
                        set resultText to collected as text
                        set AppleScript's text item delimiters to ""
                        return resultText
                    end if
                end tell
            end if
        end tell
        return ""
        """#
        return AppleScriptRunner.run(script, timeout: 5)
    }

    private func parseWeatherText(_ text: String?) -> WeatherSnapshot? {
        guard let text, !text.isEmpty else { return nil }
        let normalized = text.replacingOccurrences(of: "−", with: "-")
        let pattern = #"(-?\d{1,3})\s*°?\s*([CF])?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
        guard let match = regex.firstMatch(in: normalized, range: range), match.numberOfRanges > 1,
              let tempRange = Range(match.range(at: 1), in: normalized) else { return nil }

        let temperature = String(normalized[tempRange]) + "°C"
        let lower = normalized.lowercased()
        let condition: WeatherCondition
        if lower.contains("thunder") || lower.contains("storm") || lower.contains("雷") {
            condition = .thunderstorm
        } else if lower.contains("snow") || lower.contains("雪") {
            condition = .snow
        } else if lower.contains("drizzle") || lower.contains("毛毛雨") {
            condition = .drizzle
        } else if lower.contains("rain") || lower.contains("雨") {
            condition = .rain
        } else if lower.contains("fog") || lower.contains("雾") || lower.contains("mist") {
            condition = .fog
        } else if lower.contains("overcast") || lower.contains("阴") {
            condition = .cloudy
        } else if lower.contains("cloud") || lower.contains("多云") {
            condition = .partlyCloudy
        } else if lower.contains("clear") || lower.contains("sunny") || lower.contains("晴") {
            condition = .clear
        } else {
            condition = .unknown
        }

        return WeatherSnapshot(temperature: temperature, condition: condition, location: "", isLive: true)
    }

    private func readWeatherCache() -> WeatherSnapshot? {
        let home = fileManager.homeDirectoryForCurrentUser
        let candidates = [
            home.appendingPathComponent("Library/Containers/com.apple.weather/Data/Library/Preferences/com.apple.weather.plist"),
            home.appendingPathComponent("Library/Containers/com.apple.weather/Data/Library/Application Support"),
            home.appendingPathComponent("Library/Containers/com.apple.weather/Data/Library/Caches")
        ]

        for candidate in candidates {
            if candidate.pathExtension == "plist", let result = parsePropertyList(at: candidate) {
                return result
            }
            if let enumerator = fileManager.enumerator(at: candidate, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) {
                for case let url as URL in enumerator {
                    guard ["plist", "json"].contains(url.pathExtension.lowercased()) else { continue }
                    if let result = parsePropertyList(at: url) ?? parseTextFile(at: url) {
                        return result
                    }
                }
            }
        }
        return nil
    }

    private func parsePropertyList(at url: URL) -> WeatherSnapshot? {
        guard let data = try? Data(contentsOf: url), data.count < 10_000_000,
              let object = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) else { return nil }
        return parseAny(object)
    }

    private func parseTextFile(at url: URL) -> WeatherSnapshot? {
        guard let text = try? String(contentsOf: url, encoding: .utf8), text.count < 10_000_000 else { return nil }
        return parseWeatherText(text)
    }

    private func parseAny(_ value: Any) -> WeatherSnapshot? {
        if let string = value as? String, let result = parseWeatherText(string) { return result }
        if let dictionary = value as? [String: Any] {
            for child in dictionary.values {
                if let result = parseAny(child) { return result }
            }
        }
        if let array = value as? [Any] {
            for child in array {
                if let result = parseAny(child) { return result }
            }
        }
        return nil
    }
}

private struct RuntimePayload: Decodable {
    var model: String?
    var thinking: String?
    var fastMode: Bool?
    var fast: Bool?
    var reasoningEffort: String?
    var provider: String?
    var balance: String?
    var tokenPercent: Double?
    var tokens: Double?
    var activeSession: String?
    var elapsed: String?
    var contextPercent: Double?
    var contextUsedTokens: Double?
    var contextLimitTokens: Double?
    var agentState: String?
    var sessions: [RuntimeSessionPayload]?

    enum CodingKeys: String, CodingKey {
        case model, thinking, fastMode, fast, fast_mode, reasoningEffort, reasoning_effort, provider, balance, balanceValue, balance_value, tokenPercent, tokens
        case activeSession, elapsed, contextPercent, contextUsedTokens, contextLimitTokens
        case agentState, sessions
    }
    var balanceValue: Double?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        model = try c.decodeIfPresent(String.self, forKey: .model)
        thinking = try c.decodeIfPresent(String.self, forKey: .thinking)
        fastMode = try c.decodeIfPresent(Bool.self, forKey: .fastMode) ?? c.decodeIfPresent(Bool.self, forKey: .fast_mode)
        fast = try c.decodeIfPresent(Bool.self, forKey: .fast)
        reasoningEffort = try c.decodeIfPresent(String.self, forKey: .reasoningEffort) ?? c.decodeIfPresent(String.self, forKey: .reasoning_effort)
        provider = try c.decodeIfPresent(String.self, forKey: .provider)
        balance = try c.decodeIfPresent(String.self, forKey: .balance)
        balanceValue = try c.decodeIfPresent(Double.self, forKey: .balanceValue) ?? c.decodeIfPresent(Double.self, forKey: .balance_value)
        tokenPercent = try c.decodeIfPresent(Double.self, forKey: .tokenPercent)
        tokens = try c.decodeIfPresent(Double.self, forKey: .tokens)
        activeSession = try c.decodeIfPresent(String.self, forKey: .activeSession)
        elapsed = try c.decodeIfPresent(String.self, forKey: .elapsed)
        contextPercent = try c.decodeIfPresent(Double.self, forKey: .contextPercent)
        contextUsedTokens = try c.decodeIfPresent(Double.self, forKey: .contextUsedTokens)
        contextLimitTokens = try c.decodeIfPresent(Double.self, forKey: .contextLimitTokens)
        agentState = try c.decodeIfPresent(String.self, forKey: .agentState)
        sessions = try c.decodeIfPresent([RuntimeSessionPayload].self, forKey: .sessions)
    }
}

private struct RuntimeSessionPayload: Decodable {
    var title: String?
    var progress: Double?
    var status: String?
    var updatedAt: String?
}

private struct CodexTaskIndexEntry: Decodable {
    var id: String?
    var threadName: String?
    var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case threadName = "thread_name"
        case updatedAt = "updated_at"
    }
}

private struct CodexSnapshot {
    var sessions: [SessionInfo]
    var agentState: AgentState
    var contextPercent: Int
    var model: String?
    var thinking: String?
    var fastMode: Bool?
    var provider: String?
    var hasContextData: Bool
}

final class RuntimeStatusService {
    private let queue = DispatchQueue(label: "hermes-dashboard.runtime", qos: .utility)

    func fetch(source: RuntimeSource, provider: ProviderSettings, completion: @escaping (RuntimeStatus) -> Void) {
        queue.async {
            let status = self.read(source: source, provider: provider) ?? RuntimeStatus.demo(source: source)
            DispatchQueue.main.async { completion(status) }
        }
    }

    private func read(source: RuntimeSource, provider: ProviderSettings) -> RuntimeStatus? {
        if source == .hermes, let hermesSnapshot = readHermesSnapshot() {
            return mapHermes(hermesSnapshot, provider: provider)
        }
        let codexSnapshot = source == .codex ? readCodexSnapshot() : nil
        for url in candidateURLs(for: source) {
            guard let data = try? Data(contentsOf: url), let payload = try? JSONDecoder().decode(RuntimePayload.self, from: data) else { continue }
            return map(payload, source: source, provider: provider, codexSnapshot: codexSnapshot)
        }
        if source == .codex, let codexSnapshot {
            var status = RuntimeStatus.demo(source: source)
            status.activeSession = codexSnapshot.sessions.first?.title ?? status.activeSession
            status.contextPercent = codexSnapshot.contextPercent
            status.tokenPercent = codexSnapshot.contextPercent
            status.agentState = codexSnapshot.agentState
            status.sessions = codexSnapshot.sessions
            if let model = codexSnapshot.model { status.model = model }
            if let thinking = codexSnapshot.thinking { status.thinking = thinking.uppercased() }
            if let fastMode = codexSnapshot.fastMode { status.fastMode = fastMode }
            if let sourceProvider = codexSnapshot.provider { status.provider = sourceProvider.uppercased() }
            if !provider.name.isEmpty { status.provider = provider.name.uppercased() }
            status.balance = provider.lastBalance
            status.balanceValue = provider.lastBalanceValue
            status.hasModelData = codexSnapshot.model?.isEmpty == false
            status.hasContextData = codexSnapshot.hasContextData
            status.isLive = true
            return status
        }
        return nil
    }

    private func candidateURLs(for source: RuntimeSource) -> [URL] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let envKey = source == .codex ? "CODEX_DASHBOARD_STATUS_PATH" : "HERMES_DASHBOARD_STATUS_PATH"
        var paths: [URL] = []
        if let envPath = ProcessInfo.processInfo.environment[envKey], !envPath.isEmpty {
            paths.append(URL(fileURLWithPath: (envPath as NSString).expandingTildeInPath))
        }
        let appFolder = source == .codex ? "Codex" : "HermesAgent"
        paths.append(contentsOf: [
            home.appendingPathComponent("Library/Application Support/\(appFolder)/status.json"),
            home.appendingPathComponent("Library/Application Support/\(appFolder)/runtime.json"),
            home.appendingPathComponent("Library/Application Support/Hermes Dashboard/\(source.rawValue).json"),
            home.appendingPathComponent("Documents/\(appFolder)/status.json"),
            home.appendingPathComponent(".\(source.rawValue)/status.json")
        ])
        return paths
    }

private struct HermesSnapshot {
    var sessions: [SessionInfo]
    var activityLog: [AgentActivityEvent]
    var agentState: AgentState
    var model: String
    var thinking: String
    var fastMode: Bool
    var provider: String
    var contextPercent: Int
    var hasContextData: Bool
}

    private func mapHermes(_ snapshot: HermesSnapshot, provider: ProviderSettings) -> RuntimeStatus {
        RuntimeStatus(
            source: .hermes,
            model: snapshot.model,
            thinking: snapshot.thinking.uppercased(),
            fastMode: snapshot.fastMode,
            provider: (provider.name.isEmpty ? snapshot.provider : provider.name).uppercased(),
            balance: provider.lastBalance.isEmpty ? RuntimeStatus.demo(source: .hermes).balance : provider.lastBalance,
            balanceValue: provider.lastBalanceValue,
            tokenPercent: snapshot.contextPercent,
            activeSession: snapshot.sessions.first?.title ?? "",
            elapsed: "",
            contextPercent: snapshot.contextPercent,
            agentState: snapshot.agentState,
            sessions: snapshot.sessions,
            activityLog: snapshot.activityLog,
            isLive: true,
            hasModelData: !snapshot.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            hasContextData: snapshot.hasContextData
        )
    }

    private func hermesHomeURL() -> URL {
        if let env = ProcessInfo.processInfo.environment["HERMES_HOME"], !env.isEmpty {
            return URL(fileURLWithPath: (env as NSString).expandingTildeInPath)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".hermes")
    }

    private func readHermesSnapshot() -> HermesSnapshot? {
        let dbPath = hermesHomeURL().appendingPathComponent("state.db").path
        guard FileManager.default.fileExists(atPath: dbPath) else { return nil }
        let sessionSQL = """
        SELECT id,
               COALESCE(NULLIF(title, ''), NULLIF(display_name, ''), id) AS title,
               model,
               model_config,
               last_activity_at,
               last_activity_description,
               input_tokens,
               ended_at,
               billing_provider
        FROM sessions
        WHERE IFNULL(archived, 0) = 0
          AND IFNULL(hidden, 0) = 0
        ORDER BY COALESCE(last_activity_at, started_at) DESC
        LIMIT 5;
        """
        let rows = readSQLiteRows(path: dbPath, query: sessionSQL)
        guard !rows.isEmpty else { return nil }

        let config = readHermesConfig()
        let sessions: [SessionInfo] = rows.compactMap { row in
            guard let rawTitle = row["title"] as? String else { return nil }
            let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return nil }
            let ended = row["ended_at"] != nil && !(row["ended_at"] is NSNull)
            let activity = (row["last_activity_description"] as? String ?? "").lowercased()
            let status: String
            if activity.contains("error") || activity.contains("fail") {
                status = "ERROR"
            } else if !ended && hermesLooksActive(activity: activity, lastActivity: (row["last_activity_at"] as? NSNumber)?.doubleValue) {
                status = "RUNNING"
            } else {
                status = "DONE"
            }
            let used = (row["input_tokens"] as? NSNumber)?.doubleValue ?? 0
            let limit = hermesContextLimit(modelConfig: row["model_config"] as? String, fallback: config.contextLength)
            let percent = limit > 0 ? clamp(Int((used / limit * 100).rounded()), min: 0, max: 100) : 0
            return SessionInfo(
                title: title,
                progress: percent,
                status: status,
                updatedAt: formatEpoch((row["last_activity_at"] as? NSNumber)?.doubleValue),
                contextPercent: percent
            )
        }
        guard !sessions.isEmpty else { return nil }

        let current = rows[0]
        let modelConfig = current["model_config"] as? String ?? ""
        let sessionModel = (current["model"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let configModel = jsonString(modelConfig, key: "model") ?? ""
        let model = [sessionModel, configModel, config.model].first { !$0.isEmpty } ?? "HERMES"
        let thinking = jsonNestedString(modelConfig, path: ["reasoning_config", "effort"])
            ?? config.thinking
            ?? "MEDIUM"
        let fastMode = model.lowercased().contains("fast")
        let billing = (current["billing_provider"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let providerName = [config.provider, billing].first { !$0.isEmpty } ?? "HERMES"
        let activity = (current["last_activity_description"] as? String ?? "").lowercased()
        let ended = current["ended_at"] != nil && !(current["ended_at"] is NSNull)
        let agentState: AgentState
        if activity.contains("error") || activity.contains("fail") {
            agentState = .error
        } else if activity.contains("think") || activity.contains("reason") {
            agentState = .thinking
        } else if activity.contains("stream") || activity.contains("generat") || activity.contains("receiv") || activity.contains("output") {
            agentState = .outputting
        } else if !ended && hermesLooksActive(activity: activity, lastActivity: (current["last_activity_at"] as? NSNumber)?.doubleValue) {
            agentState = .outputting
        } else {
            agentState = .done
        }

        let sessionID = current["id"] as? String ?? ""
        let activityLog = readHermesActivity(dbPath: dbPath, sessionID: sessionID, fallback: current["last_activity_description"] as? String)
        let used = (current["input_tokens"] as? NSNumber)?.doubleValue ?? 0
        let limit = hermesContextLimit(modelConfig: modelConfig, fallback: config.contextLength)
        let contextPercent = limit > 0 ? clamp(Int((used / limit * 100).rounded()), min: 0, max: 100) : sessions[0].contextPercent
        return HermesSnapshot(
            sessions: sessions,
            activityLog: activityLog,
            agentState: agentState,
            model: model,
            thinking: thinking,
            fastMode: fastMode,
            provider: providerName,
            contextPercent: contextPercent,
            hasContextData: used > 0 || limit > 0
        )
    }

    private func hermesLooksActive(activity: String, lastActivity: Double?) -> Bool {
        let liveHints = ["stream", "tool", "call", "execut", "run", "generat", "receiv", "think", "write", "read"]
        if liveHints.contains(where: { activity.contains($0) }) { return true }
        guard let lastActivity, lastActivity > 0 else { return false }
        return Date().timeIntervalSince1970 - lastActivity < 45
    }

    private func hermesContextLimit(modelConfig: String?, fallback: Double) -> Double {
        if let modelConfig,
           let value = jsonNumber(modelConfig, key: "context_length") ?? jsonNumber(modelConfig, key: "contextLength"),
           value > 0 {
            return value
        }
        return fallback > 0 ? fallback : 256_000
    }

    private func readHermesActivity(dbPath: String, sessionID: String, fallback: String?) -> [AgentActivityEvent] {
        guard !sessionID.isEmpty else { return fallbackEvents(fallback) }
        let sql = """
        SELECT role,
               tool_name,
               substr(COALESCE(reasoning, reasoning_content, ''), 1, 280) AS reasoning,
               substr(COALESCE(content, ''), 1, 480) AS content,
               substr(COALESCE(tool_calls, ''), 1, 900) AS tool_calls
        FROM messages
        WHERE session_id = '\(sessionID.replacingOccurrences(of: "'", with: "''"))'
          AND IFNULL(active, 1) = 1
        ORDER BY timestamp DESC, id DESC
        LIMIT 40;
        """
        let rows = readSQLiteRows(path: dbPath, query: sql)
        var packets: [[AgentActivityEvent]] = []
        var finalizedReply: AgentActivityEvent?
        var packed = 0
        for row in rows {
            var packet: [AgentActivityEvent] = []
            let role = (row["role"] as? String ?? "").lowercased()
            if role == "tool" {
                let name = (row["tool_name"] as? String ?? "tool").trimmingCharacters(in: .whitespacesAndNewlines)
                let snippet = compactActivityText(row["content"] as? String)
                let failed = snippet.lowercased().contains("error") || snippet.lowercased().contains("exit_code\": 1") || snippet.contains("exit_code\":1")
                let prefix = failed ? "ERR" : "OK"
                let text = snippet.isEmpty ? "\(prefix)  \(name)" : "\(prefix)  \(name)  \(snippet)"
                packet.append(AgentActivityEvent(kind: .result, text: text))
            } else if role == "assistant" {
                let toolNames = functionNames(from: row["tool_calls"] as? String)
                let think = compactActivityText(row["reasoning"] as? String)
                let spoken = compactActivityText(row["content"] as? String, limit: 280)
                if !spoken.isEmpty && toolNames.isEmpty {
                    finalizedReply = AgentActivityEvent(kind: .reply, text: spoken)
                    break
                }
                if !think.isEmpty {
                    packet.append(AgentActivityEvent(kind: .think, text: "THINK  \(think)"))
                }
                if !toolNames.isEmpty {
                    packet.append(AgentActivityEvent(kind: .tool, text: "TOOL  \(toolNames.joined(separator: "  "))"))
                }
            }
            if !packet.isEmpty {
                packets.append(packet)
                packed += packet.count
            }
            if packed >= 16 { break }
        }
        if let finalizedReply {
            return [finalizedReply]
        }
        packets.reverse()
        let events = packets.flatMap { $0 }
        if events.isEmpty { return fallbackEvents(fallback) }
        return events
    }

    private func fallbackEvents(_ fallback: String?) -> [AgentActivityEvent] {
        let text = compactActivityText(fallback)
        if text.isEmpty { return [] }
        return [AgentActivityEvent(kind: .status, text: text)]
    }

    private func compactActivityText(_ raw: String?, limit: Int = 90) -> String {
        guard let raw else { return "" }
        var text = raw.replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
        while text.contains("  ") {
            text = text.replacingOccurrences(of: "  ", with: " ")
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("{") || text.hasPrefix("[") {
            if let name = functionNames(from: text).first { return name }
            let clipped = text.replacingOccurrences(of: "\"", with: "")
            return String(clipped.prefix(72))
        }
        if text.count > limit {
            return String(text.prefix(max(limit - 3, 1))) + "..."
        }
        return text
    }

    private func functionNames(from json: String?) -> [String] {
        guard let json, json.contains("function") || json.contains("\"name\"") else { return [] }
        var names: [String] = []
        var search = json[json.startIndex...]
        while let range = search.range(of: "\"name\"") {
            let after = search[range.upperBound...]
            if let colon = after.firstIndex(of: ":") {
                let rest = after[after.index(after: colon)...].trimmingCharacters(in: .whitespacesAndNewlines)
                if rest.hasPrefix("\""), let end = rest.dropFirst().firstIndex(of: "\"") {
                    let name = String(rest[rest.index(after: rest.startIndex)..<end])
                    if !name.isEmpty && !name.hasPrefix("call-") && !names.contains(name) {
                        names.append(name)
                    }
                }
            }
            search = search[range.upperBound...]
        }
        return names
    }

    private func readHermesConfig() -> (model: String, provider: String, thinking: String?, contextLength: Double) {
        let url = hermesHomeURL().appendingPathComponent("config.yaml")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            return ("", "", nil, 256_000)
        }
        return (
            yamlValue("default", in: text) ?? "",
            yamlValue("provider", in: text) ?? "",
            yamlValue("effort", in: text),
            Double(yamlValue("context_length", in: text) ?? "") ?? 256_000
        )
    }

    private func yamlValue(_ key: String, in text: String) -> String? {
        for line in text.split(whereSeparator: \.isNewline) {
            let raw = line.trimmingCharacters(in: .whitespaces)
            guard !raw.hasPrefix("#"), raw.hasPrefix("\(key):") else { continue }
            let value = raw.dropFirst(key.count + 1).trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            if !value.isEmpty { return value }
        }
        return nil
    }

    private func jsonString(_ json: String, key: String) -> String? {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let value = object[key] as? String,
              !value.isEmpty else { return nil }
        return value
    }

    private func jsonNumber(_ json: String, key: String) -> Double? {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let number = object[key] as? NSNumber { return number.doubleValue }
        if let string = object[key] as? String { return Double(string) }
        return nil
    }

    private func jsonNestedString(_ json: String, path: [String]) -> String? {
        guard let data = json.data(using: .utf8),
              var current: Any = try? JSONSerialization.jsonObject(with: data) else { return nil }
        for key in path {
            guard let dictionary = current as? [String: Any], let next = dictionary[key] else { return nil }
            current = next
        }
        if let string = current as? String, !string.isEmpty { return string }
        return nil
    }

    private func readCodexSnapshot() -> CodexSnapshot? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let catalogPath = home.appendingPathComponent(".codex/sqlite/codex-dev.db").path
        let historyPath = home.appendingPathComponent(".codex/thread_history_1.sqlite").path
        let statePath = home.appendingPathComponent(".codex/state_5.sqlite").path

        let catalogRows = readSQLiteRows(path: catalogPath, query: "SELECT thread_id, display_title, source_updated_at, source_recency_at FROM local_thread_catalog WHERE missing_candidate = 0 ORDER BY source_recency_at DESC LIMIT 5;")
        if !catalogRows.isEmpty {
            let stateRows = readSQLiteRows(path: statePath, query: "SELECT id, rollout_path, tokens_used, model, reasoning_effort, model_provider FROM threads WHERE archived = 0;")
            let states = Dictionary(uniqueKeysWithValues: stateRows.compactMap { row -> (String, [String: Any])? in
                guard let id = row["id"] as? String else { return nil }
                return (id, row)
            })
            let turnRows = readSQLiteRows(path: historyPath, query: "SELECT thread_id, status, started_at, completed_at FROM thread_turns ORDER BY started_at DESC;")
            var latestTurns: [String: [String: Any]] = [:]
            for row in turnRows {
                guard let threadID = row["thread_id"] as? String else { continue }
                let started = (row["started_at"] as? NSNumber)?.doubleValue ?? 0
                let previous = (latestTurns[threadID]?["started_at"] as? NSNumber)?.doubleValue ?? -1
                if started > previous { latestTurns[threadID] = row }
            }

            let sessions = catalogRows.compactMap { row -> SessionInfo? in
                guard let threadID = row["thread_id"] as? String,
                      let rawTitle = row["display_title"] as? String else { return nil }
                let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !title.isEmpty else { return nil }
                let turn = latestTurns[threadID]
                let status = normalizedSessionStatus(turn?["status"] as? String)
                let state = states[threadID]
                let usage = (state?["rollout_path"] as? String).flatMap(readTokenUsage)
                let fallbackTokens = (state?["tokens_used"] as? NSNumber)?.doubleValue ?? 0
                let contextPercent = usage?.percent ?? clamp(Int((fallbackTokens / 258400.0 * 100).rounded()), min: 0, max: 100)
                let updatedAt = formatEpoch((row["source_updated_at"] as? NSNumber)?.doubleValue)
                return SessionInfo(title: title, progress: contextPercent, status: status, updatedAt: updatedAt, contextPercent: contextPercent)
            }
            if !sessions.isEmpty {
                let agentState: AgentState
                if sessions.contains(where: { $0.status == "RUNNING" }) {
                    agentState = .working
                } else if sessions.first?.status == "ERROR" {
                    agentState = .error
                } else {
                    agentState = .idle
                }
                let currentThreadID = catalogRows.first?["thread_id"] as? String
                let currentState = currentThreadID.flatMap { states[$0] }
                let metadata = readCodexRuntimeMetadata(state: currentState)
                return CodexSnapshot(
                    sessions: sessions,
                    agentState: agentState,
                    contextPercent: sessions[0].contextPercent,
                    model: metadata.model,
                    thinking: metadata.thinking,
                    fastMode: metadata.fastMode,
                    provider: metadata.provider,
                    hasContextData: sessions.contains { $0.contextPercent > 0 }
                )
            }
        }

        let legacySessions = readLegacyCodexTasks()
        guard !legacySessions.isEmpty else { return nil }
        let metadata = readCodexRuntimeMetadata(state: nil)
        return CodexSnapshot(sessions: legacySessions, agentState: .idle, contextPercent: legacySessions[0].contextPercent, model: metadata.model, thinking: metadata.thinking, fastMode: metadata.fastMode, provider: metadata.provider, hasContextData: legacySessions.contains { $0.contextPercent > 0 })
    }

    private func readCodexRuntimeMetadata(state: [String: Any]?) -> (model: String?, thinking: String?, fastMode: Bool?, provider: String?) {
        let configURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/config.toml")
        let config = (try? String(contentsOf: configURL, encoding: .utf8)) ?? ""
        let configuredModel = state == nil ? valueAfterTOMLKey("model", in: config) : state?["model"] as? String
        let configuredThinking = state == nil ? valueAfterTOMLKey("model_reasoning_effort", in: config) : state?["reasoning_effort"] as? String
        let configuredProvider = state == nil ? valueAfterTOMLKey("model_provider", in: config) : state?["model_provider"] as? String
        let rolloutFast = (state?["rollout_path"] as? String).flatMap(readFastFlagFromRollout)
        let fast = (state?["fast_mode"] as? NSNumber)?.boolValue
            ?? (state?["fast"] as? NSNumber)?.boolValue
            ?? rolloutFast
            ?? valueAfterTOMLKey("fast_mode", in: config).map { ["true", "1", "on", "yes"].contains($0.lowercased()) }
            ?? ((valueAfterTOMLKey("service_tier", in: config)?.lowercased() == "priority") ? true : false)
        return (configuredModel, configuredThinking, fast, configuredProvider)
    }

    private func readFastFlagFromRollout(_ path: String) -> Bool? {
        guard let handle = try? FileHandle(forReadingFrom: URL(fileURLWithPath: path)) else { return nil }
        defer { try? handle.close() }
        let end = (try? handle.seekToEnd()) ?? 0
        handle.seek(toFileOffset: end > 262_144 ? end - 262_144 : 0)
        guard let data = try? handle.readToEnd(), let text = String(data: data, encoding: .utf8) else { return nil }
        for line in text.split(whereSeparator: \.isNewline).reversed() {
            let lower = line.lowercased()
            if lower.contains("\"fast_mode\":true") || lower.contains("\"fast\":true") { return true }
            if lower.contains("\"fast_mode\":false") || lower.contains("\"fast\":false") { return false }
        }
        return nil
    }

    private func valueAfterTOMLKey(_ key: String, in text: String) -> String? {
        for line in text.split(whereSeparator: \.isNewline) {
            let raw = line.trimmingCharacters(in: .whitespaces)
            guard raw.hasPrefix("\(key)"), let equals = raw.firstIndex(of: "=") else { continue }
            return raw[raw.index(after: equals)...].trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        }
        return nil
    }

    private func readLegacyCodexTasks() -> [SessionInfo] {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/session_index.jsonl")
        guard let data = try? Data(contentsOf: url), data.count < 20_000_000,
              let text = String(data: data, encoding: .utf8) else { return [] }

        let decoder = JSONDecoder()
        let entries = text.split(whereSeparator: \.isNewline).compactMap { line -> CodexTaskIndexEntry? in
            guard let lineData = line.data(using: .utf8) else { return nil }
            return try? decoder.decode(CodexTaskIndexEntry.self, from: lineData)
        }
        var seen = Set<String>()
        let sorted = entries.sorted { lhs, rhs in
            (lhs.updatedAt ?? "") > (rhs.updatedAt ?? "")
        }
        return sorted.compactMap { entry in
            let title = entry.threadName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !title.isEmpty else { return nil }
            let identity = entry.id ?? title
            guard seen.insert(identity).inserted else { return nil }
            return SessionInfo(
                title: title,
                progress: 0,
                status: "DONE",
                updatedAt: formatTaskDate(entry.updatedAt),
                contextPercent: 0
            )
        }.prefix(5).map { $0 }
    }

    private func formatTaskDate(_ value: String?) -> String {
        guard let value else { return "" }
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let standardFormatter = ISO8601DateFormatter()
        guard let date = fractionalFormatter.date(from: value) ?? standardFormatter.date(from: value) else {
            return ""
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MM/dd HH:mm"
        return formatter.string(from: date)
    }

    private func formatEpoch(_ value: Double?) -> String {
        guard let value, value > 0 else { return "" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MM/dd HH:mm"
        return formatter.string(from: Date(timeIntervalSince1970: value))
    }

    private func readSQLiteRows(path: String, query: String) -> [[String: Any]] {
        guard FileManager.default.fileExists(atPath: path),
              let output = ProcessRunner.run(executable: "/usr/bin/sqlite3", arguments: ["-readonly", "-json", path, query], timeout: 8),
              let data = output.data(using: .utf8),
              let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return rows
    }

    private func readTokenUsage(path: String) -> (percent: Int, used: Double, limit: Double)? {
        guard FileManager.default.fileExists(atPath: path),
              let handle = try? FileHandle(forReadingFrom: URL(fileURLWithPath: path)) else { return nil }
        defer { try? handle.close() }
        let end = (try? handle.seekToEnd()) ?? 0
        let offset = end > 524_288 ? end - 524_288 : 0
        handle.seek(toFileOffset: offset)
        guard let data = try? handle.readToEnd(), let text = String(data: data, encoding: .utf8) else { return nil }
        for line in text.split(whereSeparator: \.isNewline).reversed() {
            guard line.contains("\"token_count\""),
                  let lineData = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let payload = object["payload"] as? [String: Any],
                  let info = payload["info"] as? [String: Any],
                  let usage = (info["last_token_usage"] as? [String: Any]) ?? (info["total_token_usage"] as? [String: Any]),
                  let usedTokens = (usage["total_tokens"] as? NSNumber)?.doubleValue,
                  let contextLimit = (info["model_context_window"] as? NSNumber)?.doubleValue,
                  contextLimit > 0 else { continue }
            let percent = (usedTokens / contextLimit) * 100.0
            return (clamp(Int(percent.rounded()), min: 0, max: 100), usedTokens, contextLimit)
        }
        return nil
    }

    private func normalizedSessionStatus(_ value: String?) -> String {
        switch value?.lowercased() {
        case "inprogress", "in_progress", "running", "working", "executing": return "RUNNING"
        case "failed", "error", "errored", "interrupted": return "ERROR"
        case "completed", "complete", "done", "success": return "DONE"
        default: return "DONE"
        }
    }

    private func map(_ payload: RuntimePayload, source: RuntimeSource, provider: ProviderSettings, codexSnapshot: CodexSnapshot?) -> RuntimeStatus {
        let demo = RuntimeStatus.demo(source: source)
        let calculatedContext: Int
        if let snapshot = codexSnapshot {
            calculatedContext = snapshot.contextPercent
        } else if let used = payload.contextUsedTokens, let limit = payload.contextLimitTokens, limit > 0 {
            calculatedContext = Int((used / limit * 100).rounded())
        } else {
            calculatedContext = Int((payload.contextPercent ?? Double(demo.contextPercent)).rounded())
        }
        let payloadSessions = payload.sessions?.compactMap { item -> SessionInfo? in
            guard let title = item.title, !title.isEmpty else { return nil }
            return SessionInfo(
                title: title,
                progress: clamp(Int((item.progress ?? 0).rounded()), min: 0, max: 100),
                status: normalizedSessionStatus(item.status),
                updatedAt: item.updatedAt ?? "",
                contextPercent: clamp(Int((item.progress ?? 0).rounded()), min: 0, max: 100)
            )
        } ?? demo.sessions
        let sessionValues = codexSnapshot?.sessions ?? payloadSessions
        let currentSession = codexSnapshot?.sessions.first?.title ?? payload.activeSession ?? demo.activeSession
        let agentState = codexSnapshot?.agentState ?? AgentState(rawValue: payload.agentState ?? demo.agentState.rawValue)

        return RuntimeStatus(
            source: source,
            model: codexSnapshot?.model ?? payload.model ?? demo.model,
            thinking: (codexSnapshot?.thinking ?? payload.thinking ?? payload.reasoningEffort ?? demo.thinking).uppercased(),
            fastMode: codexSnapshot?.fastMode ?? payload.fastMode ?? payload.fast ?? demo.fastMode,
            provider: (provider.name.isEmpty ? (codexSnapshot?.provider ?? payload.provider ?? demo.provider) : provider.name).uppercased(),
            balance: provider.lastBalance.isEmpty ? (payload.balance ?? demo.balance) : provider.lastBalance,
            balanceValue: provider.lastBalanceValue ?? payload.balanceValue,
            tokenPercent: codexSnapshot?.contextPercent ?? clamp(Int(((payload.tokenPercent ?? payload.tokens ?? Double(demo.tokenPercent))).rounded()), min: 0, max: 100),
            activeSession: currentSession,
            elapsed: payload.elapsed ?? demo.elapsed,
            contextPercent: clamp(calculatedContext, min: 0, max: 100),
            agentState: agentState,
            sessions: Array(sessionValues.prefix(5)),
            activityLog: [],
            isLive: true,
            hasModelData: !(codexSnapshot?.model ?? payload.model ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            hasContextData: codexSnapshot?.hasContextData ?? (payload.contextUsedTokens != nil || payload.contextPercent != nil || payload.tokenPercent != nil || payload.tokens != nil)
        )
    }

    private func clamp(_ value: Int, min: Int, max: Int) -> Int {
        Swift.min(Swift.max(value, min), max)
    }
}

struct BalanceSnapshot {
    var display: String
    var numeric: Double?
}

final class ProviderBalanceService {
    private let queue = DispatchQueue(label: "hermes-dashboard.balance", qos: .utility)

    func fetch(settings: ProviderSettings, completion: @escaping (BalanceSnapshot?) -> Void) {
        guard !settings.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !settings.balancePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let apiKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"], !apiKey.isEmpty else {
            completion(nil)
            return
        }
        queue.async {
            let result = self.read(settings: settings, apiKey: apiKey)
            DispatchQueue.main.async { completion(result) }
        }
    }

    private func read(settings: ProviderSettings, apiKey: String) -> BalanceSnapshot? {
        let base = settings.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let path = settings.balancePath.hasPrefix("/") ? settings.balancePath : "/\(settings.balancePath)"
        guard let url = URL(string: base + path) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 8
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let semaphore = DispatchSemaphore(value: 0)
        var result: BalanceSnapshot?
        let task = URLSession.shared.dataTask(with: request) { data, response, _ in
            defer { semaphore.signal() }
            guard let data, (response as? HTTPURLResponse)?.statusCode ?? 0 >= 200,
                  (response as? HTTPURLResponse)?.statusCode ?? 0 < 300,
                  let object = try? JSONSerialization.jsonObject(with: data) else { return }
            let value = self.value(at: settings.balanceJSONPath, in: object) ?? object
            result = self.snapshot(for: value)
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + 10)
        return result
    }

    private func value(at path: String, in object: Any) -> Any? {
        var current: Any = object
        for component in path.split(separator: ".").map(String.init) where !component.isEmpty {
            if let dictionary = current as? [String: Any] {
                guard let next = dictionary[component] else { return nil }
                current = next
            } else if let array = current as? [Any], let index = Int(component), array.indices.contains(index) {
                current = array[index]
            } else { return nil }
        }
        return current
    }

    private func snapshot(for value: Any) -> BalanceSnapshot? {
        if let number = value as? NSNumber {
            return BalanceSnapshot(display: format(number.doubleValue), numeric: number.doubleValue)
        }
        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            let numeric = numericValue(in: trimmed)
            guard !trimmed.isEmpty else { return nil }
            let display: String
            if trimmed.contains("$") {
                display = trimmed
            } else if let numeric {
                display = format(numeric)
            } else {
                display = "$\(trimmed)"
            }
            return BalanceSnapshot(display: display, numeric: numeric)
        }
        return nil
    }

    private func numericValue(in string: String) -> Double? {
        let pattern = #"[-+]?\d+(?:\.\d+)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: string, range: NSRange(string.startIndex..<string.endIndex, in: string)),
              let range = Range(match.range, in: string) else { return nil }
        return Double(string[range])
    }

    private func format(_ value: Double) -> String {
        String(format: "$%.2f", value)
    }
}

final class GIFAnimator {
    private(set) var frames: [CGImage] = []
    private(set) var durations: [Double] = []
    private var totalDuration: Double = 0

    init?(url: URL) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let count = CGImageSourceGetCount(source)
        guard count > 0 else { return nil }

        for index in 0..<count {
            guard let image = CGImageSourceCreateImageAtIndex(source, index, nil) else { continue }
            frames.append(image)
            let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
            let gifProperties = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            let unclamped = gifProperties?[kCGImagePropertyGIFUnclampedDelayTime] as? Double
            let clamped = gifProperties?[kCGImagePropertyGIFDelayTime] as? Double
            let duration = max(unclamped ?? clamped ?? 0.1, 0.04)
            durations.append(duration)
            totalDuration += duration
        }
        guard !frames.isEmpty else { return nil }
    }

    func frame(at time: TimeInterval) -> CGImage? {
        guard !frames.isEmpty else { return nil }
        guard frames.count > 1, totalDuration > 0 else { return frames[0] }
        var remaining = time.truncatingRemainder(dividingBy: totalDuration)
        for (index, duration) in durations.enumerated() {
            if remaining <= duration { return frames[index] }
            remaining -= duration
        }
        return frames.last
    }
}
