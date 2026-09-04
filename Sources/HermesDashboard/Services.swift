import AppKit
import Foundation
import ImageIO

enum PlanUsageServiceError: LocalizedError {
    case executableNotFound(String)
    case launchFailed(String)
    case protocolError(String)
    case notAuthenticated
    case weeklyWindowUnavailable

    var errorDescription: String? {
        switch self {
        case .executableNotFound(let path): return "Codex executable not found: \(path)"
        case .launchFailed(let message): return "Could not start Codex: \(message)"
        case .protocolError(let message): return message
        case .notAuthenticated: return "Authorize with ChatGPT to read plan usage"
        case .weeklyWindowUnavailable: return "Weekly allowance is unavailable for this account"
        }
    }
}

private final class CodexAppServerClient {
    typealias JSON = [String: Any]
    private let queue = DispatchQueue(label: "com.hermes.dashboard.codex-app-server")
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var buffer = Data()
    private var nextID = 1
    private var callbacks: [Int: (Result<JSON, Error>) -> Void] = [:]
    private var didStop = false
    var onNotification: ((String, JSON) -> Void)?

    func start(executable: String, completion: @escaping (Result<Void, Error>) -> Void) {
        queue.async {
            let resolved = Self.resolveExecutable(executable)
            guard FileManager.default.isExecutableFile(atPath: resolved) else {
                DispatchQueue.main.async { completion(.failure(PlanUsageServiceError.executableNotFound(executable))) }
                return
            }
            let process = Process()
            let stdin = Pipe()
            let stdout = Pipe()
            process.executableURL = URL(fileURLWithPath: resolved)
            process.arguments = ["app-server", "--stdio"]
            process.standardInput = stdin
            process.standardOutput = stdout
            process.standardError = FileHandle.nullDevice
            self.process = process
            self.input = stdin.fileHandleForWriting
            self.output = stdout.fileHandleForReading
            stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                self?.queue.async { self?.consume(data) }
            }
            process.terminationHandler = { [weak self] process in
                self?.queue.async {
                    guard let self, !self.didStop else { return }
                    self.failPending(PlanUsageServiceError.protocolError("Codex app-server exited (\(process.terminationStatus))"))
                }
            }
            do {
                try process.run()
            } catch {
                self.stopLocked()
                DispatchQueue.main.async { completion(.failure(PlanUsageServiceError.launchFailed(error.localizedDescription))) }
                return
            }
            self.requestLocked(method: "initialize", params: [
                "clientInfo": ["name": "hermes_dashboard", "title": "Hermes Dashboard", "version": "1.0"]
            ]) { result in
                switch result {
                case .success:
                    self.sendLocked(["method": "initialized", "params": [:]])
                    DispatchQueue.main.async { completion(.success(())) }
                case .failure(let error):
                    DispatchQueue.main.async { completion(.failure(error)) }
                }
            }
        }
    }

    func request(method: String, params: JSON? = nil, completion: @escaping (Result<JSON, Error>) -> Void) {
        queue.async { self.requestLocked(method: method, params: params, completion: completion) }
    }

    func stop() { queue.async { self.stopLocked() } }

    private func requestLocked(method: String, params: JSON?, completion: @escaping (Result<JSON, Error>) -> Void) {
        guard !didStop else {
            DispatchQueue.main.async { completion(.failure(PlanUsageServiceError.protocolError("Codex connection is closed"))) }
            return
        }
        let id = nextID
        nextID += 1
        callbacks[id] = completion
        var message: JSON = ["method": method, "id": id]
        if let params { message["params"] = params }
        sendLocked(message)
        queue.asyncAfter(deadline: .now() + 20) { [weak self] in
            guard let self, let callback = self.callbacks.removeValue(forKey: id) else { return }
            DispatchQueue.main.async { callback(.failure(PlanUsageServiceError.protocolError("Codex request timed out: \(method)"))) }
        }
    }

    private func sendLocked(_ message: JSON) {
        guard let data = try? JSONSerialization.data(withJSONObject: message), var line = String(data: data, encoding: .utf8) else { return }
        line.append("\n")
        input?.write(line.data(using: .utf8) ?? Data())
    }

    private func consume(_ data: Data) {
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer.prefix(upTo: newline)
            buffer.removeSubrange(...newline)
            guard !line.isEmpty,
                  let object = try? JSONSerialization.jsonObject(with: Data(line)) as? JSON else { continue }
            handle(object)
        }
    }

    private func handle(_ message: JSON) {
        if let id = (message["id"] as? NSNumber)?.intValue,
           let callback = callbacks.removeValue(forKey: id) {
            if let result = message["result"] as? JSON {
                DispatchQueue.main.async { callback(.success(result)) }
            } else {
                let errorObject = message["error"] as? JSON
                let text = errorObject?["message"] as? String ?? "Invalid response from Codex app-server"
                DispatchQueue.main.async { callback(.failure(PlanUsageServiceError.protocolError(text))) }
            }
            return
        }
        if let method = message["method"] as? String {
            let params = message["params"] as? JSON ?? [:]
            DispatchQueue.main.async { [weak self] in self?.onNotification?(method, params) }
        }
    }

    private func failPending(_ error: Error) {
        let pending = callbacks.values
        callbacks.removeAll()
        for callback in pending { DispatchQueue.main.async { callback(.failure(error)) } }
    }

    private func stopLocked() {
        guard !didStop else { return }
        didStop = true
        output?.readabilityHandler = nil
        try? input?.close()
        try? output?.close()
        if process?.isRunning == true { process?.terminate() }
        process = nil
        input = nil
        output = nil
        callbacks.removeAll()
    }

    private static func resolveExecutable(_ configured: String) -> String {
        let value = (configured.trimmingCharacters(in: .whitespacesAndNewlines) as NSString).expandingTildeInPath
        if value.hasPrefix("/") { return value }
        let name = value.isEmpty ? "codex" : value
        let paths = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
            + ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"]
        return paths.map { URL(fileURLWithPath: $0).appendingPathComponent(name).path }
            .first(where: { FileManager.default.isExecutableFile(atPath: $0) }) ?? value
    }
}

