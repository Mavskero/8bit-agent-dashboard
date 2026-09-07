import AppKit
import Foundation
import ImageIO
import QuartzCore
import Security

enum DashboardDisplayPreference {
    private static let displayIDKey = "preferredDisplayID"

    static func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        let key = NSDeviceDescriptionKey(rawValue: "NSScreenNumber")
        return (screen.deviceDescription[key] as? NSNumber).map { CGDirectDisplayID($0.uint32Value) }
    }

    static var savedDisplayID: CGDirectDisplayID? {
        guard let value = UserDefaults.standard.object(forKey: displayIDKey) as? NSNumber else { return nil }
        return CGDirectDisplayID(value.uint32Value)
    }

    static func preferredScreen() -> NSScreen {
        if let savedDisplayID,
           let screen = NSScreen.screens.first(where: { displayID(for: $0) == savedDisplayID }) {
            return screen
        }
        return NSScreen.main ?? NSScreen.screens[0]
    }

    static func save(screen: NSScreen) {
        guard let id = displayID(for: screen) else { return }
        UserDefaults.standard.set(NSNumber(value: id), forKey: displayIDKey)
    }

    static func label(for screen: NSScreen, index: Int) -> String {
        let width = Int(screen.frame.width.rounded())
        let height = Int(screen.frame.height.rounded())
        return "\(index + 1). \(screen.localizedName) (\(width)x\(height))"
    }
}

struct TextStyle: Codable, Equatable {
    static let builtInPixelFont = "__PIXEL_GRID__"
    static let silkscreenRegular = "Silkscreen-Regular"
    static let silkscreenBold = "Silkscreen-Bold"
    var fontName: String
    var pointSize: CGFloat
    var colorHex: String
    var smoothRendering: Bool
    /// The base position for this text group in design-canvas coordinates.
    /// Panel-contained styles use coordinates relative to their panel origin.
    var x: CGFloat
    var y: CGFloat

    private enum CodingKeys: String, CodingKey {
        case fontName
        case pointSize
        case colorHex
        case smoothRendering
        case x
        case y
    }

    init(fontName: String, pointSize: CGFloat, colorHex: String, x: CGFloat = 0, y: CGFloat = 0, smoothRendering: Bool = false) {
        self.fontName = fontName
        self.pointSize = pointSize
        self.colorHex = colorHex
        self.smoothRendering = smoothRendering
        self.x = x
        self.y = y
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fontName = try container.decode(String.self, forKey: .fontName)
        pointSize = try container.decode(CGFloat.self, forKey: .pointSize)
        colorHex = try container.decode(String.self, forKey: .colorHex)
        smoothRendering = try container.decodeIfPresent(Bool.self, forKey: .smoothRendering) ?? false
        x = try container.decodeIfPresent(CGFloat.self, forKey: .x) ?? 0
        y = try container.decodeIfPresent(CGFloat.self, forKey: .y) ?? 0
    }

    static var defaultFontName: String {
        silkscreenRegular
    }

    var color: NSColor { NSColor(hex: colorHex) ?? PixelPalette.cream }
}

enum DashboardStyleKey: String, CaseIterable {
    case clock
    case date
    case temperature
    case weatherCity
    case musicVisualizer
    case musicStatus
    case title
    case artist
    case runtime
    case agent
    case agentActivity
    case activeSessionTitle
    case activeSessionName
    case activeSessionUpdatedAt
    case recentSession
    case sessionContextPercent

    var displayName: String {
        switch self {
        case .clock: return "Clock"
        case .date: return "Date"
        case .temperature: return "Temperature"
        case .weatherCity: return "Weather · Left Edge"
        case .musicVisualizer: return "Music · Wave"
        case .musicStatus: return "Music · Now Playing"
        case .title: return "Music · Track"
        case .artist: return "Music · Artist"
        case .runtime: return "Runtime Status"
        case .agent: return "Hermes Agent"
        case .agentActivity: return "Hermes Agent · Activity"
        case .activeSessionTitle: return "Active Session · Header"
        case .activeSessionName: return "Active Session · Name"
        case .activeSessionUpdatedAt: return "Active Session · Last Conversation"
        case .recentSession: return "Recent Sessions"
        case .sessionContextPercent: return "Session Context Percent"
        }
    }

    /// Default anchor for the style row. For panel styles this is relative to
    /// the panel; the dashboard applies edits as a group offset.
    var defaultPosition: CGPoint {
        switch self {
        case .clock: return CGPoint(x: 42, y: 48)
        case .date: return CGPoint(x: 42, y: 186)
        case .temperature: return CGPoint(x: 66, y: 186)
        case .weatherCity: return CGPoint(x: 480, y: 186)
        case .musicVisualizer: return CGPoint(x: 42, y: 252)
        case .musicStatus: return CGPoint(x: 106, y: 252)
        case .title: return CGPoint(x: 42, y: 287)
        case .artist: return CGPoint(x: 42, y: 322)
        case .runtime: return CGPoint(x: 30, y: 22)
        case .agent: return CGPoint(x: 18, y: 18)
        case .agentActivity: return CGPoint(x: 288, y: 66)
        case .activeSessionTitle: return CGPoint(x: 24, y: 16)
        case .activeSessionName: return CGPoint(x: 24, y: 46)
        case .activeSessionUpdatedAt: return CGPoint(x: 500, y: 22)
        case .recentSession: return CGPoint(x: 12, y: 8)
        case .sessionContextPercent: return CGPoint(x: 0, y: 0)
        }
    }
}

struct DashboardStyles: Codable, Equatable {
    private var values: [String: TextStyle]

