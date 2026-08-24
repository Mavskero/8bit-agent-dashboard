import AppKit
import Foundation
import ImageIO

struct TextStyle: Codable, Equatable {
    static let builtInPixelFont = "__PIXEL_GRID__"
    var fontName: String
    var pointSize: CGFloat
    var colorHex: String

    static var defaultFontName: String {
        builtInPixelFont
    }

    var color: NSColor { NSColor(hex: colorHex) ?? PixelPalette.cream }
}

enum DashboardStyleKey: String, CaseIterable {
    case clock
    case date
    case temperature
    case artist
    case title
    case runtime
    case agent
    case activeSession
    case recentSession

    var displayName: String {
        switch self {
        case .clock: return "Clock"
        case .date: return "Date"
        case .temperature: return "Temperature"
        case .artist: return "Now Playing · Artist"
        case .title: return "Now Playing · Title"
        case .runtime: return "Runtime Status"
        case .agent: return "Hermes Agent"
        case .activeSession: return "Active Session"
        case .recentSession: return "Recent Sessions"
        }
    }
}

struct DashboardStyles: Codable, Equatable {
    private var values: [String: TextStyle]

    static var defaults: DashboardStyles {
        let font = TextStyle.defaultFontName
        return DashboardStyles(values: [
            DashboardStyleKey.clock.rawValue: TextStyle(fontName: font, pointSize: 112, colorHex: "F2E4C9"),
            DashboardStyleKey.date.rawValue: TextStyle(fontName: font, pointSize: 35, colorHex: "F2E4C9"),
            DashboardStyleKey.temperature.rawValue: TextStyle(fontName: font, pointSize: 35, colorHex: "43E0DC"),
            DashboardStyleKey.artist.rawValue: TextStyle(fontName: font, pointSize: 28, colorHex: "43E0DC"),
            DashboardStyleKey.title.rawValue: TextStyle(fontName: font, pointSize: 49, colorHex: "F2E4C9"),
            DashboardStyleKey.runtime.rawValue: TextStyle(fontName: font, pointSize: 28, colorHex: "F2E4C9"),
            DashboardStyleKey.agent.rawValue: TextStyle(fontName: font, pointSize: 28, colorHex: "43E0DC"),
            DashboardStyleKey.activeSession.rawValue: TextStyle(fontName: font, pointSize: 28, colorHex: "F2E4C9"),
            DashboardStyleKey.recentSession.rawValue: TextStyle(fontName: font, pointSize: 14, colorHex: "F2E4C9")
        ])
    }

    func style(for key: DashboardStyleKey) -> TextStyle {
        values[key.rawValue] ?? DashboardStyles.defaults.values[key.rawValue]!
    }

    mutating func setStyle(_ style: TextStyle, for key: DashboardStyleKey) {
        values[key.rawValue] = style
    }

    static func load() -> DashboardStyles {
        guard let data = UserDefaults.standard.data(forKey: "dashboardStyles"),
              let decoded = try? JSONDecoder().decode(DashboardStyles.self, from: data) else {
            return .defaults
        }
        var merged = DashboardStyles.defaults
        for key in DashboardStyleKey.allCases {
            if let saved = decoded.values[key.rawValue] {
                merged.values[key.rawValue] = saved
            }
        }
        return merged
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: "dashboardStyles")
    }
}

extension NSColor {
    convenience init?(hex: String) {
        let cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        guard cleaned.count == 6 || cleaned.count == 8,
              let value = UInt64(cleaned, radix: 16) else { return nil }
        let red = CGFloat((value >> (cleaned.count == 8 ? 24 : 16)) & 0xFF) / 255
        let green = CGFloat((value >> (cleaned.count == 8 ? 16 : 8)) & 0xFF) / 255
        let blue = CGFloat((value >> (cleaned.count == 8 ? 8 : 0)) & 0xFF) / 255
        let alpha = cleaned.count == 8 ? CGFloat(value & 0xFF) / 255 : 1
        self.init(calibratedRed: red, green: green, blue: blue, alpha: alpha)
    }

    var hexString: String {
        guard let rgb = usingColorSpace(.deviceRGB) else { return "FFFFFF" }
        let red = Int(round(rgb.redComponent * 255))
        let green = Int(round(rgb.greenComponent * 255))
        let blue = Int(round(rgb.blueComponent * 255))
        return String(format: "%02X%02X%02X", red, green, blue)
    }
}

