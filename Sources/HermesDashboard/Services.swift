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

    func fetch(completion: @escaping (WeatherSnapshot) -> Void) {
        queue.async {
            if let cached = self.readWeatherCache() {
                DispatchQueue.main.async { completion(cached) }
                return
            }

            let bridgeOutput = self.readWeatherAppAccessibilityTree()
            let parsed = self.parseWeatherText(bridgeOutput) ?? .demo
            DispatchQueue.main.async { completion(parsed) }
        }
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
        if lower.contains("snow") || lower.contains("雪") {
            condition = .snow
        } else if lower.contains("rain") || lower.contains("雨") || lower.contains("drizzle") {
            condition = .rain
        } else if lower.contains("cloud") || lower.contains("overcast") || lower.contains("多云") {
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
        case model, thinking, fastMode, provider, balance, tokenPercent, tokens
        case activeSession, elapsed, contextPercent, contextUsedTokens, contextLimitTokens
        case agentState, sessions
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

final class RuntimeStatusService {
    private let queue = DispatchQueue(label: "hermes-dashboard.runtime", qos: .utility)

    func fetch(source: RuntimeSource, completion: @escaping (RuntimeStatus) -> Void) {
        queue.async {
            let status = self.read(source: source) ?? RuntimeStatus.demo(source: source)
            DispatchQueue.main.async { completion(status) }
        }
    }

    private func read(source: RuntimeSource) -> RuntimeStatus? {
        let codexTasks = source == .codex ? readCodexTasks() : []
        for url in candidateURLs(for: source) {
            guard let data = try? Data(contentsOf: url), let payload = try? JSONDecoder().decode(RuntimePayload.self, from: data) else { continue }
            return map(payload, source: source, codexTasks: codexTasks)
        }
        if source == .codex, !codexTasks.isEmpty {
            var status = RuntimeStatus.demo(source: source)
            status.activeSession = codexTasks[0].title
            status.sessions = codexTasks
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

    private func readCodexTasks() -> [SessionInfo] {
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
                status: "",
                updatedAt: formatTaskDate(entry.updatedAt)
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

    private func map(_ payload: RuntimePayload, source: RuntimeSource, codexTasks: [SessionInfo]) -> RuntimeStatus {
        let demo = RuntimeStatus.demo(source: source)
        let calculatedContext: Int
        if let used = payload.contextUsedTokens, let limit = payload.contextLimitTokens, limit > 0 {
            calculatedContext = Int((used / limit * 100).rounded())
        } else {
            calculatedContext = Int((payload.contextPercent ?? Double(demo.contextPercent)).rounded())
        }
        let payloadSessions = payload.sessions?.compactMap { item -> SessionInfo? in
            guard let title = item.title, !title.isEmpty else { return nil }
            return SessionInfo(
                title: title,
                progress: clamp(Int((item.progress ?? 0).rounded()), min: 0, max: 100),
                status: item.status ?? "",
                updatedAt: item.updatedAt ?? ""
            )
        } ?? demo.sessions
        let sessionValues = codexTasks.isEmpty ? payloadSessions : codexTasks
        let currentSession = codexTasks.first?.title ?? payload.activeSession ?? demo.activeSession

        return RuntimeStatus(
            source: source,
            model: payload.model ?? demo.model,
            thinking: (payload.thinking ?? demo.thinking).uppercased(),
            fastMode: payload.fastMode ?? demo.fastMode,
            provider: (payload.provider ?? demo.provider).uppercased(),
            balance: payload.balance ?? demo.balance,
            tokenPercent: clamp(Int(((payload.tokenPercent ?? payload.tokens ?? Double(demo.tokenPercent))).rounded()), min: 0, max: 100),
            activeSession: currentSession,
            elapsed: payload.elapsed ?? demo.elapsed,
            contextPercent: clamp(calculatedContext, min: 0, max: 100),
            agentState: AgentState(rawValue: payload.agentState ?? demo.agentState.rawValue),
            sessions: Array(sessionValues.prefix(5)),
            isLive: true
        )
    }

    private func clamp(_ value: Int, min: Int, max: Int) -> Int {
        Swift.min(Swift.max(value, min), max)
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
