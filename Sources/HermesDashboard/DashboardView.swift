import AppKit
import QuartzCore

final class SettingsButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class DashboardView: NSView {
    private let model: DashboardModel
    private var wallpaper: GIFAnimator?
    private var animationTimer: Timer?
    private var phase = 0
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
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        animationTimer?.invalidate()
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
        let gearDesignX = runtime.x + 444
        let gearDesignY = runtime.y + 13
        settingsButton.frame = CGRect(
            x: offsetX + (padding + gearDesignX) * scale,
            y: offsetY + (padding + designSize.height - gearDesignY - 30) * scale,
            width: 30 * scale,
            height: 30 * scale
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
        drawText(clockFormatter.string(from: now), key: .clock, at: CGPoint(x: 42, y: 48), context: context)
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
        let rect = CGRect(x: origin.x, y: origin.y, width: 484, height: 432)
        PixelPainter.drawFrame(rect, color: PixelPalette.borderBright, context: context, fill: PixelPalette.panel.withAlphaComponent(model.layout.runtimeOpacity))
        var runtimeStyle = model.styles.style(for: .runtime)
        PixelPainter.drawText("RUNTIME STATUS", at: CGPoint(x: origin.x + 30, y: origin.y + 22), style: runtimeStyle, context: context)
        let sourceLabel = model.runtime.source == .codex ? "CODEX" : "HERMES"
        runtimeStyle.pointSize *= 0.55
        runtimeStyle.colorHex = PixelPalette.green.hexString
        let sourceWidth = PixelPainter.textWidth(sourceLabel, style: runtimeStyle)
        PixelPainter.drawText(sourceLabel, at: CGPoint(x: origin.x + 438 - sourceWidth, y: origin.y + 26), style: runtimeStyle, context: context)

        let rows: [(String, String, NSColor, Int)] = [
            ("MODEL", model.runtime.model, PixelPalette.cyan, 0),
            ("THINKING", model.runtime.thinking, PixelPalette.violet, 1),
            ("FASTMODE", model.runtime.fastMode ? "ON" : "OFF", PixelPalette.cyan, 2),
            ("PROVIDER", model.runtime.provider, PixelPalette.cyan, 3),
            ("BALANCE", model.runtime.balance, PixelPalette.green, 4),
            ("TOKENS", "\(model.runtime.tokenPercent)%", PixelPalette.cyan, 5)
        ]

        for (index, row) in rows.enumerated() {
            let rowY = origin.y + 66 + CGFloat(index) * 58
            PixelPainter.drawStatusIcon(at: CGPoint(x: origin.x + 28, y: rowY + 5), kind: row.3, color: row.2, context: context)
            var rowStyle = model.styles.style(for: .runtime)
            rowStyle.pointSize *= 0.72
            PixelPainter.drawText(row.0, at: CGPoint(x: origin.x + 80, y: rowY + 4), style: rowStyle, context: context)
            PixelPalette.border.setFill()
            let labelEnd = origin.x + 80 + PixelPainter.textWidth(row.0, style: rowStyle)
            for dot in stride(from: Int(labelEnd + 16), to: Int(origin.x + 350), by: 10) {
                context.fill(CGRect(x: CGFloat(dot), y: rowY + 19, width: 3, height: 2))
            }
            if row.0 == "FASTMODE" {
                var fastStyle = rowStyle
                fastStyle.colorHex = (row.1 == "ON" ? PixelPalette.cyan : PixelPalette.orange).hexString
                PixelPainter.drawText(row.1, at: CGPoint(x: origin.x + 360, y: rowY + 4), style: fastStyle, context: context)
                PixelPalette.cyan.setFill()
                context.fill(CGRect(x: origin.x + 418, y: rowY + 5, width: 42, height: 25))
                PixelPalette.navy.setFill()
                context.fill(CGRect(x: origin.x + (row.1 == "ON" ? 438 : 422), y: rowY + 9, width: 17, height: 17))
            } else {
                var valueStyle = rowStyle
                valueStyle.colorHex = (row.2 == PixelPalette.cyan ? PixelPalette.cyan : (row.0 == "THINKING" ? PixelPalette.orange : row.2)).hexString
                let valueWidth = PixelPainter.textWidth(row.1, style: valueStyle)
                PixelPainter.drawText(row.1, at: CGPoint(x: origin.x + 460 - valueWidth, y: rowY + 4), style: valueStyle, context: context)
            }
            row.2.setFill()
            context.fill(CGRect(x: origin.x + 469, y: rowY + 12, width: 7, height: 7))
        }
    }