    static var defaults: DashboardStyles {
        return DashboardStyles(values: [
            DashboardStyleKey.clock.rawValue: TextStyle(fontName: "Pixelon", pointSize: 166, colorHex: "FDFAF6", x: 38, y: 27, smoothRendering: false),
            DashboardStyleKey.date.rawValue: TextStyle(fontName: "YuMincho +36p Kana", pointSize: 40, colorHex: "FAF3E8", x: 42, y: 186, smoothRendering: false),
            DashboardStyleKey.temperature.rawValue: TextStyle(fontName: "Pixelon", pointSize: 36, colorHex: "72EDF2", x: 220, y: 230, smoothRendering: true),
            DashboardStyleKey.weatherCity.rawValue: TextStyle(fontName: "Pixelon", pointSize: 20, colorHex: "64EBEE", x: 480, y: 186, smoothRendering: false),
            DashboardStyleKey.musicVisualizer.rawValue: TextStyle(fontName: "Pixelon", pointSize: 16, colorHex: "238FA4", x: 42, y: 252, smoothRendering: false),
            DashboardStyleKey.musicStatus.rawValue: TextStyle(fontName: "Pixelon", pointSize: 20, colorHex: "64EBEE", x: 106, y: 252, smoothRendering: false),
            DashboardStyleKey.title.rawValue: TextStyle(fontName: "Yuanti TC", pointSize: 24, colorHex: "F9F0E2", x: 42, y: 287, smoothRendering: true),
            DashboardStyleKey.artist.rawValue: TextStyle(fontName: "Yuanti SC", pointSize: 22, colorHex: "64EBEE", x: 42, y: 322, smoothRendering: true),
            DashboardStyleKey.runtime.rawValue: TextStyle(fontName: "Pixelon", pointSize: 39, colorHex: "FBF5ED", x: 30, y: 22, smoothRendering: true),
            DashboardStyleKey.agent.rawValue: TextStyle(fontName: "Zapf Dingbats", pointSize: 28, colorHex: "64EBEE", x: 18, y: 18, smoothRendering: false),
            DashboardStyleKey.agentActivity.rawValue: TextStyle(fontName: "Pixelon", pointSize: 14, colorHex: "F5EAD2", x: 288, y: 66, smoothRendering: true),
            DashboardStyleKey.activeSessionTitle.rawValue: TextStyle(fontName: "Pixelon", pointSize: 35, colorHex: "FDF9F4", x: 24, y: 10, smoothRendering: true),
            DashboardStyleKey.activeSessionName.rawValue: TextStyle(fontName: "HanziPen SC", pointSize: 21, colorHex: "F5EAD2", x: 24, y: 44, smoothRendering: true),
            DashboardStyleKey.activeSessionUpdatedAt.rawValue: TextStyle(fontName: "Pixelon", pointSize: 22, colorHex: "81EFF5", x: 957, y: 48, smoothRendering: true),
            DashboardStyleKey.recentSession.rawValue: TextStyle(fontName: "HanziPen SC", pointSize: 18, colorHex: "FAF3E8", x: 12, y: 3, smoothRendering: true),
            DashboardStyleKey.sessionContextPercent.rawValue: TextStyle(fontName: "Pixelon", pointSize: 20, colorHex: "72EDF2", x: 0, y: -3, smoothRendering: false)
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
            UserDefaults.standard.set(true, forKey: "didMigrateWeatherRightEdgeV2")
            UserDefaults.standard.set(true, forKey: "didMigrateWeatherLeftEdgeV3")
            return .defaults
        }
        var merged = DashboardStyles.defaults
        let shouldMigrateLegacyPixelStyles = !UserDefaults.standard.bool(forKey: "didMigrateLegacyPixelStyles")
        let shouldResetSmoothRendering = !UserDefaults.standard.bool(forKey: "didMigrateSmoothRenderingDefaults")
        let shouldMigrateMusicLayout = decoded.values[DashboardStyleKey.musicStatus.rawValue] == nil
        for key in DashboardStyleKey.allCases {
            if let saved = decoded.values[key.rawValue] {
                var migrated = saved
                // Styles saved before position editing do not have x/y keys.
                // Restore the corresponding design anchor instead of treating
                // the missing values as an intentional (0, 0) position.
                if migrated.x == 0 && migrated.y == 0 {
                    migrated.x = key.defaultPosition.x
                    migrated.y = key.defaultPosition.y
                }
                if shouldMigrateLegacyPixelStyles && migrated.fontName == TextStyle.builtInPixelFont {
                    migrated.fontName = (key == .clock || key == .title) ? TextStyle.silkscreenBold : TextStyle.silkscreenRegular
                }
                if shouldResetSmoothRendering {
                    migrated.smoothRendering = false
                }
                merged.values[key.rawValue] = migrated
            }
        }
        if shouldMigrateMusicLayout, var artist = merged.values[DashboardStyleKey.artist.rawValue] {
            artist.y += 70
            merged.values[DashboardStyleKey.artist.rawValue] = artist
        }
        if let legacyActiveSession = decoded.values["activeSession"] {
            var legacyTitle = legacyActiveSession
            var legacyName = legacyActiveSession
            if legacyTitle.x == 0 && legacyTitle.y == 0 {
                legacyTitle.x = DashboardStyleKey.activeSessionTitle.defaultPosition.x
                legacyTitle.y = DashboardStyleKey.activeSessionTitle.defaultPosition.y
                legacyName.x = DashboardStyleKey.activeSessionName.defaultPosition.x
                legacyName.y = DashboardStyleKey.activeSessionName.defaultPosition.y
            }
            if decoded.values[DashboardStyleKey.activeSessionTitle.rawValue] == nil {
                merged.values[DashboardStyleKey.activeSessionTitle.rawValue] = legacyTitle
            }
            if decoded.values[DashboardStyleKey.activeSessionName.rawValue] == nil {
                merged.values[DashboardStyleKey.activeSessionName.rawValue] = legacyName
            }
        }
        if shouldMigrateLegacyPixelStyles {
            UserDefaults.standard.set(true, forKey: "didMigrateLegacyPixelStyles")
        }
        if shouldResetSmoothRendering {
            UserDefaults.standard.set(true, forKey: "didMigrateSmoothRenderingDefaults")
        }
        if shouldResetSmoothRendering || shouldMigrateMusicLayout {
            merged.save()
        }
        return merged
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: "dashboardStyles")
    }
}

struct DashboardModulePosition: Codable, Equatable {
    var x: CGFloat
    var y: CGFloat
}

enum RuntimeIconKey: String, CaseIterable, Codable {
    case model, thinking, fastMode, provider, balance, reset, tokens

    var displayName: String {
        switch self {
        case .model: return "MODEL"
        case .thinking: return "THINKING"
        case .fastMode: return "FASTMODE"
        case .provider: return "PLAN"
        case .balance: return "BALANCE"
        case .reset: return "RESET"
        case .tokens: return "TOKENS"
        }
    }
}

struct RuntimeIconStyle: Codable, Equatable {
    /// Built-in pixel patterns are named pattern-0 through pattern-5. Project
    /// resources use a bundle: path and user-selected files use a file: path.
    var name: String
    var x: CGFloat
    var y: CGFloat
    var size: CGFloat

    private enum CodingKeys: String, CodingKey {
        case name, x, y, size
    }

    init(name: String, x: CGFloat = 28, y: CGFloat = 5, size: CGFloat = 24) {
        self.name = name
        self.x = x
        self.y = y
        self.size = size
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        x = try container.decodeIfPresent(CGFloat.self, forKey: .x) ?? 28
        y = try container.decodeIfPresent(CGFloat.self, forKey: .y) ?? 5
        size = try container.decodeIfPresent(CGFloat.self, forKey: .size) ?? 24
    }

    var pattern: Int {
        guard name.hasPrefix("pattern-"), let value = Int(name.dropFirst("pattern-".count)) else { return 0 }
        return min(max(value, 0), 5)
    }
}

struct DashboardLayout: Codable, Equatable {
    var padding: CGFloat
    var runtimeStatus: DashboardModulePosition
    var hermesAgent: DashboardModulePosition
    var activeSession: DashboardModulePosition
    var runtimeOpacity: CGFloat
    var agentOpacity: CGFloat
    var activeSessionOpacity: CGFloat
    var sessionCardOpacity: CGFloat
    var runtimeTitleSpacing: CGFloat
    var runtimeIconTitleSpacing: CGFloat
    var runtimeIcons: [String: RuntimeIconStyle]
    /// Missing entries use the automatic status color for that value.
    var runtimeValueColors: [String: String]

    private enum CodingKeys: String, CodingKey {
        case padding, runtimeStatus, hermesAgent, activeSession
        case runtimeOpacity, agentOpacity, activeSessionOpacity, sessionCardOpacity
        case runtimeTitleSpacing, runtimeIconTitleSpacing, runtimeIcons, runtimeValueColors
    }