enum RuntimeSource: String, CaseIterable {
    case codex
    case hermes

    var displayName: String {
        switch self {
        case .codex: return "Codex Desktop"
        case .hermes: return "Hermes Agent"
        }
    }
}

enum AgentState: String {
    case working
    case thinking
    case done
    case idle
    case error

    init(rawValue: String) {
        switch rawValue.lowercased() {
        case "working", "running", "executing": self = .working
        case "thinking", "planning": self = .thinking
        case "done", "complete", "completed", "success": self = .done
        case "error", "failed": self = .error
        default: self = .idle
        }
    }

    var label: String {
        switch self {
        case .working: return "WORKING..."
        case .thinking: return "THINKING..."
        case .done: return "DONE"
        case .idle: return "IDLE"
        case .error: return "ERROR"
        }
    }
}

enum WeatherCondition {
    case clear
    case partlyCloudy
    case cloudy
    case rain
    case snow
    case unknown
}

struct WeatherSnapshot {
    var temperature: String
    var condition: WeatherCondition
    var location: String
    var isLive: Bool

    static let demo = WeatherSnapshot(
        temperature: "24°C",
        condition: .partlyCloudy,
        location: "",
        isLive: false
    )
}

struct MusicSnapshot {
    var artist: String
    var title: String
    var album: String
    var isPlaying: Bool
    var position: Double
    var duration: Double

    static let notPlaying = MusicSnapshot(
        artist: "HERMES AGENT",
        title: "TELEMETRY DREAMS",
        album: "",
        isPlaying: false,
        position: 0,
        duration: 0
    )
}

struct SessionInfo {
    var title: String
    var progress: Int
    var status: String
    var updatedAt: String
}

struct RuntimeStatus {
    var source: RuntimeSource
    var model: String
    var thinking: String
    var fastMode: Bool
    var provider: String
    var balance: String
    var tokenPercent: Int
    var activeSession: String
    var elapsed: String
    var contextPercent: Int
    var agentState: AgentState
    var sessions: [SessionInfo]
    var isLive: Bool

    static func demo(source: RuntimeSource) -> RuntimeStatus {
        RuntimeStatus(
            source: source,
            model: "GPT-5",
            thinking: "HIGH",
            fastMode: true,
            provider: "OPENAI",
            balance: "$18.42",
            tokenPercent: 72,
            activeSession: "Refactor telemetry pipeline",
            elapsed: "08:41",
            contextPercent: 68,
            agentState: .working,
            sessions: [
                SessionInfo(title: "Build dashboard shell", progress: 100, status: "DONE", updatedAt: "18:32"),
                SessionInfo(title: "Tune pixel avatar", progress: 82, status: "", updatedAt: "17:05"),
                SessionInfo(title: "API health check", progress: 46, status: "", updatedAt: "15:47"),
                SessionInfo(title: "Write release notes", progress: 24, status: "", updatedAt: "13:22")
            ],
            isLive: false
        )
    }
}

final class DashboardModel: NSObject {
    private(set) var weather: WeatherSnapshot = .demo
    private(set) var music: MusicSnapshot = .notPlaying
    private(set) var runtime: RuntimeStatus
    private(set) var wallpaperPath: String?
    private(set) var assetFolderPath: String?
    private(set) var styles: DashboardStyles
    private(set) var assetStore: DashboardAssetStore
    var onChange: (() -> Void)?

    var runtimeSource: RuntimeSource {
        didSet {
            UserDefaults.standard.set(runtimeSource.rawValue, forKey: Keys.runtimeSource)
            refreshRuntime()
        }
    }

    private enum Keys {
        static let runtimeSource = "runtimeSource"
        static let wallpaperPath = "wallpaperPath"
        static let assetFolderPath = "assetFolderPath"
    }

    private let weatherService = SystemWeatherService()
    private let musicService = AppleMusicService()
    private let runtimeService = RuntimeStatusService()
    private var refreshTimer: Timer?

    override init() {
        let storedSource = UserDefaults.standard.string(forKey: Keys.runtimeSource)
            .flatMap(RuntimeSource.init(rawValue:)) ?? .codex
        runtimeSource = storedSource
        runtime = RuntimeStatus.demo(source: storedSource)
        wallpaperPath = UserDefaults.standard.string(forKey: Keys.wallpaperPath)
        assetFolderPath = UserDefaults.standard.string(forKey: Keys.assetFolderPath)
        styles = DashboardStyles.load()
        assetStore = DashboardAssetStore(folderURL: assetFolderPath.map(URL.init(fileURLWithPath:)))
        super.init()
    }