    private func drawBottomArea(context: CGContext) {
        let agentOrigin = model.layout.hermesAgent
        let agentRect = CGRect(x: agentOrigin.x, y: agentOrigin.y, width: 584, height: 210)
        PixelPainter.drawFrame(agentRect, color: PixelPalette.borderBright, context: context, fill: PixelPalette.panel.withAlphaComponent(model.layout.agentOpacity))
        PixelPainter.drawText("HERMES AGENT", at: CGPoint(x: agentOrigin.x + 18, y: agentOrigin.y + 18), style: model.styles.style(for: .agent), context: context)
        var agentStateStyle = model.styles.style(for: .agent)
        agentStateStyle.pointSize *= 0.72
        let currentState = model.runtime.agentState
        if let agentImage = model.assetStore.agentImage(state: currentState, at: CACurrentMediaTime()) {
            PixelPainter.drawAsset(agentImage, in: CGRect(x: agentOrigin.x + 26, y: agentOrigin.y + 56, width: 188, height: 140), context: context)
        } else {
            PixelPainter.drawAvatar(at: CGPoint(x: agentOrigin.x + 42, y: agentOrigin.y + 56), scale: 3.0, state: currentState, phase: phase, context: context)
        }

        PixelPalette.border.setFill()
        context.fill(CGRect(x: agentOrigin.x + 260, y: agentOrigin.y + 54, width: 1, height: 138))
        var stateHintStyle = model.styles.style(for: .agent)
        stateHintStyle.pointSize *= 0.42
        stateHintStyle.colorHex = PixelPalette.cyanDim.hexString
        PixelPainter.drawText("CURRENT STATE", at: CGPoint(x: agentOrigin.x + 288, y: agentOrigin.y + 66), style: stateHintStyle, context: context)
        PixelPainter.drawText(currentState.label, at: CGPoint(x: agentOrigin.x + 288, y: agentOrigin.y + 92), style: agentStateStyle, context: context)
        var stateDetailStyle = stateHintStyle
        stateDetailStyle.colorHex = PixelPalette.cream.hexString
        PixelPainter.drawText(stateDescription(for: currentState), at: CGPoint(x: agentOrigin.x + 288, y: agentOrigin.y + 132), style: stateDetailStyle, context: context)

        var liveStyle = model.styles.style(for: .agent)
        liveStyle.pointSize *= 0.6
        liveStyle.colorHex = PixelPalette.green.hexString
        PixelPainter.drawText("LIVE", at: CGPoint(x: agentOrigin.x + 510, y: agentOrigin.y + 18), style: liveStyle, context: context)
        PixelPalette.green.setFill()
        context.fill(CGRect(x: agentOrigin.x + 500, y: agentOrigin.y + 74, width: 8, height: 8))

        let sessionOrigin = model.layout.activeSession
        let sessionRect = CGRect(x: sessionOrigin.x, y: sessionOrigin.y, width: 636, height: 210)
        PixelPainter.drawFrame(sessionRect, color: PixelPalette.cyan, context: context, fill: PixelPalette.panel.withAlphaComponent(model.layout.activeSessionOpacity))
        PixelPainter.drawText("ACTIVE SESSION", at: CGPoint(x: sessionOrigin.x + 24, y: sessionOrigin.y + 16), style: model.styles.style(for: .activeSessionTitle), context: context)
        var activeMetaStyle = model.styles.style(for: .activeSessionName)
        activeMetaStyle.pointSize *= 0.55
        activeMetaStyle.colorHex = PixelPalette.cyan.hexString
        PixelPainter.drawText(model.runtime.elapsed, at: CGPoint(x: sessionOrigin.x + 460, y: sessionOrigin.y + 18), style: activeMetaStyle, context: context)
        activeMetaStyle.colorHex = PixelPalette.green.hexString
        PixelPainter.drawText("RUNNING", at: CGPoint(x: sessionOrigin.x + 526, y: sessionOrigin.y + 18), style: activeMetaStyle, context: context)
        PixelPainter.drawText(model.runtime.activeSession, at: CGPoint(x: sessionOrigin.x + 24, y: sessionOrigin.y + 46), style: model.styles.style(for: .activeSessionName), context: context)
        PixelPainter.drawProgress(CGRect(x: sessionOrigin.x + 24, y: sessionOrigin.y + 79, width: 504, height: 23), value: model.runtime.contextPercent, color: PixelPalette.cyan, context: context)
        activeMetaStyle.colorHex = PixelPalette.cyan.hexString
        PixelPainter.drawText("CTX \(model.runtime.contextPercent)%", at: CGPoint(x: sessionOrigin.x + 542, y: sessionOrigin.y + 81), style: activeMetaStyle, context: context)

        let recent = model.runtime.sessions.count == 4 ? model.runtime.sessions : RuntimeStatus.demo(source: model.runtime.source).sessions
        let positions = [
            CGRect(x: sessionOrigin.x + 24, y: sessionOrigin.y + 118, width: 292, height: 38), CGRect(x: sessionOrigin.x + 328, y: sessionOrigin.y + 118, width: 292, height: 38),
            CGRect(x: sessionOrigin.x + 24, y: sessionOrigin.y + 162, width: 292, height: 38), CGRect(x: sessionOrigin.x + 328, y: sessionOrigin.y + 162, width: 292, height: 38)
        ]
        for (index, card) in recent.prefix(4).enumerated() {
            drawSessionCard(card, rect: positions[index], context: context)
        }
    }