    init(
        padding: CGFloat,
        runtimeStatus: DashboardModulePosition,
        hermesAgent: DashboardModulePosition,
        activeSession: DashboardModulePosition,
        runtimeOpacity: CGFloat,
        agentOpacity: CGFloat,
        activeSessionOpacity: CGFloat,
        sessionCardOpacity: CGFloat = 0.82,
        runtimeTitleSpacing: CGFloat = 18,
        runtimeIconTitleSpacing: CGFloat = 28,
        runtimeIcons: [String: RuntimeIconStyle] = DashboardLayout.defaultRuntimeIcons,
        runtimeValueColors: [String: String] = [:]
    ) {
        self.padding = padding
        self.runtimeStatus = runtimeStatus
        self.hermesAgent = hermesAgent
        self.activeSession = activeSession
        self.runtimeOpacity = runtimeOpacity
        self.agentOpacity = agentOpacity
        self.activeSessionOpacity = activeSessionOpacity
        self.sessionCardOpacity = sessionCardOpacity
        self.runtimeTitleSpacing = runtimeTitleSpacing
        self.runtimeIconTitleSpacing = runtimeIconTitleSpacing
        self.runtimeIcons = runtimeIcons
        self.runtimeValueColors = runtimeValueColors
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        padding = try container.decode(CGFloat.self, forKey: .padding)
        runtimeStatus = try container.decode(DashboardModulePosition.self, forKey: .runtimeStatus)
        hermesAgent = try container.decode(DashboardModulePosition.self, forKey: .hermesAgent)
        activeSession = try container.decode(DashboardModulePosition.self, forKey: .activeSession)
        runtimeOpacity = try container.decode(CGFloat.self, forKey: .runtimeOpacity)
        agentOpacity = try container.decode(CGFloat.self, forKey: .agentOpacity)
        activeSessionOpacity = try container.decode(CGFloat.self, forKey: .activeSessionOpacity)
        sessionCardOpacity = try container.decodeIfPresent(CGFloat.self, forKey: .sessionCardOpacity) ?? 0.82
        runtimeTitleSpacing = try container.decodeIfPresent(CGFloat.self, forKey: .runtimeTitleSpacing) ?? 18
        runtimeIconTitleSpacing = try container.decodeIfPresent(CGFloat.self, forKey: .runtimeIconTitleSpacing) ?? 28
        runtimeIcons = try container.decodeIfPresent([String: RuntimeIconStyle].self, forKey: .runtimeIcons) ?? DashboardLayout.defaultRuntimeIcons
        runtimeValueColors = try container.decodeIfPresent([String: String].self, forKey: .runtimeValueColors) ?? [:]
        for key in RuntimeIconKey.allCases where runtimeIcons[key.rawValue] == nil {
            runtimeIcons[key.rawValue] = DashboardLayout.defaultRuntimeIcons[key.rawValue]
        }
    }

    static let defaultRuntimeIcons: [String: RuntimeIconStyle] = [
        RuntimeIconKey.model.rawValue: RuntimeIconStyle(name: "bundle:RuntimeStatusIcons/01-model.png"),
        RuntimeIconKey.thinking.rawValue: RuntimeIconStyle(name: "bundle:RuntimeStatusIcons/02-thinking.png"),
        RuntimeIconKey.fastMode.rawValue: RuntimeIconStyle(name: "bundle:RuntimeStatusIcons/03-fastmode.png"),
        RuntimeIconKey.provider.rawValue: RuntimeIconStyle(name: "bundle:RuntimeStatusIcons/04-plan.png"),
        RuntimeIconKey.balance.rawValue: RuntimeIconStyle(name: "bundle:RuntimeStatusIcons/07-plan-balance.png"),
        RuntimeIconKey.reset.rawValue: RuntimeIconStyle(name: "bundle:RuntimeStatusIcons/08-next-reset.png"),
        RuntimeIconKey.tokens.rawValue: RuntimeIconStyle(name: "bundle:RuntimeStatusIcons/06-tokens.png")
    ]

    static let defaults = DashboardLayout(
        padding: 12,
        runtimeStatus: DashboardModulePosition(x: 770, y: 20),
        hermesAgent: DashboardModulePosition(x: 16, y: 416),
        activeSession: DashboardModulePosition(x: 618, y: 416),
        runtimeOpacity: 0.2,
        agentOpacity: 0.2,
        activeSessionOpacity: 0.2,
        sessionCardOpacity: 0.0,
        runtimeTitleSpacing: 48,
        runtimeIconTitleSpacing: 10,
        runtimeIcons: DashboardLayout.defaultRuntimeIcons
    )

    static func load() -> DashboardLayout {
        guard let data = UserDefaults.standard.data(forKey: "dashboardLayout"),
              var decoded = try? JSONDecoder().decode(DashboardLayout.self, from: data) else {
            return .defaults
        }
        // Migrate the anchors used by the previous 2:1 and 7:9 compositions.
        // Other coordinates are user edits and remain untouched.
        if [492, 444, 327, 417, 420].contains(decoded.hermesAgent.y) { decoded.hermesAgent.y = 416 }
        if [492, 444, 327, 417, 420].contains(decoded.activeSession.y) { decoded.activeSession.y = 416 }
        let migrationKey = "didMigrateBundledRuntimeIcons20260904"
        if !UserDefaults.standard.bool(forKey: migrationKey) {
            for key in RuntimeIconKey.allCases {
                guard var current = decoded.runtimeIcons[key.rawValue], current.name.hasPrefix("pattern-"),
                      let bundled = defaultRuntimeIcons[key.rawValue] else { continue }
                current.name = bundled.name
                decoded.runtimeIcons[key.rawValue] = current
            }
            decoded.save()
            UserDefaults.standard.set(true, forKey: migrationKey)
        }
        return decoded
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: "dashboardLayout")
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
        self.init(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }

