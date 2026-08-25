import AppKit
import QuartzCore
import ImageIO

final class SettingsButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class DashboardView: NSView {
    private let model: DashboardModel
    private var wallpaper: GIFAnimator?
    private var animationTimer: Timer?
    private var clockBlinkTimer: Timer?
    private var phase = 0
    private var clockColonVisible = true
    private let settingsButton: NSButton = {
        let button = SettingsButton(frame: .zero)
        button.setButtonType(.momentaryPushIn)
        button.bezelStyle = .regularSquare
        button.isBordered = false
        button.image = NSImage(systemSymbolName: "gearshape.fill", accessibilityDescription: "Open settings")
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.contentTintColor = PixelPalette.cyan
        button.toolTip = "Open Hermes Dashboard settings"
        return button
    }()

    private let designSize = CGSize(width: 1280, height: 720)
    // The flipped drawing canvas places the 405pt upper region above this
    // divider, leaving a 315pt lower region for the two bottom modules.
    private let areaSplitY: CGFloat = 405
    private let runtimeModuleHeight: CGFloat = 378
    private let bottomModuleHeight: CGFloat = 288
    private let clockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEEE / MMM d"
        return formatter
    }()

    init(model: DashboardModel) {
        self.model = model
        super.init(frame: .zero)
        wantsLayer = true
        settingsButton.target = self
        settingsButton.action = #selector(openSettings(_:))
        addSubview(settingsButton)
        model.onChange = { [weak self] in
            self?.reloadWallpaperIfNeeded()
            self?.needsLayout = true
            self?.needsDisplay = true
        }
        reloadWallpaperIfNeeded()
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in
            self?.phase += 1
            self?.needsDisplay = true
        }
        clockBlinkTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.clockColonVisible.toggle()
            self?.needsDisplay = true
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        animationTimer?.invalidate()
        clockBlinkTimer?.invalidate()
    }

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func layout() {
        super.layout()
        let padding = model.layout.padding
        let canvasSize = CGSize(width: designSize.width + padding * 2, height: designSize.height + padding * 2)
        let scale = min(bounds.width / canvasSize.width, bounds.height / canvasSize.height)
        let offsetX = (bounds.width - canvasSize.width * scale) / 2
        let offsetY = (bounds.height - canvasSize.height * scale) / 2
        let runtime = model.layout.runtimeStatus
        let gearSize: CGFloat = 54
        let gearDesignX = runtime.x + 424
        let gearDesignY = runtime.y + 2
        settingsButton.frame = CGRect(
            x: offsetX + (padding + gearDesignX) * scale,
            y: offsetY + (padding + designSize.height - gearDesignY - gearSize) * scale,
            width: gearSize * scale,
            height: gearSize * scale
        ).integral
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.setShouldAntialias(false)
        context.interpolationQuality = .none

        let padding = model.layout.padding
        let canvasSize = CGSize(width: designSize.width + padding * 2, height: designSize.height + padding * 2)
        let scale = min(bounds.width / canvasSize.width, bounds.height / canvasSize.height)
        let offsetX = (bounds.width - canvasSize.width * scale) / 2
        let offsetY = (bounds.height - canvasSize.height * scale) / 2

        context.saveGState()
        context.translateBy(x: offsetX + padding * scale, y: offsetY + (padding + designSize.height) * scale)
        context.scaleBy(x: scale, y: -scale)

        PixelPainter.drawDefaultBackdrop(width: designSize.width, height: designSize.height, context: context)
        if let frame = wallpaper?.frame(at: CACurrentMediaTime()) {
            PixelPainter.drawWallpaper(frame, in: CGRect(origin: .zero, size: designSize), alpha: 0.26, context: context)
        }

        drawTopArea(context: context)
        drawBottomArea(context: context)
        drawOuterFrame(context: context)
        context.restoreGState()
    }

    override func keyDown(with event: NSEvent) {
        let command = event.modifierFlags.contains(.command)
        let key = event.charactersIgnoringModifiers?.lowercased()
        if command && key == "," {
            (NSApp.delegate as? DashboardAppDelegate)?.showSettings()
            return
        }
        if command && key == "q" {
            NSApp.terminate(nil)
            return
        }
        if event.keyCode == 53 {
            NSApp.terminate(nil)
            return
        }
        if key == "s" {
            (NSApp.delegate as? DashboardAppDelegate)?.showSettings()
            return
        }
        super.keyDown(with: event)
    }

    @objc private func openSettings(_ sender: NSButton) {
        (NSApp.delegate as? DashboardAppDelegate)?.showSettings()
    }

    private func reloadWallpaperIfNeeded() {
        guard let path = model.wallpaperPath else {
            wallpaper = nil
            return
        }
        let url = URL(fileURLWithPath: path)
        wallpaper = GIFAnimator(url: url)
    }

    private func drawTopArea(context: CGContext) {
        // Time and weather occupy one aligned visual row.
        let now = Date()
        let timeParts = clockFormatter.string(from: now).split(separator: ":", maxSplits: 1).map(String.init)
        let hour = timeParts.first ?? "00"
        let minute = timeParts.count > 1 ? timeParts[1] : "00"
        let clockStyle = model.styles.style(for: .clock)
        let hourWidth = PixelPainter.textWidth(hour, style: clockStyle)
        let colonWidth = PixelPainter.textWidth(":", style: clockStyle)
        let clockX: CGFloat = 42
        drawText(hour, key: .clock, at: CGPoint(x: clockX, y: 48), context: context)
        if clockColonVisible {
            drawText(":", key: .clock, at: CGPoint(x: clockX + hourWidth, y: 48), context: context)
        }
        // Keep the minute anchor fixed to the full HH:MM geometry even while
        // the separator is hidden, so the minute digits never jump.
        drawText(minute, key: .clock, at: CGPoint(x: clockX + hourWidth + colonWidth, y: 48), context: context)
        let weatherRect = CGRect(x: 560, y: 48, width: 128, height: 128)
        if let weatherImage = model.assetStore.weatherImage(condition: model.weather.condition, at: CACurrentMediaTime()) {
            PixelPainter.drawAsset(weatherImage, in: weatherRect, context: context)
        } else {
            PixelPainter.drawWeatherIcon(at: CGPoint(x: 572, y: 48), scale: 8, condition: model.weather.condition, context: context)
        }

        let date = dateFormatter.string(from: now).uppercased()
        drawText(date, key: .date, at: CGPoint(x: 42, y: 186), context: context)
        let dateWidth = PixelPainter.textWidth(date, style: model.styles.style(for: .date))
        drawText(model.weather.temperature, key: .temperature, at: CGPoint(x: 66 + dateWidth, y: 186), context: context)

        // Borderless two-line music broadcast.
        let artist = model.music.artist.isEmpty ? "HERMES AGENT" : model.music.artist
        let title = model.music.title.isEmpty ? "TELEMETRY DREAMS" : model.music.title
        drawText(artist, key: .artist, at: CGPoint(x: 42, y: 252), context: context)
        drawText(title, key: .title, at: CGPoint(x: 42, y: 287), context: context)
        PixelPalette.cyanDim.setFill()
        for index in 0..<6 {
            let height = CGFloat(3 + ((phase + index * 2) % 7))
            context.fill(CGRect(x: 45 + CGFloat(index * 9), y: 332 - height, width: 5, height: height))
        }

        drawRuntimeStatus(context: context)
    }

    private func drawRuntimeStatus(context: CGContext) {
        let origin = model.layout.runtimeStatus
        let rect = CGRect(x: origin.x, y: origin.y, width: 484, height: runtimeModuleHeight)
        PixelPainter.drawFrame(rect, color: PixelPalette.borderBright, context: context, fill: PixelPalette.panel.withAlphaComponent(model.layout.runtimeOpacity))
        var runtimeStyle = model.styles.style(for: .runtime)
        drawText("RUNTIME STATUS", key: .runtime, at: CGPoint(x: origin.x + 30, y: origin.y + 22), context: context, style: runtimeStyle)
        runtimeStyle.pointSize *= 0.55

        let rows: [(RuntimeIconKey, String, String, NSColor)] = [
            (.model, "MODEL", model.runtime.model, PixelPalette.cyan),
            (.thinking, "THINKING", model.runtime.thinking, thinkingColor(model.runtime.thinking)),
            (.fastMode, "FASTMODE", model.runtime.fastMode ? "ON" : "OFF", PixelPalette.cyan),
            (.provider, "PROVIDER", model.runtime.provider, PixelPalette.cyan),
            (.balance, "BALANCE", model.runtime.balance, balanceColor(model.runtime.balanceValue)),
            (.tokens, "TOKENS", "\(model.runtime.tokenPercent)%", PixelPalette.cyan)
        ]

        for (index, row) in rows.enumerated() {
            let rowY = origin.y + 22 + runtimeStyle.pointSize + model.layout.runtimeTitleSpacing + CGFloat(index) * 35
            let icon = model.layout.runtimeIcons[row.0.rawValue] ?? DashboardLayout.defaultRuntimeIcons[row.0.rawValue]!
            if let custom = runtimeIconImage(style: icon) {
                PixelPainter.drawAsset(custom, in: CGRect(x: origin.x + icon.x, y: rowY + icon.y, width: 24, height: 24), context: context)
            } else {
                PixelPainter.drawStatusIcon(at: CGPoint(x: origin.x + icon.x, y: rowY + icon.y), kind: icon.pattern, color: row.3, context: context)
            }
            var rowStyle = model.styles.style(for: .runtime)
            rowStyle.pointSize *= 0.72
            drawText(row.1, key: .runtime, at: CGPoint(x: origin.x + 80, y: rowY + 4), context: context, style: rowStyle)
            PixelPalette.border.setFill()
            let labelEnd = origin.x + 80 + PixelPainter.textWidth(row.1, style: rowStyle)
            for dot in stride(from: Int(labelEnd + 16), to: Int(origin.x + 350), by: 10) {
                context.fill(CGRect(x: CGFloat(dot), y: rowY + 19, width: 3, height: 2))
            }
            if row.0 == .fastMode {
                var fastStyle = rowStyle
                fastStyle.colorHex = (row.2 == "ON" ? PixelPalette.cyan : PixelPalette.orange).hexString
                drawText(row.2, key: .runtime, at: CGPoint(x: origin.x + 360, y: rowY + 4), context: context, style: fastStyle)
                PixelPalette.cyan.setFill()
                context.fill(CGRect(x: origin.x + 418, y: rowY + 5, width: 42, height: 25))
                PixelPalette.navy.setFill()
                context.fill(CGRect(x: origin.x + (row.2 == "ON" ? 438 : 422), y: rowY + 9, width: 17, height: 17))
            } else {
                var valueStyle = rowStyle
                valueStyle.colorHex = row.3.hexString
                let valueWidth = PixelPainter.textWidth(row.2, style: valueStyle)
                drawText(row.2, key: .runtime, at: CGPoint(x: origin.x + 460 - valueWidth, y: rowY + 4), context: context, style: valueStyle)
            }
        }
    }

    private func thinkingColor(_ value: String) -> NSColor {
        switch value.lowercased() {
        case "low", "minimal": return PixelPalette.green
        case "medium", "med": return PixelPalette.yellow
        case "high": return PixelPalette.orange
        case "xhigh", "ultra", "max": return PixelPalette.violet
        default: return PixelPalette.cyan
        }
    }

    private func balanceColor(_ value: Double?) -> NSColor {
        guard let value else { return PixelPalette.orange }
        if value >= 10 { return PixelPalette.green }
        if value >= 5 { return PixelPalette.yellow }
        return PixelPalette.red
    }

    private func runtimeIconImage(style: RuntimeIconStyle) -> CGImage? {
        guard style.name.hasPrefix("file:") else { return nil }
        let url = URL(fileURLWithPath: String(style.name.dropFirst(5)))
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    private func drawBottomArea(context: CGContext) {
        let agentOrigin = model.layout.hermesAgent
        let agentRect = CGRect(x: agentOrigin.x, y: agentOrigin.y, width: 584, height: bottomModuleHeight)
        PixelPainter.drawFrame(agentRect, color: PixelPalette.borderBright, context: context, fill: PixelPalette.panel.withAlphaComponent(model.layout.agentOpacity))
        drawText("HERMES AGENT", key: .agent, at: CGPoint(x: agentOrigin.x + 18, y: agentOrigin.y + 18), context: context)
        var agentStateStyle = model.styles.style(for: .agent)
        agentStateStyle.pointSize *= 0.72
        let currentState = model.runtime.agentState
        if let agentImage = model.assetStore.agentImage(state: currentState, at: CACurrentMediaTime()) {
            PixelPainter.drawAsset(agentImage, in: CGRect(x: agentOrigin.x + 26, y: agentOrigin.y + 56, width: 188, height: 164), context: context)
        } else {
            PixelPainter.drawAvatar(at: CGPoint(x: agentOrigin.x + 42, y: agentOrigin.y + 56), scale: 3.0, state: currentState, phase: phase, context: context)
        }

        PixelPalette.border.setFill()
        context.fill(CGRect(x: agentOrigin.x + 260, y: agentOrigin.y + 54, width: 1, height: 180))
        var stateHintStyle = model.styles.style(for: .agent)
        stateHintStyle.pointSize *= 0.42
        stateHintStyle.colorHex = PixelPalette.cyanDim.hexString
        drawText("CURRENT STATE", key: .agent, at: CGPoint(x: agentOrigin.x + 288, y: agentOrigin.y + 66), context: context, style: stateHintStyle)
        drawText(currentState.label, key: .agent, at: CGPoint(x: agentOrigin.x + 288, y: agentOrigin.y + 92), context: context, style: agentStateStyle)
        var stateDetailStyle = stateHintStyle
        stateDetailStyle.colorHex = PixelPalette.cream.hexString
        drawText(stateDescription(for: currentState), key: .agent, at: CGPoint(x: agentOrigin.x + 288, y: agentOrigin.y + 132), context: context, style: stateDetailStyle)

        var liveStyle = model.styles.style(for: .agent)
        liveStyle.pointSize *= 0.6
        let liveColor = model.runtime.isLive ? PixelPalette.green : PixelPalette.cyanDim
        liveStyle.colorHex = liveColor.hexString
        drawText(model.runtime.isLive ? "LIVE" : "LOCAL", key: .agent, at: CGPoint(x: agentOrigin.x + 510, y: agentOrigin.y + 18), context: context, style: liveStyle)
        liveColor.setFill()
        context.fill(CGRect(x: agentOrigin.x + 500, y: agentOrigin.y + 74, width: 8, height: 8))

        let sessionOrigin = model.layout.activeSession
        let sessionRect = CGRect(x: sessionOrigin.x, y: sessionOrigin.y, width: 636, height: bottomModuleHeight)
        PixelPainter.drawFrame(sessionRect, color: PixelPalette.borderBright, context: context, fill: PixelPalette.panel.withAlphaComponent(model.layout.activeSessionOpacity))
        let latestRect = CGRect(x: sessionOrigin.x + 24, y: sessionOrigin.y + 10, width: 596, height: 108)
        PixelPainter.drawFrame(latestRect, color: PixelPalette.cyan, context: context, fill: PixelPalette.navy.withAlphaComponent(model.layout.sessionCardOpacity))
        drawText("ACTIVE SESSION", key: .activeSessionTitle, at: CGPoint(x: sessionOrigin.x + 40, y: sessionOrigin.y + 22), context: context)
        let recent = Array(model.runtime.sessions.prefix(5))
        if let latest = recent.first {
            let latestStyle = model.styles.style(for: .activeSessionName)
            let latestTitle = fittedText(latest.title, style: latestStyle, maxWidth: 500)
            drawText(latestTitle, key: .activeSessionName, at: CGPoint(x: sessionOrigin.x + 40, y: sessionOrigin.y + 52), context: context)
            if !latest.updatedAt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                drawText(latest.updatedAt, key: .activeSessionUpdatedAt, at: CGPoint(x: sessionOrigin.x, y: sessionOrigin.y), context: context)
            }
            drawSessionStatusLamp(latest.status, at: CGPoint(x: latestRect.maxX - 30, y: latestRect.minY + 23), context: context)
            PixelPainter.drawProgress(CGRect(x: sessionOrigin.x + 40, y: sessionOrigin.y + 84, width: 548, height: 14), value: sessionContextValue(latest), color: PixelPalette.cyan, context: context)
        }
        let positions = [
            CGRect(x: sessionOrigin.x + 24, y: sessionOrigin.y + 124, width: 292, height: 76),
            CGRect(x: sessionOrigin.x + 328, y: sessionOrigin.y + 124, width: 292, height: 76),
            CGRect(x: sessionOrigin.x + 24, y: sessionOrigin.y + 202, width: 292, height: 76),
            CGRect(x: sessionOrigin.x + 328, y: sessionOrigin.y + 202, width: 292, height: 76)
        ]
        // The latest session lives in the shared header frame above; only the
        // remaining four sessions are assigned to these child frames.
        for (index, card) in recent.dropFirst().prefix(4).enumerated() {
            drawSessionCard(card, rect: positions[index], context: context)
        }
    }

    private func drawSessionCard(_ session: SessionInfo, rect: CGRect, context: CGContext) {
        PixelPainter.drawFrame(rect, color: PixelPalette.border, context: context, fill: PixelPalette.navy.withAlphaComponent(model.layout.sessionCardOpacity))
        let titleStyle = model.styles.style(for: .recentSession)
        let title = fittedText(session.title, style: titleStyle, maxWidth: rect.width - 54)
        drawText(title, key: .recentSession, at: CGPoint(x: rect.minX + 12, y: rect.minY + 12), context: context)
        drawSessionStatusLamp(session.status, at: CGPoint(x: rect.maxX - 26, y: rect.minY + 19), context: context)
        PixelPainter.drawProgress(CGRect(x: rect.minX + 12, y: rect.minY + 46, width: rect.width - 24, height: 14), value: sessionContextValue(session), color: PixelPalette.cyan, context: context)
    }

    private func sessionContextValue(_ session: SessionInfo) -> Int {
        session.contextPercent > 0 ? session.contextPercent : session.progress
    }

    private func drawSessionStatusLamp(_ status: String, at point: CGPoint, context: CGContext) {
        let normalized = status.uppercased()
        let color: NSColor
        switch normalized {
        case "DONE": color = PixelPalette.green
        case "ERROR": color = PixelPalette.red
        default: color = PixelPalette.cyan
        }
        let isRunning = normalized == "RUNNING"
        let isVisible = !isRunning || phase % 10 < 5
        PixelPalette.navy.setFill()
        context.fill(CGRect(x: point.x - 2, y: point.y - 2, width: 12, height: 12))
        if isVisible {
            color.setFill()
            context.fill(CGRect(x: point.x, y: point.y, width: 8, height: 8))
        }
    }

    private func fittedText(_ text: String, style: TextStyle, maxWidth: CGFloat) -> String {
        guard PixelPainter.textWidth(text, style: style) > maxWidth else { return text }
        var result = ""
        for character in text {
            let candidate = result + String(character) + "..."
            if PixelPainter.textWidth(candidate, style: style) > maxWidth { break }
            result.append(character)
        }
        return result.isEmpty ? "..." : result + "..."
    }

    private func drawText(_ text: String, key: DashboardStyleKey, at point: CGPoint, context: CGContext) {
        drawText(text, key: key, at: point, context: context, style: model.styles.style(for: key))
    }

    private func drawText(_ text: String, key: DashboardStyleKey, at point: CGPoint, context: CGContext, style: TextStyle) {
        let position = model.styles.style(for: key)
        let defaultPosition = key.defaultPosition
        let adjustedPoint = CGPoint(
            x: point.x + position.x - defaultPosition.x,
            y: point.y + position.y - defaultPosition.y
        )
        PixelPainter.drawText(text, at: adjustedPoint, style: style, context: context)
    }

    private func stateDescription(for state: AgentState) -> String {
        switch state {
        case .working: return "PROCESSING"
        case .thinking: return "PLANNING"
        case .done: return "COMPLETE"
        case .idle: return "STANDBY"
        case .error: return "ATTENTION"
        }
    }

    private func drawOuterFrame(context: CGContext) {
        PixelPainter.drawFrame(CGRect(x: 8, y: 8, width: 1264, height: 704), color: PixelPalette.borderBright, context: context)
        PixelPalette.border.setFill()
        context.fill(CGRect(x: 8, y: areaSplitY, width: 1264, height: 5))
        PixelPalette.borderBright.setFill()
        context.fill(CGRect(x: 18, y: areaSplitY + 2, width: 1244, height: 2))
    }
}