    private func drawSessionCard(_ session: SessionInfo, rect: CGRect, context: CGContext) {
        PixelPainter.drawFrame(rect, color: PixelPalette.border, context: context, fill: PixelPalette.navy)
        drawText(session.title, key: .recentSession, at: CGPoint(x: rect.minX + 12, y: rect.minY + 8), context: context)
        if !session.updatedAt.isEmpty {
            var metaStyle = model.styles.style(for: .recentSession)
            metaStyle.pointSize *= 0.85
            metaStyle.colorHex = PixelPalette.cyanDim.hexString
            PixelPainter.drawText(session.updatedAt, at: CGPoint(x: rect.maxX - 72, y: rect.minY + 8), style: metaStyle, context: context)
        }
        PixelPainter.drawProgress(CGRect(x: rect.minX + 12, y: rect.minY + 25, width: rect.width - 106, height: 9), value: session.progress, color: session.progress == 100 ? PixelPalette.green : PixelPalette.cyan, context: context)
        var progressStyle = model.styles.style(for: .recentSession)
        progressStyle.pointSize *= 0.85
        progressStyle.colorHex = (session.progress == 100 ? PixelPalette.green : PixelPalette.cyan).hexString
        PixelPainter.drawText("\(session.progress)%", at: CGPoint(x: rect.maxX - 82, y: rect.minY + 25), style: progressStyle, context: context)
    }

    private func drawText(_ text: String, key: DashboardStyleKey, at point: CGPoint, context: CGContext) {
        PixelPainter.drawText(text, at: point, style: model.styles.style(for: key), context: context)
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
        context.fill(CGRect(x: 8, y: 474, width: 1264, height: 5))
        PixelPalette.borderBright.setFill()
        context.fill(CGRect(x: 18, y: 476, width: 1244, height: 2))
    }
}