    var hexString: String {
        guard let rgb = usingColorSpace(.sRGB) else { return "FFFFFF" }
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

enum WeatherSource: String, CaseIterable, Codable {
    case qweather
    case openMeteo
    case macOSWeather

    var displayName: String {
        switch self {
        case .qweather: return "QWeather / 和风天气"
        case .openMeteo: return "Open-Meteo"
        case .macOSWeather: return "macOS Weather"
        }
    }
}

enum WeatherIconSet: String, CaseIterable, Codable {
    case standard
    case referenceStyle

    var displayName: String {
        switch self {
        case .standard: return "Standard"
        case .referenceStyle: return "Reference style"
        }
    }
}

private enum WeatherCredentialStore {
    private static let service = "com.hermes.dashboard.qweather"
    private static let account = "api-key"

    static func loadAPIKey() -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else { return "" }
        return value
    }

    static func saveAPIKey(_ value: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        guard !value.isEmpty else {
            SecItemDelete(query as CFDictionary)
            return
        }
        let data = Data(value.utf8)
        let attributes: [String: Any] = [kSecValueData as String: data]
        if SecItemUpdate(query as CFDictionary, attributes as CFDictionary) == errSecItemNotFound {
            var newItem = query
            newItem[kSecValueData as String] = data
            newItem[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(newItem as CFDictionary, nil)
        }
    }
}

struct WeatherSettings: Codable, Equatable {
    var source: WeatherSource
    var iconSet: WeatherIconSet
    var apiHost: String
    var apiKey: String
    var city: String
    var refreshInterval: TimeInterval
    var iconX: CGFloat
    var iconY: CGFloat
    var iconSize: CGFloat

    private enum CodingKeys: String, CodingKey {
        case source, iconSet, apiHost, city, refreshInterval, iconX, iconY, iconSize
    }

    init(source: WeatherSource, iconSet: WeatherIconSet, apiHost: String, apiKey: String, city: String, refreshInterval: TimeInterval, iconX: CGFloat = 560, iconY: CGFloat = 48, iconSize: CGFloat = 128) {
        self.source = source
        self.iconSet = iconSet
        self.apiHost = apiHost
        self.apiKey = apiKey
        self.city = city
        self.refreshInterval = refreshInterval
        self.iconX = iconX
        self.iconY = iconY
        self.iconSize = iconSize
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        source = try container.decodeIfPresent(WeatherSource.self, forKey: .source) ?? .qweather
        iconSet = try container.decodeIfPresent(WeatherIconSet.self, forKey: .iconSet) ?? .standard
        apiHost = try container.decodeIfPresent(String.self, forKey: .apiHost) ?? ""
        city = try container.decodeIfPresent(String.self, forKey: .city) ?? "Fuzhou"
        refreshInterval = try container.decodeIfPresent(TimeInterval.self, forKey: .refreshInterval) ?? 1800
        iconX = try container.decodeIfPresent(CGFloat.self, forKey: .iconX) ?? 560
        iconY = try container.decodeIfPresent(CGFloat.self, forKey: .iconY) ?? 48
        iconSize = try container.decodeIfPresent(CGFloat.self, forKey: .iconSize) ?? 128
        apiKey = ""
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(source, forKey: .source)
        try container.encode(iconSet, forKey: .iconSet)
        try container.encode(apiHost, forKey: .apiHost)
        try container.encode(city, forKey: .city)
        try container.encode(refreshInterval, forKey: .refreshInterval)
        try container.encode(iconX, forKey: .iconX)
        try container.encode(iconY, forKey: .iconY)
        try container.encode(iconSize, forKey: .iconSize)
    }

    static let defaults = WeatherSettings(
        source: .qweather,
        iconSet: .standard,
        apiHost: "",
        apiKey: "",
        city: "Fuzhou",
        refreshInterval: 1800
    )

    static func load() -> WeatherSettings {
        var value: WeatherSettings
        if let data = UserDefaults.standard.data(forKey: "weatherSettings"),
           let stored = try? JSONDecoder().decode(WeatherSettings.self, from: data) {
            value = stored
        } else {
            value = .defaults
            if let legacyCity = UserDefaults.standard.string(forKey: "weatherCity"), !legacyCity.isEmpty {
                value.city = legacyCity
            }
        }
        // Keychain reads may display a macOS authorization prompt after an
        // ad-hoc rebuild. Load the credential asynchronously from the model's
        // start path so that Music and Runtime polling are never blocked here.
        value.apiKey = ""
        return value
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: "weatherSettings")
        }
        WeatherCredentialStore.saveAPIKey(apiKey)
    }
}

struct PlanUsageSettings: Codable, Equatable {
    var planLabel: String
    var limitID: String
    var codexExecutable: String
    var refreshInterval: TimeInterval
    var lastRemainingPercent: Int?
    var lastResetAt: Date?
    var lastPlanType: String?
    var lastEmail: String?

    static var defaults: PlanUsageSettings {
        let candidates = ["/opt/homebrew/bin/codex", "/usr/local/bin/codex", "/usr/bin/codex"]
        let executable = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) ?? "codex"
        return PlanUsageSettings(
            planLabel: "",
            limitID: "codex",
            codexExecutable: executable,
            refreshInterval: 600,
            lastRemainingPercent: nil,
            lastResetAt: nil,
            lastPlanType: nil,
            lastEmail: nil
        )
    }

    static func load() -> PlanUsageSettings {
        guard let data = UserDefaults.standard.data(forKey: "planUsageSettings"),
              var value = try? JSONDecoder().decode(PlanUsageSettings.self, from: data) else { return .defaults }
        value.refreshInterval = 600
        return value
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: "planUsageSettings")
    }
}

struct PlanUsageSnapshot: Equatable {
    var authenticated: Bool
    var planType: String?
    var email: String?
    var remainingPercent: Int?
    var resetsAt: Date?
    var windowDurationMinutes: Int?
    var status: String

    static func cached(from settings: PlanUsageSettings) -> PlanUsageSnapshot {
        PlanUsageSnapshot(
            authenticated: settings.lastPlanType != nil,
            planType: settings.lastPlanType,
            email: settings.lastEmail,
            remainingPercent: settings.lastRemainingPercent,
            resetsAt: settings.lastResetAt,
            windowDurationMinutes: settings.lastRemainingPercent == nil ? nil : 10_080,
            status: settings.lastRemainingPercent == nil ? "NOT CONNECTED" : "CACHED"
        )
    }

    func planLabel(override: String) -> String {
        let custom = override.trimmingCharacters(in: .whitespacesAndNewlines)
        if !custom.isEmpty { return custom.uppercased() }
        guard let planType, !planType.isEmpty else { return "CHATGPT" }
        return "GPT " + planType.replacingOccurrences(of: "_", with: " ").uppercased()
    }

    var allowanceText: String {
        guard let remainingPercent else { return authenticated ? "UNAVAILABLE" : "SIGN IN" }
        if windowDurationMinutes == 10_080 { return "\(remainingPercent)% WEEKLY" }
        return "\(remainingPercent)% REMAINING"
    }

    func resetCountdown(now: Date = Date()) -> String {
        guard let resetsAt else { return "UNAVAILABLE" }
        let seconds = max(Int(resetsAt.timeIntervalSince(now)), 0)
        if seconds == 0 { return "DUE NOW" }
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60
        if days > 0 { return "\(days)D \(hours)H" }
        if hours > 0 { return "\(hours)H \(minutes)M" }
        return "\(max(minutes, 1))M"
    }
}

enum AgentState: String {
    case working
    case thinking
    case outputting
    case done
    case idle
    case error

    init(rawValue: String) {
        switch rawValue.lowercased() {
        case "working", "running", "executing": self = .working
        case "thinking", "planning": self = .thinking
        case "outputting", "outputing", "streaming", "generating": self = .outputting
        case "done", "complete", "completed", "success": self = .done
        case "error", "failed": self = .error
        default: self = .idle
        }
    }

    var label: String {
        switch self {
        case .working: return "WORKING"
        case .thinking: return "THINKING"
        case .outputting: return "OUTPUTTING"
        case .done: return "DONE"
        case .idle: return "DONE"
        case .error: return "ERROR"
        }
    }
}

enum AgentAnimationAction: String {
    case typing = "01-typing"
    case doneOK = "02-done-ok"
    case thinking = "03-thinking"
    case music = "04-music"
    case tired = "05-tired"
    case coffee = "06-coffee"

    var duration: TimeInterval {
        switch self {
        case .typing: return 1.32
        case .doneOK: return 3.01
        case .thinking: return 2.45
        case .music: return 1.44
        case .tired: return 2.78
        case .coffee: return 8.54
        }
    }
}

struct AgentAnimationPresentation {
    var action: AgentAnimationAction
    var elapsed: TimeInterval
}

enum WeatherCondition {
    case clear
    case partlyCloudy
    case cloudy
    case fog
    case drizzle
    case rain
    case snow
    case thunderstorm
    case unknown

    var displayName: String {
        switch self {
        case .clear: return "CLEAR"
        case .partlyCloudy: return "PARTLY"
        case .cloudy: return "CLOUDY"
        case .fog: return "FOG"
        case .drizzle: return "DRIZZLE"
        case .rain: return "RAIN"
        case .snow: return "SNOW"
        case .thunderstorm: return "STORM"
        case .unknown: return "UNKNOWN"
        }
    }
}