    func start() {
        refreshAll()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.refreshDynamicData()
        }
    }

    func stop() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    func setWallpaper(url: URL?) {
        wallpaperPath = url?.path
        if let path = wallpaperPath {
            UserDefaults.standard.set(path, forKey: Keys.wallpaperPath)
        } else {
            UserDefaults.standard.removeObject(forKey: Keys.wallpaperPath)
        }
        notifyChange()
    }

    func setAssetFolder(url: URL?) {
        assetFolderPath = url?.path
        if let path = assetFolderPath {
            UserDefaults.standard.set(path, forKey: Keys.assetFolderPath)
        } else {
            UserDefaults.standard.removeObject(forKey: Keys.assetFolderPath)
        }
        assetStore = DashboardAssetStore(folderURL: url)
        notifyChange()
    }

    func updateStyle(_ style: TextStyle, for key: DashboardStyleKey) {
        styles.setStyle(style, for: key)
        styles.save()
        notifyChange()
    }

    func resetStyles() {
        styles = .defaults
        styles.save()
        notifyChange()
    }

    func refreshAll() {
        refreshWeather()
        refreshMusic()
        refreshRuntime()
    }

    private func refreshDynamicData() {
        refreshMusic()
        refreshRuntime()
    }

    private func refreshWeather() {
        weatherService.fetch { [weak self] snapshot in
            guard let self else { return }
            self.weather = snapshot
            self.notifyChange()
        }
    }

    private func refreshMusic() {
        musicService.fetch { [weak self] snapshot in
            guard let self else { return }
            self.music = snapshot
            self.notifyChange()
        }
    }

    fileprivate func refreshRuntime() {
        let source = runtimeSource
        runtimeService.fetch(source: source) { [weak self] status in
            guard let self else { return }
            self.runtime = status
            self.notifyChange()
        }
    }

    private func notifyChange() {
        DispatchQueue.main.async { [weak self] in
            self?.onChange?()
        }
    }
}

final class DashboardAssetStore {
    let folderURL: URL?
    private var staticCache: [String: CGImage] = [:]
    private var gifCache: [String: GIFAnimator] = [:]

    init(folderURL: URL?) {
        self.folderURL = folderURL
    }

    func weatherImage(condition: WeatherCondition, at time: TimeInterval) -> CGImage? {
        let names: [String]
        switch condition {
        case .clear: names = ["weather-clear", "weather"]
        case .partlyCloudy: names = ["weather-partly-cloudy", "weather-cloudy", "weather"]
        case .cloudy: names = ["weather-cloudy", "weather"]
        case .rain: names = ["weather-rain", "weather"]
        case .snow: names = ["weather-snow", "weather"]
        case .unknown: names = ["weather", "weather-clear"]
        }
        return image(names: names, subfolders: ["weather", "icons"], at: time)
    }

    func agentImage(state: AgentState, at time: TimeInterval) -> CGImage? {
        let names = [
            "hermes-\(state.rawValue)",
            "agent-\(state.rawValue)",
            "hermes",
            "agent"
        ]
        return image(names: names, subfolders: ["hermes", "agent", "icons"], at: time)
    }

    private func image(names: [String], subfolders: [String], at time: TimeInterval) -> CGImage? {
        guard let folderURL else { return nil }
        for name in names {
            for folder in [folderURL] + subfolders.map({ folderURL.appendingPathComponent($0, isDirectory: true) }) {
                for ext in ["gif", "png", "jpg", "jpeg"] {
                    let url = folder.appendingPathComponent("\(name).\(ext)")
                    guard FileManager.default.fileExists(atPath: url.path) else { continue }
                    if ext == "gif" {
                        if gifCache[url.path] == nil {
                            gifCache[url.path] = GIFAnimator(url: url)
                        }
                        if let frame = gifCache[url.path]?.frame(at: time) { return frame }
                    } else {
                        if staticCache[url.path] == nil {
                            staticCache[url.path] = Self.loadImage(at: url)
                        }
                        if let image = staticCache[url.path] { return image }
                    }
                }
            }
        }
        return nil
    }

    private static func loadImage(at url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}