final class CodexPlanUsageService {
    private var refreshClient: CodexAppServerClient?
    private var oauthClient: CodexAppServerClient?

    func fetch(settings: PlanUsageSettings, completion: @escaping (Result<PlanUsageSnapshot, Error>) -> Void) {
        refreshClient?.stop()
        let client = CodexAppServerClient()
        refreshClient = client
        client.start(executable: settings.codexExecutable) { [weak self, weak client] startResult in
            guard let self, let client else { return }
            if case .failure(let error) = startResult {
                self.refreshClient = nil
                completion(.failure(error))
                return
            }
            client.request(method: "account/read", params: ["refreshToken": false]) { accountResult in
                switch accountResult {
                case .failure(let error):
                    client.stop(); self.refreshClient = nil; completion(.failure(error))
                case .success(let response):
                    guard let account = response["account"] as? [String: Any], account["type"] as? String == "chatgpt" else {
                        client.stop(); self.refreshClient = nil; completion(.failure(PlanUsageServiceError.notAuthenticated))
                        return
                    }
                    let planType = account["planType"] as? String
                    let email = account["email"] as? String
                    client.request(method: "account/rateLimits/read") { limitsResult in
                        client.stop(); self.refreshClient = nil
                        switch limitsResult {
                        case .failure(let error): completion(.failure(error))
                        case .success(let limits):
                            completion(Self.snapshot(from: limits, limitID: settings.limitID, planType: planType, email: email))
                        }
                    }
                }
            }
        }
    }

    func startOAuth(executable: String, completion: @escaping (Result<Void, Error>) -> Void) {
        oauthClient?.stop()
        let client = CodexAppServerClient()
        oauthClient = client
        var completed = false
        func finish(_ result: Result<Void, Error>) {
            guard !completed else { return }
            completed = true
            client.stop()
            oauthClient = nil
            completion(result)
        }
        client.onNotification = { method, params in
            guard method == "account/login/completed" else { return }
            if params["success"] as? Bool == true {
                finish(.success(()))
            } else {
                finish(.failure(PlanUsageServiceError.protocolError(params["error"] as? String ?? "Authorization failed")))
            }
        }
        client.start(executable: executable) { result in
            if case .failure(let error) = result { finish(.failure(error)); return }
            client.request(method: "account/login/start", params: [
                "type": "chatgpt", "useHostedLoginSuccessPage": true, "appBrand": "chatgpt"
            ]) { response in
                switch response {
                case .failure(let error): finish(.failure(error))
                case .success(let payload):
                    guard let text = payload["authUrl"] as? String, let url = URL(string: text) else {
                        finish(.failure(PlanUsageServiceError.protocolError("Codex did not return an authorization URL")))
                        return
                    }
                    if !NSWorkspace.shared.open(url) {
                        finish(.failure(PlanUsageServiceError.protocolError("Could not open the authorization page")))
                    }
                }
            }
        }
    }

    private static func snapshot(from response: [String: Any], limitID: String, planType: String?, email: String?) -> Result<PlanUsageSnapshot, Error> {
        let buckets = response["rateLimitsByLimitId"] as? [String: Any]
        let selected = (buckets?[limitID] as? [String: Any]) ?? (response["rateLimits"] as? [String: Any])
        guard let bucket = selected else { return .failure(PlanUsageServiceError.weeklyWindowUnavailable) }
        let windows = [bucket["primary"], bucket["secondary"]].compactMap { $0 as? [String: Any] }
        guard let weekly = windows.first(where: { ($0["windowDurationMins"] as? NSNumber)?.intValue == 10_080 }) else {
            return .failure(PlanUsageServiceError.weeklyWindowUnavailable)
        }
        let used = min(max((weekly["usedPercent"] as? NSNumber)?.intValue ?? 0, 0), 100)
        let resetSeconds = (weekly["resetsAt"] as? NSNumber)?.doubleValue
        return .success(PlanUsageSnapshot(
            authenticated: true,
            planType: planType ?? bucket["planType"] as? String,
            email: email,
            remainingPercent: 100 - used,
            resetsAt: resetSeconds.map(Date.init(timeIntervalSince1970:)),
            windowDurationMinutes: 10_080,
            status: "LIVE"
        ))
    }
}

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
        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct LocalSummaryResult {
    var text: String
}

private final class LocalQwenSummaryService {
    private let model = "qwen3.5:2b"
    private var cache: [String: LocalSummaryResult] = [:]

    func summarize(id: String, text: String, layout: ActivitySummaryLayout) -> LocalSummaryResult {
        let cacheKey = "\(id)|\(layout.signature)"
        if let cached = cache[cacheKey] { return cached }
        let clippedInput = String(text.prefix(6_000))
        let prompt = """
        将输入内容总结成适合软件活动区展示的中文纯文本。活动区按当前字号大约每行可显示\(layout.approximateCharactersPerLine)个汉字，最多\(layout.maxLines)行。内容不必严格限制为100个汉字，但应尽量完整地放在这个活动区内。

        要求：
        1. 保留对象、核心结论、关键数字以及异常或限制。
        2. 优先说明发生了什么、结果如何、是否需要用户处理。
        3. 根据内容适当换行；不使用标题、Markdown、列表或前缀。
        4. 以总结为主。不要以省略号收尾；预计内容放不下时，提前结束完整语句，把展开的操作步骤或细节省略，并在末尾写“详情请进入客户端查看”。
        5. 不解释总结过程，不添加原文没有的信息。内容没有异常时直接陈述结果。

        输入内容：
        \(clippedInput)
        """
        let output = requestSummary(prompt, tokenBudget: min(max(layout.approximateCharacterCapacity * 2, 160), 600))
        let cleaned = cleanSummary(output)
        let result: LocalSummaryResult
        if cleaned.isEmpty {
            result = LocalSummaryResult(text: fitSummary(compactFallback(text), layout: layout))
        } else {
            result = LocalSummaryResult(text: fitSummary(cleaned, layout: layout))
        }
        cache[cacheKey] = result
        if cache.count > 32, let first = cache.keys.first { cache.removeValue(forKey: first) }
        return result
    }