struct WeatherSnapshot {
    var temperature: String
    var condition: WeatherCondition
    var location: String
    var isLive: Bool
    var attribution: String

    init(temperature: String, condition: WeatherCondition, location: String, isLive: Bool, attribution: String = "") {
        self.temperature = temperature
        self.condition = condition
        self.location = location
        self.isLive = isLive
        self.attribution = attribution
    }

    static let demo = WeatherSnapshot(
        temperature: "24°C",
        condition: .partlyCloudy,
        location: "",
        isLive: false,
        attribution: ""
    )
}

struct MusicSnapshot {
    var artist: String
    var title: String
    var album: String
    var isPlaying: Bool
    var position: Double
    var duration: Double

    func preservingTrack(from previous: MusicSnapshot) -> MusicSnapshot {
        guard title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !previous.title.isEmpty else { return self }
        var retained = self
        retained.title = previous.title
        retained.artist = previous.artist
        retained.album = previous.album
        return retained
    }

    static let notPlaying = MusicSnapshot(
        artist: "",
        title: "",
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
    var contextPercent: Int = 0
}

enum AgentActivityKind: String {
    case think
    case tool
    case files
    case search
    case result
    case reply
    case status
    case approval
    case error

    var tag: String {
        switch self {
        case .think: return "[THINKING]"
        case .tool: return "[TOOLS]"
        case .files: return "[FILES]"
        case .search: return "[SEARCH]"
        case .result: return "[RESULT]"
        case .reply: return "[OUTPUT]"
        case .status: return "[STATUS]"
        case .approval: return "[APPROVAL]"
        case .error: return "[ERROR]"
        }
    }
}

struct ActivitySummaryLayout {
    static let panelSize = CGSize(width: 318, height: 216)

    var style: TextStyle
    var width: CGFloat
    var height: CGFloat

    var lineHeight: CGFloat { max(style.pointSize + 6, 16) }
    var maxLines: Int { max(Int(height / lineHeight), 1) }
    var approximateCharactersPerLine: Int {
        let glyphWidth = max(PixelPainter.textWidth("总结内容", style: style) / 4, 1)
        return max(Int((width - 4) / glyphWidth), 8)
    }
    var approximateCharacterCapacity: Int {
        max(approximateCharactersPerLine * maxLines - AgentActivityKind.reply.tag.count - 1, 24)
    }
    var signature: String {
        "\(style.fontName)|\(Int(style.pointSize.rounded()))|\(Int(width.rounded()))x\(Int(height.rounded()))"
    }
}

struct AgentActivityEvent {
    var id: String
    var kind: AgentActivityKind
    var text: String
    var summarizeBeforeDisplay: Bool

    init(id: String = "", kind: AgentActivityKind, text: String, summarizeBeforeDisplay: Bool = false) {
        self.id = id
        self.kind = kind
        self.text = text
        self.summarizeBeforeDisplay = summarizeBeforeDisplay
    }
}

struct RuntimeStatus {
    var source: RuntimeSource
    var model: String
    var thinking: String
    var fastMode: Bool
    var provider: String
    var balance: String
    var balanceValue: Double?
    var resetCountdown: String = "UNAVAILABLE"
    var tokenPercent: Int
    var todayTokens: Int = 0
    var hasTodayTokenData: Bool = false
    var activeSession: String
    var elapsed: String
    var contextPercent: Int
    var agentState: AgentState
    var sessions: [SessionInfo]
    var activityLog: [AgentActivityEvent]
    var isLive: Bool
    var hasModelData: Bool
    var hasContextData: Bool

    func automaticValueColor(for key: RuntimeIconKey) -> NSColor {
        switch key {
        case .thinking:
            switch thinking.lowercased() {
            case "low", "minimal": return PixelPalette.green
            case "medium", "med": return PixelPalette.yellow
            case "high": return PixelPalette.orange
            case "xhigh", "ultra", "max": return PixelPalette.violet
            default: return PixelPalette.cyan
            }
        case .balance:
            guard let balanceValue else { return PixelPalette.orange }
            if balanceValue >= 50 { return PixelPalette.green }
            if balanceValue >= 20 { return PixelPalette.yellow }
            return PixelPalette.red
        case .fastMode: return fastMode ? PixelPalette.cyan : PixelPalette.orange
        case .reset: return PixelPalette.violet
        default: return PixelPalette.cyan
        }
    }

    static func demo(source: RuntimeSource) -> RuntimeStatus {
        RuntimeStatus(
            source: source,
            model: "GPT-5",
            thinking: "HIGH",
            fastMode: true,
            provider: "OPENAI",
            balance: "$18.42",
            balanceValue: 18.42,
            tokenPercent: 72,
            todayTokens: 0,
            hasTodayTokenData: false,
            activeSession: "Refactor telemetry pipeline",
            elapsed: "08:41",
            contextPercent: 68,
            agentState: .working,
            sessions: [
                SessionInfo(title: "Build dashboard shell", progress: 100, status: "DONE", updatedAt: "18:32"),
                SessionInfo(title: "Tune pixel avatar", progress: 82, status: "", updatedAt: "17:05"),
                SessionInfo(title: "API health check", progress: 46, status: "", updatedAt: "15:47"),
                SessionInfo(title: "Write release notes", progress: 24, status: "", updatedAt: "13:22"),
                SessionInfo(title: "Review telemetry output", progress: 0, status: "", updatedAt: "12:10")
            ],
            activityLog: [
                AgentActivityEvent(id: "demo-status", kind: .status, text: "等待代理任务"),
                AgentActivityEvent(id: "demo-thinking", kind: .think, text: "分析仪表盘布局"),
                AgentActivityEvent(id: "demo-tool", kind: .tool, text: "检查 Git 状态"),
                AgentActivityEvent(id: "demo-result", kind: .result, text: "工作区检查完成"),
                AgentActivityEvent(id: "demo-output", kind: .reply, text: "仪表盘已准备完成")
            ],
            isLive: false,
            hasModelData: false,
            hasContextData: false
        )
    }

    func preservingTransientData(from previous: RuntimeStatus) -> RuntimeStatus {
        guard previous.source == source else { return self }
        var merged = self
        let normalizedModel = model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !hasModelData || normalizedModel.isEmpty || normalizedModel == "custom" {
            merged.model = previous.model
        }
        if !hasContextData {
            merged.contextPercent = previous.contextPercent
            merged.tokenPercent = previous.tokenPercent
            merged.sessions = previous.sessions
        }
        if !hasTodayTokenData {
            merged.todayTokens = previous.todayTokens
            merged.hasTodayTokenData = previous.hasTodayTokenData
        }
        if activeSession.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            merged.activeSession = previous.activeSession
        }
        if activityLog.isEmpty {
            merged.activityLog = previous.activityLog
        }
        return merged
    }
}

final class DashboardModel: NSObject {
    private(set) var weather: WeatherSnapshot = .demo
    private(set) var music: MusicSnapshot = .notPlaying
    private(set) var runtime: RuntimeStatus
    private(set) var wallpaperPath: String?
    private(set) var assetFolderPath: String?
    private(set) var styles: DashboardStyles
    private(set) var layout: DashboardLayout
    private(set) var planUsageSettings: PlanUsageSettings
    private(set) var planUsage: PlanUsageSnapshot
    private(set) var weatherSettings: WeatherSettings
    private(set) var assetStore: DashboardAssetStore
    private(set) var streamedActivityLog: [AgentActivityEvent] = []
    private(set) var displayedTodayTokens = 0
    var weatherCity: String { weatherSettings.city }
    var usesWeatherLeftEdge: Bool { UserDefaults.standard.bool(forKey: "didMigrateWeatherLeftEdgeV3") }
    var onChange: (() -> Void)?

    var runtimeSource: RuntimeSource {
        didSet {
            UserDefaults.standard.set(runtimeSource.rawValue, forKey: Keys.runtimeSource)
            resetActivityStream(for: runtimeSource)
            if runtimeSource != .codex { updateTodayTokensTarget(0, hasData: true) }
            refreshRuntime()
        }
    }

    private enum Keys {
        static let runtimeSource = "runtimeSource"
        static let wallpaperPath = "wallpaperPath"
        static let wallpaperCleared = "wallpaperCleared"
        static let assetFolderPath = "assetFolderPath"
        static let didPreferHermesRuntime = "didPreferHermesRuntime"
    }

    private static var bundledWallpaperPath: String? {
        Bundle.main.url(forResource: "kirby_s_chill_land", withExtension: "gif")?.path
    }

    private let weatherService = SystemWeatherService()
    private let musicService = AppleMusicService()
    private let runtimeService = RuntimeStatusService()
    private let planUsageService = CodexPlanUsageService()
    private var refreshTimer: Timer?
    private var planUsageTimer: Timer?
    private var weatherTimer: Timer?
    private var activityStreamTimer: Timer?
    private var tokenAnimationTimer: Timer?
    private var lastBalanceRefreshAttempt: Date?
    private var lastResetRefreshAttempt: Date?
    private var planUsageRequestID: UUID?
    private var activityStreamSource: RuntimeSource?
    private var activityQueue: [AgentActivityEvent] = []
    private var activeActivity: (event: AgentActivityEvent, characters: [Character], revealed: Int)?
    private var completedActivityIDs = Set<String>()
    private var activityPauseTicks = 0
    private var weatherCredentialLoadID: UUID?
    private var agentAnimationAction: AgentAnimationAction = .typing
    private var agentAnimationStartedAt = CACurrentMediaTime()
    private var observedAgentState: AgentState?

    override init() {
        var storedSource = UserDefaults.standard.string(forKey: Keys.runtimeSource)
            .flatMap(RuntimeSource.init(rawValue:)) ?? .hermes
        if storedSource == .codex && !UserDefaults.standard.bool(forKey: Keys.didPreferHermesRuntime) {
            storedSource = .hermes
            UserDefaults.standard.set(RuntimeSource.hermes.rawValue, forKey: Keys.runtimeSource)
            UserDefaults.standard.set(true, forKey: Keys.didPreferHermesRuntime)
        }
        runtimeSource = storedSource
        runtime = RuntimeStatus.demo(source: storedSource)
        if let storedWallpaperPath = UserDefaults.standard.string(forKey: Keys.wallpaperPath) {
            wallpaperPath = storedWallpaperPath
        } else if UserDefaults.standard.bool(forKey: Keys.wallpaperCleared) {
            wallpaperPath = nil
        } else {
            wallpaperPath = Self.bundledWallpaperPath
        }
        assetFolderPath = UserDefaults.standard.string(forKey: Keys.assetFolderPath)
        styles = DashboardStyles.load()
        layout = DashboardLayout.load()
        planUsageSettings = PlanUsageSettings.load()
        planUsage = PlanUsageSnapshot.cached(from: planUsageSettings)
        weatherSettings = WeatherSettings.load()
        assetStore = DashboardAssetStore(folderURL: assetFolderPath.map(URL.init(fileURLWithPath:)) ?? Bundle.main.resourceURL)
        super.init()
    }