    private func requestSummary(_ prompt: String, tokenBudget: Int) -> String? {
        guard let url = URL(string: "http://127.0.0.1:11434/api/generate"),
              let body = try? JSONSerialization.data(withJSONObject: [
                "model": model,
                "prompt": prompt,
                "stream": false,
                "think": false,
                "keep_alive": "10m",
                "options": ["temperature": 0.1, "num_predict": tokenBudget]
              ]) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.timeoutInterval = 45
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let semaphore = DispatchSemaphore(value: 0)
        var summary: String?
        let task = URLSession.shared.dataTask(with: request) { data, response, _ in
            defer { semaphore.signal() }
            guard let data, (response as? HTTPURLResponse)?.statusCode == 200,
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
            summary = object["response"] as? String
        }
        task.resume()
        if semaphore.wait(timeout: .now() + 46) == .timedOut {
            task.cancel()
            return nil
        }
        return summary
    }

    private func cleanSummary(_ value: String?) -> String {
        guard var text = value else { return "" }
        if let expression = try? NSRegularExpression(pattern: "\u{001B}\\[[0-9;?]*[ -/]*[@-~]"), !text.isEmpty {
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            text = expression.stringByReplacingMatches(in: text, range: range, withTemplate: "")
        }
        if let start = text.range(of: "<think>"), let end = text.range(of: "</think>", range: start.upperBound..<text.endIndex) {
            text.removeSubrange(start.lowerBound..<end.upperBound)
        }
        text = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "`", with: "")
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: #"\[([^\]]+)\]\([^\)]+\)"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"^(?:总结|摘要)[：:]\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?m)^[#*\-]+\s*"#, with: "", options: .regularExpression)
        while text.contains("  ") { text = text.replacingOccurrences(of: "  ", with: " ") }
        while text.contains("\n\n\n") { text = text.replacingOccurrences(of: "\n\n\n", with: "\n\n") }
        return text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"'")))
    }

    private func fitSummary(_ text: String, layout: ActivitySummaryLayout) -> String {
        let detail = "详情请进入客户端查看"
        var normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var requiresDetailNotice = false
        guard !normalized.isEmpty else { return "任务已完成，详情请进入客户端查看" }
        if hasTrailingEllipsis(normalized) {
            requiresDetailNotice = true
            while let last = normalized.last, last == "." || last == "…" || last == "。" {
                normalized.removeLast()
            }
            normalized = normalized.trimmingCharacters(in: .whitespacesAndNewlines)
            normalized = finishAtNaturalBoundary(normalized)
            let earlyEnding = normalized.isEmpty ? detail : "\(normalized)\n\(detail)"
            if summaryFits(earlyEnding, layout: layout) { return earlyEnding }
        }
        if !requiresDetailNotice, summaryFits(normalized, layout: layout) { return normalized }

        let summaryBody = normalized
            .replacingOccurrences(of: "\n\(detail)", with: "")
            .replacingOccurrences(of: detail, with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let characters = Array(summaryBody)
        var lower = 0
        var upper = characters.count
        while lower < upper {
            let middle = (lower + upper + 1) / 2
            let prefix = String(characters.prefix(middle)).trimmingCharacters(in: .whitespacesAndNewlines)
            let candidate = prefix.isEmpty ? detail : "\(prefix)。\n\(detail)"
            if summaryFits(candidate, layout: layout) {
                lower = middle
            } else {
                upper = middle - 1
            }
        }
        let prefix = finishAtNaturalBoundary(String(characters.prefix(lower)))
        return prefix.isEmpty ? detail : "\(prefix)\n\(detail)"
    }

    private func hasTrailingEllipsis(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasSuffix("...") || trimmed.hasSuffix("……") || trimmed.hasSuffix("…")
    }

    private func finishAtNaturalBoundary(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let sentenceMarks = CharacterSet(charactersIn: "。！？!?；;\n")
        if let boundary = trimmed.unicodeScalars.lastIndex(where: { sentenceMarks.contains($0) }) {
            let end = trimmed.unicodeScalars.index(after: boundary)
            let complete = String(trimmed.unicodeScalars[..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
            if complete.count >= min(16, trimmed.count) { return complete }
        }
        let cleaned = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "，,、：:；;-.… "))
        return cleaned.isEmpty ? "" : cleaned + "。"
    }

    private func summaryFits(_ text: String, layout: ActivitySummaryLayout) -> Bool {
        let formatted = "\(AgentActivityKind.reply.tag) \(text)"
        return PixelPainter.wrappedLines(
            formatted,
            style: layout.style,
            maxWidth: layout.width - 4,
            maxLines: layout.maxLines + 1
        ).count <= layout.maxLines
    }

    private func compactFallback(_ value: String) -> String {
        let text = cleanSummary(value)
        return text.isEmpty ? "任务已完成，但没有可显示的结果。" : String(text.prefix(600))
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

    func fetch(settings: WeatherSettings, completion: @escaping (WeatherSnapshot) -> Void) {
        queue.async {
            let live: WeatherSnapshot?
            switch settings.source {
            case .qweather:
                live = self.fetchFromQWeather(settings: settings)
            case .openMeteo:
                live = self.fetchFromOpenMeteo(city: settings.city) ?? self.fetchFromWttr(city: settings.city)
            case .macOSWeather:
                live = nil
            }
            let snapshot = live ?? self.readSystemWeather() ?? .demo
            DispatchQueue.main.async { completion(snapshot) }
        }
    }

    private func jsonObject(from url: URL, headers: [String: String] = [:], timeout: TimeInterval = 8) -> [String: Any]? {
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.setValue("HermesDashboard/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
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

    private func fetchFromQWeather(settings: WeatherSettings) -> WeatherSnapshot? {
        let host = settings.apiHost
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let key = settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let city = settings.city.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty, !key.isEmpty, !city.isEmpty else { return nil }

        let baseURL = host.hasPrefix("https://") ? host : "https://\(host)"
        var lookup = URLComponents(string: "\(baseURL)/geo/v2/city/lookup")
        lookup?.queryItems = [
            URLQueryItem(name: "location", value: city),
            URLQueryItem(name: "number", value: "1"),
            URLQueryItem(name: "lang", value: "en")
        ]
        let headers = ["X-QW-Api-Key": key]
        guard let lookupURL = lookup?.url,
              let lookupObject = jsonObject(from: lookupURL, headers: headers),
              (lookupObject["code"] as? String) == "200",
              let location = (lookupObject["location"] as? [[String: Any]])?.first,
              let latitude = location["lat"] as? String,
              let longitude = location["lon"] as? String else { return nil }

        let locationName = (location["name"] as? String) ?? city
        var current = URLComponents(string: "\(baseURL)/weather/v1/current/\(latitude)/\(longitude)")
        current?.queryItems = [URLQueryItem(name: "lang", value: "en")]
        guard let currentURL = current?.url,
              let object = jsonObject(from: currentURL, headers: headers),
              let temperature = object["temperature"] as? [String: Any],
              let value = jsonNumber(temperature["value"]) else { return nil }

        let conditionObject = object["condition"] as? [String: Any]
        let code = conditionObject?["code"] as? String ?? "999"
        let text = conditionObject?["text"] as? String ?? ""
        let unit = temperature["unit"] as? String ?? "°C"
        let formatted = value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
        return WeatherSnapshot(
            temperature: "\(formatted)\(unit)",
            condition: qweatherCondition(code: code, text: text),
            location: locationName,
            isLive: true,
            attribution: "QWEATHER"
        )
    }

    private func qweatherCondition(code: String, text: String) -> WeatherCondition {
        let value = Int(code) ?? 999
        switch value {
        case 100, 150: return .clear
        case 101...103, 151...153: return .partlyCloudy
        case 104, 154: return .cloudy
        case 302...304: return .thunderstorm
        case 309: return .drizzle
        case 300...399: return .rain
        case 400...499: return .snow
        case 500...515: return .fog
        default:
            return conditionFromText(text)
        }
    }

    private func conditionFromText(_ text: String) -> WeatherCondition {
        let value = text.lowercased()
        if value.contains("thunder") || value.contains("storm") || value.contains("雷") { return .thunderstorm }
        if value.contains("snow") || value.contains("雪") { return .snow }
        if value.contains("drizzle") || value.contains("毛毛雨") { return .drizzle }
        if value.contains("rain") || value.contains("雨") { return .rain }
        if value.contains("fog") || value.contains("mist") || value.contains("haze") || value.contains("雾") || value.contains("霾") { return .fog }
        if value.contains("overcast") || value.contains("阴") { return .cloudy }
        if value.contains("cloud") || value.contains("多云") { return .partlyCloudy }
        if value.contains("clear") || value.contains("sunny") || value.contains("晴") { return .clear }
        return .unknown
    }

    private func readSystemWeather() -> WeatherSnapshot? {
        if let cached = readWeatherCache() { return cached }
        return parseWeatherText(readWeatherAppAccessibilityTree())
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
    var activityLog: [AgentActivityEvent]
    var agentState: AgentState
    var contextPercent: Int
    var todayTokens: Int?
    var model: String?
    var thinking: String?
    var fastMode: Bool?
    var provider: String?
    var hasContextData: Bool
}

final class RuntimeStatusService {
    private let queue = DispatchQueue(label: "hermes-dashboard.runtime", qos: .utility)
    private let summaryQueue = DispatchQueue(label: "hermes-dashboard.summary", qos: .utility)
    private let qwenSummaryService = LocalQwenSummaryService()
    private var completedSummaries: [String: LocalSummaryResult] = [:]
    private var pendingSummaries = Set<String>()
    private let dailyTokenDateKey = "runtime.codex.dailyTokens.date"
    private let dailyTokenValueKey = "runtime.codex.dailyTokens.value"

    func fetch(source: RuntimeSource, activityLayout: ActivitySummaryLayout, completion: @escaping (RuntimeStatus) -> Void) {
        queue.async {
            var status = self.read(source: source) ?? RuntimeStatus.demo(source: source)
            status = self.summarizeFinalOutput(in: status, layout: activityLayout)
            DispatchQueue.main.async { completion(status) }
        }
    }

    private func summarizeFinalOutput(in status: RuntimeStatus, layout: ActivitySummaryLayout) -> RuntimeStatus {
        guard let finalIndex = status.activityLog.lastIndex(where: { $0.summarizeBeforeDisplay }) else { return status }
        var updated = status
        let finalEvent = updated.activityLog[finalIndex]
        let summaryID = "\(finalEvent.id)|\(layout.signature)"
        updated.activityLog.removeAll { $0.summarizeBeforeDisplay }
        guard let result = completedSummaries[summaryID] else {
            updated.agentState = .thinking
            updated.activityLog.append(AgentActivityEvent(id: "\(finalEvent.id):summary-pending", kind: .status, text: "正在总结输出结果"))
            if pendingSummaries.insert(summaryID).inserted {
                summaryQueue.async {
                    let result = self.qwenSummaryService.summarize(id: finalEvent.id, text: finalEvent.text, layout: layout)
                    self.queue.async {
                        self.pendingSummaries.remove(summaryID)
                        self.completedSummaries[summaryID] = result
                        if self.completedSummaries.count > 32, let first = self.completedSummaries.keys.first {
                            self.completedSummaries.removeValue(forKey: first)
                        }
                    }
                }
            }
            return updated
        }
        var summarized = finalEvent
        summarized.text = result.text
        summarized.summarizeBeforeDisplay = false
        updated.activityLog = [summarized]
        return updated
    }

    private func read(source: RuntimeSource) -> RuntimeStatus? {
        if source == .hermes, let hermesSnapshot = readHermesSnapshot() {
            return mapHermes(hermesSnapshot)
        }
        let codexSnapshot = source == .codex ? readCodexSnapshot() : nil
        for url in candidateURLs(for: source) {
            guard let data = try? Data(contentsOf: url), let payload = try? JSONDecoder().decode(RuntimePayload.self, from: data) else { continue }
            return map(payload, source: source, codexSnapshot: codexSnapshot)
        }
        if source == .codex, let codexSnapshot {
            var status = RuntimeStatus.demo(source: source)
            status.activeSession = codexSnapshot.sessions.first?.title ?? status.activeSession
            status.contextPercent = codexSnapshot.contextPercent
            status.tokenPercent = codexSnapshot.contextPercent
            status.agentState = codexSnapshot.agentState
            status.sessions = codexSnapshot.sessions
            status.activityLog = codexSnapshot.activityLog
            if let todayTokens = codexSnapshot.todayTokens {
                status.todayTokens = todayTokens
                status.hasTodayTokenData = true
            }
            if let model = codexSnapshot.model { status.model = model }
            if let thinking = codexSnapshot.thinking { status.thinking = thinking.uppercased() }
            if let fastMode = codexSnapshot.fastMode { status.fastMode = fastMode }
            if let sourceProvider = codexSnapshot.provider { status.provider = sourceProvider.uppercased() }
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

    private func mapHermes(_ snapshot: HermesSnapshot) -> RuntimeStatus {
        RuntimeStatus(
            source: .hermes,
            model: snapshot.model,
            thinking: snapshot.thinking.uppercased(),
            fastMode: snapshot.fastMode,
            provider: snapshot.provider.uppercased(),
            balance: RuntimeStatus.demo(source: .hermes).balance,
            balanceValue: RuntimeStatus.demo(source: .hermes).balanceValue,
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
        let activityLog = readHermesActivity(dbPath: dbPath, sessionID: sessionID, fallback: current["last_activity_description"] as? String, isComplete: agentState == .idle || agentState == .done)
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

    private func readHermesActivity(dbPath: String, sessionID: String, fallback: String?, isComplete: Bool) -> [AgentActivityEvent] {
        guard !sessionID.isEmpty else { return fallbackEvents(fallback) }
        let sql = """
        SELECT id,
               role,
               tool_name,
               substr(COALESCE(reasoning, reasoning_content, ''), 1, 280) AS reasoning,
               substr(COALESCE(content, ''), 1, 12000) AS content,
               substr(COALESCE(tool_calls, ''), 1, 900) AS tool_calls
        FROM messages
        WHERE session_id = '\(sessionID.replacingOccurrences(of: "'", with: "''"))'
          AND IFNULL(active, 1) = 1
        ORDER BY timestamp DESC, id DESC
        LIMIT 40;
        """
        let rows = readSQLiteRows(path: dbPath, query: sql)
        var packets: [[AgentActivityEvent]] = []
        var packed = 0
        for row in rows {
            var packet: [AgentActivityEvent] = []
            let messageID = String(describing: row["id"] ?? "hermes-\(packed)")
            let role = (row["role"] as? String ?? "").lowercased()
            if role == "tool" {
                let name = (row["tool_name"] as? String ?? "tool").trimmingCharacters(in: .whitespacesAndNewlines)
                let snippet = compactActivityText(row["content"] as? String)
                let failed = snippet.lowercased().contains("error") || snippet.lowercased().contains("exit_code\": 1") || snippet.contains("exit_code\":1")
                let text = snippet.isEmpty ? "\(name) 执行完成" : "\(name)：\(snippet)"
                packet.append(AgentActivityEvent(id: "hermes:\(messageID):result", kind: failed ? .error : .result, text: text))
            } else if role == "assistant" {
                let toolNames = functionNames(from: row["tool_calls"] as? String)
                let think = compactActivityText(row["reasoning"] as? String)
                let rawSpoken = row["content"] as? String ?? ""
                let spoken = isComplete ? rawSpoken.trimmingCharacters(in: .whitespacesAndNewlines) : compactActivityText(rawSpoken, limit: 90)
                if !spoken.isEmpty && toolNames.isEmpty {
                    packet.append(AgentActivityEvent(id: "hermes:\(messageID):output", kind: isComplete ? .reply : .status, text: spoken, summarizeBeforeDisplay: isComplete))
                }
                if !think.isEmpty {
                    packet.append(AgentActivityEvent(id: "hermes:\(messageID):thinking", kind: .think, text: think))
                }
                if !toolNames.isEmpty {
                    packet.append(AgentActivityEvent(id: "hermes:\(messageID):tools", kind: .tool, text: "调用 \(toolNames.joined(separator: "、"))"))
                }
            }
            if !packet.isEmpty {
                packets.append(packet)
                packed += packet.count
            }
            if packed >= 16 { break }
        }
        packets.reverse()
        let events = packets.flatMap { $0 }
        if events.isEmpty { return fallbackEvents(fallback) }
        return events
    }

    private func fallbackEvents(_ fallback: String?) -> [AgentActivityEvent] {
        let text = compactActivityText(fallback)
        if text.isEmpty { return [] }
        return [AgentActivityEvent(id: "hermes:fallback:\(text)", kind: .status, text: text)]
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
            .trimmingCharacters(in: CharacterSet(charactersIn: "#-*`"))
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
            let stateRowsResult = readSQLiteRowsIfAvailable(path: statePath, query: "SELECT id, rollout_path, tokens_used, model, reasoning_effort, model_provider FROM threads;")
            let stateRows = stateRowsResult ?? []
            let states = Dictionary(uniqueKeysWithValues: stateRows.compactMap { row -> (String, [String: Any])? in
                guard let id = row["id"] as? String else { return nil }
                return (id, row)
            })
            let turnRowsResult = readSQLiteRowsIfAvailable(path: historyPath, query: "SELECT thread_id, status, started_at, completed_at FROM thread_turns ORDER BY started_at DESC;")
            let turnRows = turnRowsResult ?? []
            var latestTurns: [String: [String: Any]] = [:]
            for row in turnRows {
                guard let threadID = row["thread_id"] as? String else { continue }
                let started = (row["started_at"] as? NSNumber)?.doubleValue ?? 0
                let previous = (latestTurns[threadID]?["started_at"] as? NSNumber)?.doubleValue ?? -1
                if started > previous { latestTurns[threadID] = row }
            }
            let measuredTodayTokens: Int? = stateRowsResult != nil && turnRowsResult != nil
                ? completedTodayTokens(states: states, latestTurns: latestTurns)
                : nil
            let todayTokens = stableTodayTokens(measured: measuredTodayTokens)

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
                let activityLog = (currentState?["rollout_path"] as? String).map(readCodexActivity) ?? []
                let latestKind = activityLog.last?.kind
                let resolvedAgentState: AgentState
                if sessions.contains(where: { $0.status == "RUNNING" }) {
                    switch latestKind {
                    case .think: resolvedAgentState = .thinking
                    case .reply: resolvedAgentState = .outputting
                    case .error: resolvedAgentState = .error
                    default: resolvedAgentState = .working
                    }
                } else if latestKind == .error {
                    resolvedAgentState = .error
                } else {
                    resolvedAgentState = agentState
                }
                return CodexSnapshot(
                    sessions: sessions,
                    activityLog: activityLog,
                    agentState: resolvedAgentState,
                    contextPercent: sessions[0].contextPercent,
                    todayTokens: todayTokens,
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
        return CodexSnapshot(sessions: legacySessions, activityLog: [], agentState: .idle, contextPercent: legacySessions[0].contextPercent, todayTokens: stableTodayTokens(measured: nil), model: metadata.model, thinking: metadata.thinking, fastMode: metadata.fastMode, provider: metadata.provider, hasContextData: legacySessions.contains { $0.contextPercent > 0 })
    }

    private func completedTodayTokens(states: [String: [String: Any]], latestTurns: [String: [String: Any]], now: Date = Date()) -> Int {
        let startOfDay = Calendar.current.startOfDay(for: now).timeIntervalSince1970
        var total: Int64 = 0
        for (threadID, turn) in latestTurns {
            let status = (turn["status"] as? String ?? "").lowercased()
            guard ["completed", "failed", "interrupted"].contains(status),
                  let completedAt = (turn["completed_at"] as? NSNumber)?.doubleValue,
                  completedAt >= startOfDay,
                  let tokens = (states[threadID]?["tokens_used"] as? NSNumber)?.int64Value else { continue }
            total += max(tokens, 0)
        }
        return Int(min(total, Int64(Int.max)))
    }

    private func stableTodayTokens(measured: Int?, now: Date = Date()) -> Int? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar.current
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        let today = formatter.string(from: now)
        let defaults = UserDefaults.standard
        let cachedDate = defaults.string(forKey: dailyTokenDateKey)

        if cachedDate != today {
            guard let measured else { return nil }
            let value = max(measured, 0)
            defaults.set(today, forKey: dailyTokenDateKey)
            defaults.set(value, forKey: dailyTokenValueKey)
            return value
        }

        let cached = max(defaults.integer(forKey: dailyTokenValueKey), 0)
        guard let measured else { return cached }
        let value = max(cached, measured)
        if value != cached { defaults.set(value, forKey: dailyTokenValueKey) }
        return value
    }

    private func readCodexActivity(_ path: String) -> [AgentActivityEvent] {
        guard FileManager.default.fileExists(atPath: path),
              let handle = try? FileHandle(forReadingFrom: URL(fileURLWithPath: path)) else { return [] }
        defer { try? handle.close() }
        let end = (try? handle.seekToEnd()) ?? 0
        let maxBytes: UInt64 = 8 * 1_024 * 1_024
        let offset = end > maxBytes ? end - maxBytes : 0
        handle.seek(toFileOffset: offset)
        guard let data = try? handle.readToEnd(), var text = String(data: data, encoding: .utf8) else { return [] }
        if offset > 0, let newline = text.firstIndex(of: "\n") {
            text.removeSubrange(text.startIndex...newline)
        }

        var events: [AgentActivityEvent] = []
        var seen = Set<String>()
        var pendingApprovalEventIDs = Set<String>()
        var approvalEventIDByCallID: [String: String] = [:]
        for (lineIndex, line) in text.split(whereSeparator: \.isNewline).enumerated() {
            guard line.utf8.count <= 524_288,
                  let lineData = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let recordType = object["type"] as? String else { continue }
            let payload = object["payload"] as? [String: Any] ?? [:]
            if recordType == "event_msg", (payload["type"] as? String) == "task_started" {
                events.removeAll()
                seen.removeAll()
                pendingApprovalEventIDs.removeAll()
                approvalEventIDByCallID.removeAll()
                continue
            }

            if recordType == "response_item" {
                let responseType = (payload["type"] as? String ?? "").lowercased()
                if responseType == "custom_tool_call_output" || responseType == "function_call_output" {
                    if let callID = payload["call_id"] as? String,
                       let eventID = approvalEventIDByCallID.removeValue(forKey: callID) {
                        pendingApprovalEventIDs.remove(eventID)
                    }
                } else if isApprovalRequest(payload),
                          let callID = (payload["call_id"] as? String) ?? (payload["id"] as? String) {
                    let itemID = payload["id"] as? String ?? "approval-\(lineIndex)"
                    let eventID = "codex:\(itemID):approval"
                    approvalEventIDByCallID[callID] = eventID
                    pendingApprovalEventIDs.insert(eventID)
                }
            }

            let event: AgentActivityEvent?
            if recordType == "event_msg", (payload["type"] as? String) == "item_completed",
               let item = payload["item"] as? [String: Any] {
                event = codexCompletedEvent(item, fallbackID: "event-\(lineIndex)")
            } else if recordType == "response_item" {
                event = codexResponseEvent(payload, fallbackID: "response-\(lineIndex)")
            } else {
                event = nil
            }
            guard let event, !event.text.isEmpty, seen.insert(event.id).inserted else { continue }
            events.append(event)
            if events.count > 40 { events.removeFirst(events.count - 40) }
        }

        events.removeAll { $0.kind == .approval && !pendingApprovalEventIDs.contains($0.id) }

        if events.isEmpty {
            return [AgentActivityEvent(id: "codex:waiting", kind: .status, text: "等待 Codex 活动")]
        }
        return Array(coalesceCodexEvents(events).suffix(10))
    }

    private func coalesceCodexEvents(_ events: [AgentActivityEvent]) -> [AgentActivityEvent] {
        let replaceableKinds: Set<String> = [
            AgentActivityKind.think.rawValue,
            AgentActivityKind.tool.rawValue,
            AgentActivityKind.files.rawValue,
            AgentActivityKind.search.rawValue,
            AgentActivityKind.status.rawValue,
            AgentActivityKind.approval.rawValue
        ]
        var compacted: [AgentActivityEvent] = []
        for event in events {
            if let last = compacted.last,
               last.kind == event.kind,
               replaceableKinds.contains(event.kind.rawValue) {
                compacted[compacted.count - 1] = event
            } else {
                compacted.append(event)
            }
        }
        return compacted
    }

    private func codexCompletedEvent(_ item: [String: Any], fallbackID: String) -> AgentActivityEvent? {
        let rawType = (item["type"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let type = rawType.lowercased()
        let itemID = item["id"] as? String ?? fallbackID
        switch type {
        case "reasoning":
            let text = compactActivityText(extractCodexText(item["summary_text"]), limit: 84)
            guard !text.isEmpty else { return nil }
            return AgentActivityEvent(id: "codex:\(itemID):thinking", kind: .think, text: text)
        case "commandexecution":
            let command = (item["command"] as? [Any])?.map { String(describing: $0) } ?? []
            let description = compactCommandDescription(command)
            let status = (item["status"] as? String ?? "completed").lowercased()
            let exitCode = (item["exit_code"] as? NSNumber)?.intValue
            if status == "failed" || (exitCode != nil && exitCode != 0) {
                let suffix = exitCode.map { "（退出码 \($0)）" } ?? ""
                return AgentActivityEvent(id: "codex:\(itemID):error", kind: .error, text: "\(description)失败\(suffix)")
            }
            return AgentActivityEvent(id: "codex:\(itemID):tool", kind: .tool, text: "\(description) · 完成")
        case "filechange":
            return AgentActivityEvent(id: "codex:\(itemID):files", kind: .files, text: compactFileChanges(item["changes"]))
        case "extension", "websearch":
            return AgentActivityEvent(id: "codex:\(itemID):search", kind: .search, text: "查询网络资料")
        case "mcptoolcall", "dynamictoolcall", "collabtoolcall":
            let name = compactActivityText((item["tool"] as? String) ?? (item["server"] as? String) ?? "扩展工具", limit: 32)
            return AgentActivityEvent(id: "codex:\(itemID):tool", kind: .tool, text: "调用 \(name)")
        case "imageview":
            let name = (item["path"] as? String).map { URL(fileURLWithPath: $0).lastPathComponent } ?? "图片"
            return AgentActivityEvent(id: "codex:\(itemID):image", kind: .tool, text: "查看 \(compactActivityText(name, limit: 42))")
        case "contextcompaction":
            return AgentActivityEvent(id: "codex:\(itemID):compact", kind: .status, text: "整理会话上下文")
        case "agentmessage":
            let text = extractCodexText(item["content"])
            let phase = (item["phase"] as? String ?? "").lowercased()
            if phase == "final_answer" {
                return AgentActivityEvent(id: "codex:\(itemID):output", kind: .reply, text: String(text.prefix(12_000)), summarizeBeforeDisplay: true)
            }
            let compact = compactActivityText(text, limit: 90)
            guard !compact.isEmpty else { return nil }
            return AgentActivityEvent(id: "codex:\(itemID):status", kind: .status, text: compact)
        default:
            return nil
        }
    }

    private func codexResponseEvent(_ payload: [String: Any], fallbackID: String) -> AgentActivityEvent? {
        let type = (payload["type"] as? String ?? "").lowercased()
        let itemID = payload["id"] as? String ?? fallbackID
        switch type {
        case "reasoning":
            let text = compactActivityText(extractCodexText(payload["summary"]), limit: 84)
            guard !text.isEmpty else { return nil }
            return AgentActivityEvent(id: "codex:\(itemID):thinking", kind: .think, text: text)
        case "message":
            guard (payload["role"] as? String)?.lowercased() == "assistant" else { return nil }
            let text = extractCodexText(payload["content"])
            let phase = (payload["phase"] as? String ?? "").lowercased()
            if phase == "final_answer" {
                return AgentActivityEvent(id: "codex:\(itemID):output", kind: .reply, text: String(text.prefix(12_000)), summarizeBeforeDisplay: true)
            }
            let compact = compactActivityText(text, limit: 90)
            guard !compact.isEmpty else { return nil }
            return AgentActivityEvent(id: "codex:\(itemID):status", kind: .status, text: compact)
        case "custom_tool_call", "function_call":
            if isApprovalRequest(payload) {
                return AgentActivityEvent(id: "codex:\(itemID):approval", kind: .approval, text: "等待用户授权后继续")
            }
            let name = payload["name"] as? String ?? "tool"
            let input = payload["input"] as? String ?? ""
            let description = compactToolCall(name: name, input: input)
            return AgentActivityEvent(id: "codex:\(itemID):tool", kind: .tool, text: description)
        default:
            return nil
        }
    }

    private func isApprovalRequest(_ payload: [String: Any]) -> Bool {
        let type = (payload["type"] as? String ?? "").lowercased()
        if ["request_approval", "approval_request", "permission_request"].contains(type) { return true }
        guard type == "custom_tool_call" || type == "function_call" else { return false }
        let input = payload["input"] as? String ?? ""
        let normalized = input.lowercased()
        return normalized.contains("sandbox_permissions") && normalized.contains("require_escalated")
    }

    private func extractCodexText(_ value: Any?) -> String {
        if let text = value as? String { return text }
        if let values = value as? [Any] {
            return values.map(extractCodexText).filter { !$0.isEmpty }.joined(separator: " ")
        }
        if let value = value as? [String: Any] {
            for key in ["text", "content", "summary_text", "message"] {
                let text = extractCodexText(value[key])
                if !text.isEmpty { return text }
            }
        }
        return ""
    }

    private func compactCommandDescription(_ command: [String]) -> String {
        let joined = command.joined(separator: " ").lowercased()
        if joined.contains("./build.sh") || joined.contains("swift build") || joined.contains("swiftc ") { return "构建 Hermes Dashboard" }
        if joined.contains("codesign") { return "验证应用签名" }
        if joined.contains("git commit") { return "提交 Git 改动" }
        if joined.contains("git add") { return "暂存 Git 改动" }
        if joined.contains("git status") || joined.contains("git diff") || joined.contains("git log") { return "检查 Git 仓库" }
        if joined.contains("rg ") || joined.contains("grep ") { return "搜索项目内容" }
        if joined.contains("sed ") || joined.contains("cat ") || joined.contains("nl ") || joined.contains("tail ") || joined.contains("head ") || joined.contains("find ") { return "读取项目文件" }
        if joined.contains("apply_patch") { return "更新项目文件" }
        if joined.contains("ollama") { return "处理输出摘要" }
        if joined.contains("curl ") { return "访问本地服务" }
        guard let executable = command.first else { return "执行本地命令" }
        if executable.contains("\n") || executable.contains("exec_command") || executable.count > 100 { return "执行本地命令" }
        let name = URL(fileURLWithPath: executable).lastPathComponent
        return "执行 \(compactActivityText(name, limit: 28))"
    }

    private func compactToolCall(name: String, input: String) -> String {
        let lower = input.lowercased()
        if lower.contains("web__run") { return "查询 OpenAI 官方文档" }
        if lower.contains("apply_patch") { return "更新项目文件" }
        if lower.contains("view_image") || lower.contains("imagegen") { return "处理图片资源" }
        if lower.contains("exec_command") {
            return compactCommandDescription([input])
        }
        return "调用 \(compactActivityText(name.replacingOccurrences(of: "_", with: " "), limit: 32))"
    }

    private func compactFileChanges(_ value: Any?) -> String {
        var paths: [String] = []
        if let changes = value as? [[String: Any]] {
            paths = changes.compactMap { ($0["path"] as? String).map { URL(fileURLWithPath: $0).lastPathComponent } }
        } else if let changes = value as? [String: Any] {
            paths = changes.keys.map { URL(fileURLWithPath: $0).lastPathComponent }
        }
        let unique = Array(Set(paths)).sorted()
        guard !unique.isEmpty else { return "更新项目文件" }
        let names = unique.prefix(3).joined(separator: "、")
        let description = unique.count > 3 ? "更新 \(names) 等 \(unique.count) 个文件" : "更新 \(names)"
        return compactActivityText(description, limit: 84)
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
        readSQLiteRowsIfAvailable(path: path, query: query) ?? []
    }

    private func readSQLiteRowsIfAvailable(path: String, query: String) -> [[String: Any]]? {
        guard FileManager.default.fileExists(atPath: path),
              let output = ProcessRunner.run(executable: "/usr/bin/sqlite3", arguments: ["-readonly", "-json", path, query], timeout: 8) else { return nil }
        if output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return [] }
        guard
              let data = output.data(using: .utf8),
              let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return nil }
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

    private func map(_ payload: RuntimePayload, source: RuntimeSource, codexSnapshot: CodexSnapshot?) -> RuntimeStatus {
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
            provider: (codexSnapshot?.provider ?? payload.provider ?? demo.provider).uppercased(),
            balance: payload.balance ?? demo.balance,
            balanceValue: payload.balanceValue ?? demo.balanceValue,
            tokenPercent: codexSnapshot?.contextPercent ?? clamp(Int(((payload.tokenPercent ?? payload.tokens ?? Double(demo.tokenPercent))).rounded()), min: 0, max: 100),
            todayTokens: codexSnapshot?.todayTokens ?? 0,
            hasTodayTokenData: codexSnapshot?.todayTokens != nil,
            activeSession: currentSession,
            elapsed: payload.elapsed ?? demo.elapsed,
            contextPercent: clamp(calculatedContext, min: 0, max: 100),
            agentState: agentState,
            sessions: Array(sessionValues.prefix(5)),
            activityLog: codexSnapshot?.activityLog ?? [],
            isLive: true,
            hasModelData: !(codexSnapshot?.model ?? payload.model ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            hasContextData: codexSnapshot?.hasContextData ?? (payload.contextUsedTokens != nil || payload.contextPercent != nil || payload.tokenPercent != nil || payload.tokens != nil)
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