    func start() {
        loadWeatherCredential()
        scheduleActivityStreamTimer()
        refreshAll()
        refreshPlanUsage(updateBalance: true, updateReset: true)
        schedulePlanUsageTimer()
        scheduleWeatherTimer()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.refreshDynamicData()
        }
    }

    func stop() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        planUsageTimer?.invalidate()
        planUsageTimer = nil
        weatherTimer?.invalidate()
        weatherTimer = nil
        activityStreamTimer?.invalidate()
        activityStreamTimer = nil
        tokenAnimationTimer?.invalidate()
        tokenAnimationTimer = nil
    }

    func setWallpaper(url: URL?) {
        wallpaperPath = url?.path
        if let path = wallpaperPath {
            UserDefaults.standard.set(path, forKey: Keys.wallpaperPath)
            UserDefaults.standard.removeObject(forKey: Keys.wallpaperCleared)
        } else {
            UserDefaults.standard.removeObject(forKey: Keys.wallpaperPath)
            UserDefaults.standard.set(true, forKey: Keys.wallpaperCleared)
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
        assetStore = DashboardAssetStore(folderURL: url ?? Bundle.main.resourceURL)
        notifyChange()
    }

    func updateStyle(_ style: TextStyle, for key: DashboardStyleKey) {
        styles.setStyle(style, for: key)
        styles.save()
        notifyChange()
    }

    func migrateWeatherLeftEdge(to leftEdge: CGFloat) {
        guard !usesWeatherLeftEdge else { return }
        var style = styles.style(for: .weatherCity)
        style.x = leftEdge
        styles.setStyle(style, for: .weatherCity)
        styles.save()
        UserDefaults.standard.set(true, forKey: "didMigrateWeatherLeftEdgeV3")
    }

    func resetStyles() {
        styles = .defaults
        styles.save()
        notifyChange()
    }

    func updateLayout(_ newLayout: DashboardLayout) {
        layout = newLayout
        layout.save()
        notifyChange()
    }

    func runtimeValueColor(for key: RuntimeIconKey) -> NSColor {
        layout.runtimeValueColors[key.rawValue].flatMap { NSColor(hex: $0) }
            ?? runtime.automaticValueColor(for: key)
    }

    func updatePlanUsageSettings(_ settings: PlanUsageSettings) {
        var updated = settings
        updated.planLabel = updated.planLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.limitID = updated.limitID.trimmingCharacters(in: .whitespacesAndNewlines)
        if updated.limitID.isEmpty { updated.limitID = "codex" }
        updated.codexExecutable = updated.codexExecutable.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.refreshInterval = 600
        planUsageSettings = updated
        updated.save()
        schedulePlanUsageTimer()
        refreshPlanUsage(updateBalance: true, updateReset: true)
        applyPlanUsageToRuntime()
        notifyChange()
    }

    func beginPlanOAuth(completion: @escaping (String) -> Void) {
        planUsageService.startOAuth(executable: planUsageSettings.codexExecutable) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success:
                    completion("Authorization complete")
                    self.refreshPlanUsage(updateBalance: true, updateReset: true)
                case .failure(let error):
                    completion(error.localizedDescription)
                }
            }
        }
    }

    func updateWeatherSettings(_ settings: WeatherSettings) {
        weatherCredentialLoadID = nil
        var updated = settings
        updated.apiHost = updated.apiHost.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.apiKey = updated.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.city = updated.city.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.refreshInterval = min(max(updated.refreshInterval, 60), 86_400)
        updated.iconX = min(max(updated.iconX, -256), 1_280)
        updated.iconY = min(max(updated.iconY, -256), 720)
        updated.iconSize = min(max(updated.iconSize, 24), 384)
        weatherSettings = updated
        updated.save()
        scheduleWeatherTimer()
        refreshWeather()
    }

    private func loadWeatherCredential() {
        let requestID = UUID()
        weatherCredentialLoadID = requestID
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let apiKey = WeatherCredentialStore.loadAPIKey()
            DispatchQueue.main.async {
                guard let self, self.weatherCredentialLoadID == requestID else { return }
                self.weatherCredentialLoadID = nil
                self.weatherSettings.apiKey = apiKey
                self.refreshWeather()
                self.notifyChange()
            }
        }
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
        weatherService.fetch(settings: weatherSettings) { [weak self] snapshot in
            guard let self else { return }
            self.weather = snapshot
            self.notifyChange()
        }
    }

    private func refreshMusic() {
        musicService.fetch { [weak self] snapshot in
            guard let self else { return }
            let previous = self.music
            self.music = snapshot.preservingTrack(from: previous)
            self.handleMusicAnimationChange(from: previous, to: self.music, at: CACurrentMediaTime())
            self.notifyChange()
        }
    }

    fileprivate func refreshRuntime() {
        let source = runtimeSource
        let activityStyle = styles.style(for: .agentActivity)
        let activityLayout = ActivitySummaryLayout(
            style: activityStyle,
            width: ActivitySummaryLayout.panelSize.width,
            height: ActivitySummaryLayout.panelSize.height
        )
        runtimeService.fetch(source: source, activityLayout: activityLayout) { [weak self] status in
            guard let self else { return }
            guard source == self.runtimeSource else { return }
            self.runtime = status.preservingTransientData(from: self.runtime)
            self.handleAgentStateChange(to: self.runtime.agentState, at: CACurrentMediaTime())
            self.updateTodayTokensTarget(self.runtime.todayTokens, hasData: self.runtime.hasTodayTokenData)
            self.updateActivityTarget(self.runtime.activityLog, source: source)
            self.applyPlanUsageToRuntime()
            self.notifyChange()
        }
    }

    func agentAnimation(at time: TimeInterval) -> AgentAnimationPresentation {
        advanceAgentAnimationIfNeeded(at: time)
        return AgentAnimationPresentation(
            action: agentAnimationAction,
            elapsed: max(time - agentAnimationStartedAt, 0)
        )
    }

    private var agentHasActiveTask: Bool {
        switch runtime.agentState {
        case .working, .thinking, .outputting, .error: return true
        case .done, .idle: return false
        }
    }

    private func handleAgentStateChange(to state: AgentState, at time: TimeInterval) {
        let previous = observedAgentState
        observedAgentState = state

        switch state {
        case .working, .outputting:
            setAgentAnimation(.typing, at: time)
        case .thinking:
            setAgentAnimation(.thinking, at: time)
        case .error:
            setAgentAnimation(.tired, at: time)
        case .done, .idle:
            if let previous, [.working, .thinking, .outputting].contains(previous) {
                setAgentAnimation(.doneOK, at: time, restart: true)
            } else if previous == .error {
                chooseIdleAgentAnimation(at: time)
            } else if previous == nil {
                setAgentAnimation(.typing, at: time)
            }
        }
    }

    private func handleMusicAnimationChange(from previous: MusicSnapshot, to current: MusicSnapshot, at time: TimeInterval) {
        guard !agentHasActiveTask else { return }
        if !previous.isPlaying && current.isPlaying {
            // Opening a player or explicitly resuming playback starts one
            // listening cycle. A title change while already playing does not.
            setAgentAnimation(.music, at: time, restart: true)
        } else if !current.isPlaying && agentAnimationAction == .music {
            chooseIdleAgentAnimation(at: time, allowMusic: false)
        }
    }

    private func advanceAgentAnimationIfNeeded(at time: TimeInterval) {
        guard !agentHasActiveTask else { return }
        let elapsed = time - agentAnimationStartedAt
        guard elapsed >= agentAnimationAction.duration else { return }
        chooseIdleAgentAnimation(at: time)
    }

    private func chooseIdleAgentAnimation(at time: TimeInterval, allowMusic: Bool = true) {
        if allowMusic && music.isPlaying {
            let action: AgentAnimationAction = Int.random(in: 0..<5) == 0 ? .music : .typing
            setAgentAnimation(action, at: time, restart: true)
        } else if Int.random(in: 0..<6) == 0 {
            setAgentAnimation(.coffee, at: time, restart: true)
        } else {
            setAgentAnimation(.typing, at: time, restart: true)
        }
    }

    private func setAgentAnimation(_ action: AgentAnimationAction, at time: TimeInterval, restart: Bool = false) {
        guard restart || agentAnimationAction != action else { return }
        agentAnimationAction = action
        agentAnimationStartedAt = time
    }

    private func scheduleActivityStreamTimer() {
        activityStreamTimer?.invalidate()
        activityStreamTimer = Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { [weak self] _ in
            self?.advanceActivityStream()
        }
    }

    private func resetActivityStream(for source: RuntimeSource) {
        activityStreamSource = source
        activityQueue.removeAll()
        activeActivity = nil
        completedActivityIDs.removeAll()
        streamedActivityLog.removeAll()
        activityPauseTicks = 0
        notifyChange()
    }

    private func updateActivityTarget(_ events: [AgentActivityEvent], source: RuntimeSource) {
        if activityStreamSource != source { resetActivityStream(for: source) }
        let target = Array(events.suffix(14).enumerated()).map { index, event -> AgentActivityEvent in
            var normalized = event
            if normalized.id.isEmpty {
                normalized.id = "\(source.rawValue):\(index):\(event.kind.rawValue):\(event.text)"
            }
            return normalized
        }
        let desiredIDs = Set(target.map(\.id))
        streamedActivityLog.removeAll { !desiredIDs.contains($0.id) }
        activityQueue.removeAll { !desiredIDs.contains($0.id) }
        if let activeActivity, !desiredIDs.contains(activeActivity.event.id) {
            self.activeActivity = nil
        }
        completedActivityIDs.formIntersection(desiredIDs)

        var knownIDs = Set(streamedActivityLog.map(\.id))
        knownIDs.formUnion(activityQueue.map(\.id))
        if let activeActivity { knownIDs.insert(activeActivity.event.id) }
        knownIDs.formUnion(completedActivityIDs)
        for event in target where !knownIDs.contains(event.id) {
            activityQueue.append(event)
            knownIDs.insert(event.id)
        }
    }

    private func advanceActivityStream() {
        if activityPauseTicks > 0 {
            activityPauseTicks -= 1
            return
        }
        if activeActivity == nil {
            guard !activityQueue.isEmpty else { return }
            let event = activityQueue.removeFirst()
            let characters = Array(event.text)
            var visible = event
            visible.text = ""
            streamedActivityLog.append(visible)
            if streamedActivityLog.count > 14 {
                streamedActivityLog.removeFirst(streamedActivityLog.count - 14)
            }
            activeActivity = (event, characters, 0)
            notifyChange()
            if characters.isEmpty {
                completedActivityIDs.insert(event.id)
                activeActivity = nil
                activityPauseTicks = 2
            }
            return
        }

        guard var typing = activeActivity else { return }
        typing.revealed = min(typing.revealed + 4, typing.characters.count)
        if let index = streamedActivityLog.lastIndex(where: { $0.id == typing.event.id }) {
            streamedActivityLog[index].text = String(typing.characters.prefix(typing.revealed))
        }
        if typing.revealed >= typing.characters.count {
            completedActivityIDs.insert(typing.event.id)
            activeActivity = nil
            activityPauseTicks = 1
        } else {
            activeActivity = typing
        }
        notifyChange()
    }

    private func schedulePlanUsageTimer() {
        planUsageTimer?.invalidate()
        planUsageTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.refreshPlanUsageIfNeeded()
        }
    }

    private func scheduleWeatherTimer() {
        weatherTimer?.invalidate()
        let interval = min(max(weatherSettings.refreshInterval, 60), 86_400)
        weatherTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.refreshWeather()
        }
    }

    private func refreshPlanUsageIfNeeded(now: Date = Date()) {
        let balanceDue = lastBalanceRefreshAttempt.map { now.timeIntervalSince($0) >= 600 } ?? true
        let resetDue = lastResetRefreshAttempt.map { now.timeIntervalSince($0) >= 3_600 } ?? true
        guard balanceDue || resetDue else { return }
        refreshPlanUsage(updateBalance: balanceDue, updateReset: resetDue, now: now)
    }

    func refreshPlanUsage(updateBalance: Bool = true, updateReset: Bool = true, now: Date = Date()) {
        guard updateBalance || updateReset else { return }
        let requestID = UUID()
        planUsageRequestID = requestID
        if updateBalance { lastBalanceRefreshAttempt = now }
        if updateReset { lastResetRefreshAttempt = now }
        let settings = planUsageSettings
        planUsageService.fetch(settings: settings) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                guard self.planUsageRequestID == requestID else { return }
                self.planUsageRequestID = nil
                switch result {
                case .success(let snapshot):
                    self.planUsage.authenticated = snapshot.authenticated
                    self.planUsage.planType = snapshot.planType
                    self.planUsage.email = snapshot.email
                    self.planUsage.windowDurationMinutes = snapshot.windowDurationMinutes
                    self.planUsage.status = snapshot.status
                    self.planUsageSettings.lastPlanType = snapshot.planType
                    self.planUsageSettings.lastEmail = snapshot.email
                    if updateBalance {
                        self.planUsage.remainingPercent = snapshot.remainingPercent
                        self.planUsageSettings.lastRemainingPercent = snapshot.remainingPercent
                    }
                    if updateReset {
                        self.planUsage.resetsAt = snapshot.resetsAt
                        self.planUsageSettings.lastResetAt = snapshot.resetsAt
                    }
                    self.planUsageSettings.save()
                case .failure(let error):
                    self.planUsage.status = error.localizedDescription
                }
                self.applyPlanUsageToRuntime()
                self.notifyChange()
            }
        }
    }

    private func updateTodayTokensTarget(_ target: Int, hasData: Bool) {
        guard hasData else { return }
        let safeTarget = max(target, 0)
        guard displayedTodayTokens != safeTarget else { return }
        tokenAnimationTimer?.invalidate()
        let startValue = displayedTodayTokens
        let difference = safeTarget - startValue
        let startedAt = Date()
        let duration: TimeInterval = 0.85
        tokenAnimationTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            let progress = min(max(Date().timeIntervalSince(startedAt) / duration, 0), 1)
            let eased = 1 - pow(1 - progress, 3)
            self.displayedTodayTokens = startValue + Int((Double(difference) * eased).rounded())
            self.notifyChange()
            if progress >= 1 {
                self.displayedTodayTokens = safeTarget
                timer.invalidate()
                self.tokenAnimationTimer = nil
            }
        }
    }

    private func applyPlanUsageToRuntime() {
        runtime.provider = planUsage.planLabel(override: planUsageSettings.planLabel)
        runtime.balance = planUsage.allowanceText
        runtime.balanceValue = planUsage.remainingPercent.map(Double.init)
        runtime.resetCountdown = planUsage.resetCountdown()
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
    private var animatedCache: [String: AnimatedImageAnimator] = [:]

    init(folderURL: URL?) {
        self.folderURL = folderURL
    }

    func weatherImage(condition: WeatherCondition, iconSet: WeatherIconSet, at time: TimeInterval) -> CGImage? {
        let hour = Calendar.current.component(.hour, from: Date())
        let isNight = hour < 6 || hour >= 18
        let names: [String]
        switch condition {
        case .clear:
            names = isNight ? ["07-moon", "weather-clear-night", "weather-clear", "weather"] : ["03-sun", "weather-clear", "weather"]
        case .partlyCloudy:
            names = isNight
                ? ["04-partly-cloudy", "weather-partly-cloudy-night", "weather-partly-cloudy", "weather-cloudy", "weather"]
                : ["04-partly-cloudy", "weather-partly-cloudy", "weather-cloudy", "weather"]
        case .cloudy: names = ["06-cloud", "weather-cloudy", "weather"]
        case .fog: names = ["06-cloud", "weather-fog", "weather-cloudy", "weather"]
        case .drizzle: names = ["08-showers", "weather-drizzle", "weather-rain", "weather"]
        case .rain: names = ["01-rain", "weather-rain", "weather"]
        case .snow: names = ["10-snowflake", "weather-snow", "weather"]
        case .thunderstorm: names = ["02-thunderstorm", "weather-storm", "weather-rain", "weather"]
        case .unknown: names = ["03-sun", "weather", "weather-clear"]
        }
        let bundledFolders = iconSet == .referenceStyle
            ? ["WeatherAssets/Alternate/ReferenceStyle", "WeatherAssets/Static"]
            : ["WeatherAssets/Static"]
        return image(names: names, subfolders: bundledFolders + ["weather", "icons"], at: time)
    }

    func agentImage(action: AgentAnimationAction, state: AgentState, elapsed: TimeInterval) -> CGImage? {
        if let image = image(
            names: [action.rawValue],
            subfolders: ["AgentAnimations", "agent"],
            at: elapsed
        ) {
            return image
        }

        var legacyNames = ["hermes-\(state.rawValue)", "agent-\(state.rawValue)"]
        if state == .outputting {
            legacyNames.append(contentsOf: ["hermes-working", "agent-working"])
        }
        legacyNames.append(contentsOf: ["hermes", "agent"])
        return image(names: legacyNames, subfolders: ["hermes", "agent", "icons"], at: elapsed)
    }

    private func image(names: [String], subfolders: [String], at time: TimeInterval) -> CGImage? {
        var roots: [URL] = []
        if let folderURL { roots.append(folderURL) }
        if let bundled = Bundle.main.resourceURL,
           !roots.contains(where: { $0.standardizedFileURL == bundled.standardizedFileURL }) {
            roots.append(bundled)
        }
        guard !roots.isEmpty else { return nil }
        for name in names {
            for root in roots {
                for folder in [root] + subfolders.map({ root.appendingPathComponent($0, isDirectory: true) }) {
                    for ext in ["webp", "gif", "png", "jpg", "jpeg"] {
                        let url = folder.appendingPathComponent("\(name).\(ext)")
                        guard FileManager.default.fileExists(atPath: url.path) else { continue }
                        if ext == "gif" || ext == "webp" {
                            if animatedCache[url.path] == nil {
                                animatedCache[url.path] = AnimatedImageAnimator(url: url)
                            }
                            if let frame = animatedCache[url.path]?.frame(at: time) { return frame }
                        } else {
                            if staticCache[url.path] == nil {
                                staticCache[url.path] = Self.loadImage(at: url)
                            }
                            if let image = staticCache[url.path] { return image }
                        }
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
