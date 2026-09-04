import AppKit
import CoreText
import UniformTypeIdentifiers

final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let model: DashboardModel
    private weak var parentWindow: NSWindow?
    private let onDisplayChanged: (NSScreen) -> Void
    private let sourcePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let displayPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let wallpaperLabel = NSTextField(labelWithString: "No GIF selected")
    private let assetFolderLabel = NSTextField(labelWithString: "Use built-in pixel icons")
    private let statusPathLabel = NSTextField(labelWithString: "")
    private var styleRows: [DashboardStyleKey: StyleRow] = [:]
    private var availableScreens: [NSScreen] = []
    private var layoutController: LayoutSettingsWindowController?
    private var planUsageController: PlanUsageSettingsWindowController?
    private var weatherController: WeatherSettingsWindowController?
    private var runtimeColorController: RuntimeColorSettingsWindowController?

    init(model: DashboardModel, parentWindow: NSWindow?, onDisplayChanged: @escaping (NSScreen) -> Void) {
        self.model = model
        self.parentWindow = parentWindow
        self.onDisplayChanged = onDisplayChanged
        let window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 720), styleMask: [.titled, .closable, .utilityWindow], backing: .buffered, defer: false)
        window.title = "Hermes Dashboard Settings"
        window.isFloatingPanel = true
        window.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.hidesOnDeactivate = false
        window.backgroundColor = NSColor(calibratedWhite: 0.96, alpha: 1)
        window.appearance = NSAppearance(named: .aqua)
        window.minSize = NSSize(width: 980, height: 620)
        super.init(window: window)
        window.delegate = self
        buildContent()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        reloadDisplays()
        centerWindow(on: parentWindow?.screen ?? DashboardDisplayPreference.preferredScreen())
        NSApp.activate(ignoringOtherApps: true)
        if let panel = window {
            if let parentWindow, panel.parent == nil {
                parentWindow.addChildWindow(panel, ordered: .above)
            }
            panel.orderFrontRegardless()
            panel.makeKey()
        }
    }

    func windowWillClose(_ notification: Notification) {
        guard let panel = window else { return }
        parentWindow?.removeChildWindow(panel)
        parentWindow?.makeKeyAndOrderFront(nil)
    }

    private func buildContent() {
        guard let content = window?.contentView else { return }
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor(calibratedWhite: 0.96, alpha: 1).cgColor

        let title = NSTextField(labelWithString: "DASHBOARD CONTROL")
        title.font = NSFont.monospacedSystemFont(ofSize: 18, weight: .bold)
        title.textColor = NSColor(calibratedRed: 0.04, green: 0.31, blue: 0.38, alpha: 1)
        title.frame = NSRect(x: 28, y: 674, width: 930, height: 26)
        content.addSubview(title)

        let sourceLabel = makeLabel("RUNTIME STATUS SOURCE")
        sourceLabel.frame = NSRect(x: 28, y: 626, width: 240, height: 20)
        content.addSubview(sourceLabel)
        sourcePopup.addItems(withTitles: RuntimeSource.allCases.map(\.displayName))
        sourcePopup.selectItem(at: model.runtimeSource == .codex ? 0 : 1)
        sourcePopup.frame = NSRect(x: 280, y: 622, width: 260, height: 28)
        sourcePopup.target = self
        sourcePopup.action = #selector(sourceChanged(_:))
        content.addSubview(sourcePopup)
        addButton("Plan Usage / OAuth…", x: 570, y: 622, width: 160, action: #selector(showPlanUsageSettings(_:)), to: content)

        let displayLabel = makeLabel("DEFAULT DISPLAY")
        displayLabel.frame = NSRect(x: 28, y: 584, width: 240, height: 20)
        content.addSubview(displayLabel)
        displayPopup.frame = NSRect(x: 280, y: 580, width: 360, height: 28)
        displayPopup.target = self
        displayPopup.action = #selector(displayChanged(_:))
        content.addSubview(displayPopup)
        reloadDisplays()

        let weatherLabel = makeLabel("WEATHER SOURCE")
        weatherLabel.frame = NSRect(x: 730, y: 606, width: 180, height: 18)
        content.addSubview(weatherLabel)
        addButton("Weather Settings…", x: 730, y: 578, width: 150, action: #selector(showWeatherSettings(_:)), to: content)

        let wallpaperTitle = makeLabel("GIF WALLPAPER")
        wallpaperTitle.frame = NSRect(x: 28, y: 540, width: 240, height: 20)
        content.addSubview(wallpaperTitle)
        wallpaperLabel.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        wallpaperLabel.textColor = NSColor.labelColor
        wallpaperLabel.lineBreakMode = .byTruncatingMiddle
        wallpaperLabel.stringValue = model.wallpaperPath ?? "No GIF selected"
        wallpaperLabel.frame = NSRect(x: 280, y: 540, width: 350, height: 20)
        content.addSubview(wallpaperLabel)
        addButton("Choose GIF…", x: 640, y: 536, width: 80, action: #selector(chooseWallpaper(_:)), to: content)
        addButton("Clear", x: 728, y: 536, width: 54, action: #selector(clearWallpaper(_:)), to: content)

        let assetTitle = makeLabel("WEATHER / AGENT ASSET FOLDER")
        assetTitle.frame = NSRect(x: 28, y: 496, width: 240, height: 20)
        content.addSubview(assetTitle)
        assetFolderLabel.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        assetFolderLabel.textColor = NSColor.labelColor
        assetFolderLabel.lineBreakMode = .byTruncatingMiddle
        assetFolderLabel.stringValue = model.assetFolderPath ?? "Use built-in pixel icons"
        assetFolderLabel.frame = NSRect(x: 280, y: 496, width: 350, height: 20)
        content.addSubview(assetFolderLabel)
        addButton("Choose Folder…", x: 640, y: 492, width: 100, action: #selector(chooseAssetFolder(_:)), to: content)
        addButton("Clear", x: 748, y: 492, width: 54, action: #selector(clearAssetFolder(_:)), to: content)

        let assetHint = NSTextField(wrappingLabelWithString: "Optional names: weather-clear.png / weather-rain.gif and hermes-working.png / hermes-thinking.gif / hermes-done.png. Subfolders weather/, hermes/ and icons/ are also searched.")
        assetHint.font = NSFont.systemFont(ofSize: 10)
        assetHint.textColor = NSColor.secondaryLabelColor
        assetHint.frame = NSRect(x: 280, y: 450, width: 470, height: 38)
        content.addSubview(assetHint)

        addButton("Layout / Opacity…", x: 28, y: 404, width: 140, action: #selector(showLayoutSettings(_:)), to: content)
        addButton("Runtime Colors…", x: 180, y: 404, width: 150, action: #selector(showRuntimeColors(_:)), to: content)
        let styleTitle = makeLabel("TEXT STYLE OVERRIDES")
        styleTitle.frame = NSRect(x: 28, y: 376, width: 300, height: 20)
        content.addSubview(styleTitle)
        let columnHint = NSTextField(labelWithString: "POSITION X       Y       FONT FAMILY                         SIZE       COLOR       R       G       B       SMOOTH + 8X")
        columnHint.font = NSFont.monospacedSystemFont(ofSize: 9, weight: .regular)
        columnHint.textColor = PixelPalette.cyanDim
        columnHint.frame = NSRect(x: 38, y: 353, width: 930, height: 16)
        content.addSubview(columnHint)

        let documentHeight = CGFloat(DashboardStyleKey.allCases.count) * 44 + 12
        let document = NSView(frame: NSRect(x: 0, y: 0, width: 930, height: documentHeight))
        for (index, key) in DashboardStyleKey.allCases.enumerated() {
            let y = documentHeight - CGFloat(index + 1) * 44
            let row = StyleRow(key: key, style: model.styles.style(for: key), owner: self)
            row.frame = NSRect(x: 8, y: y, width: 914, height: 40)
            document.addSubview(row)
            styleRows[key] = row
        }
        let scroll = NSScrollView(frame: NSRect(x: 28, y: 82, width: 944, height: 260))
        scroll.documentView = document
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        content.addSubview(scroll)

        addButton("Import Font…", x: 28, y: 44, width: 104, action: #selector(loadFont(_:)), to: content)
        addButton("Reset Text Styles", x: 140, y: 44, width: 130, action: #selector(resetStyles(_:)), to: content)
        let note = NSTextField(wrappingLabelWithString: "Styles are saved immediately. Imported .ttf/.otf/.ttc files are kept in Application Support and registered at launch.")
        note.font = NSFont.systemFont(ofSize: 10)
        note.textColor = NSColor.secondaryLabelColor
        note.frame = NSRect(x: 290, y: 42, width: 680, height: 28)
        content.addSubview(note)

        statusPathLabel.font = NSFont.monospacedSystemFont(ofSize: 9, weight: .regular)
        statusPathLabel.textColor = NSColor.secondaryLabelColor
        statusPathLabel.frame = NSRect(x: 28, y: 18, width: 930, height: 18)
        content.addSubview(statusPathLabel)
        updateStatusPathLabel()
    }

    private func makeLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .bold)
        label.textColor = NSColor(calibratedWhite: 0.12, alpha: 1)
        return label
    }

    private func addButton(_ title: String, x: CGFloat, y: CGFloat, width: CGFloat, action: Selector, to view: NSView) {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        button.frame = NSRect(x: x, y: y, width: width, height: 28)
        view.addSubview(button)
    }

    @objc private func showLayoutSettings(_ sender: NSButton) {
        if layoutController == nil {
            layoutController = LayoutSettingsWindowController(model: model, parentWindow: window)
        }
        layoutController?.showWindow(nil)
    }

    @objc private func showPlanUsageSettings(_ sender: NSButton) {
        if planUsageController == nil { planUsageController = PlanUsageSettingsWindowController(model: model, parentWindow: window) }
        planUsageController?.showWindow(nil)
    }

    @objc private func showRuntimeColors(_ sender: NSButton) {
        if runtimeColorController == nil {
            runtimeColorController = RuntimeColorSettingsWindowController(model: model, parentWindow: window) { [weak self] well in
                self?.showColorPanel(for: well)
            }
        }
        runtimeColorController?.showWindow(nil)
    }

    @objc private func showWeatherSettings(_ sender: NSButton) {
        if weatherController == nil { weatherController = WeatherSettingsWindowController(model: model, parentWindow: window) }
        weatherController?.showWindow(nil)
    }

    @objc private func sourceChanged(_ sender: NSPopUpButton) {
        model.runtimeSource = sender.indexOfSelectedItem == 0 ? .codex : .hermes
        updateStatusPathLabel()
    }

    @objc private func displayChanged(_ sender: NSPopUpButton) {
        guard availableScreens.indices.contains(sender.indexOfSelectedItem) else { return }
        let screen = availableScreens[sender.indexOfSelectedItem]
        DashboardDisplayPreference.save(screen: screen)
        onDisplayChanged(screen)
        centerWindow(on: screen)
    }

    private func reloadDisplays() {
        availableScreens = NSScreen.screens
        displayPopup.removeAllItems()
        for (index, screen) in availableScreens.enumerated() {
            displayPopup.addItem(withTitle: DashboardDisplayPreference.label(for: screen, index: index))
        }

        let preferredID = DashboardDisplayPreference.savedDisplayID
            ?? parentWindow?.screen.flatMap { DashboardDisplayPreference.displayID(for: $0) }
        if let index = availableScreens.firstIndex(where: { DashboardDisplayPreference.displayID(for: $0) == preferredID }) {
            displayPopup.selectItem(at: index)
        } else if !availableScreens.isEmpty {
            displayPopup.selectItem(at: 0)
        }
    }

    private func centerWindow(on screen: NSScreen) {
        guard let window else { return }
        let frame = window.frame
        let visible = screen.visibleFrame
        window.setFrameOrigin(NSPoint(
            x: visible.midX - frame.width / 2,
            y: visible.midY - frame.height / 2
        ))
    }

    private func updateStatusPathLabel() {
        let folder = model.runtimeSource == .codex ? "Codex" : "HermesAgent"
        statusPathLabel.stringValue = "Status: ~/Library/Application Support/\(folder)/status.json    •    Gear, ⌘, or S opens settings    •    Esc exits"
    }

    @objc private func chooseWallpaper(_ sender: NSButton) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.gif]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        beginFilePanel(panel) { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            self.model.setWallpaper(url: url)
            self.wallpaperLabel.stringValue = url.path
        }
    }

    @objc private func clearWallpaper(_ sender: NSButton) {
        model.setWallpaper(url: nil)
        wallpaperLabel.stringValue = "No GIF selected"
    }

    @objc private func chooseAssetFolder(_ sender: NSButton) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        beginFilePanel(panel) { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            self.model.setAssetFolder(url: url)
            self.assetFolderLabel.stringValue = url.path
        }
    }

    @objc private func clearAssetFolder(_ sender: NSButton) {
        model.setAssetFolder(url: nil)
        assetFolderLabel.stringValue = "Use built-in pixel icons"
    }

    private func beginFilePanel(_ panel: NSOpenPanel, completion: @escaping (NSApplication.ModalResponse) -> Void) {
        let dashboardLevel = parentWindow?.level
        let settingsLevel = window?.level
        parentWindow?.level = .normal
        window?.level = .floating
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 2)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        NSApp.activate(ignoringOtherApps: true)
        panel.begin { [weak self] response in
            guard let self else { return }
            panel.orderOut(nil)
            self.parentWindow?.level = dashboardLevel ?? .screenSaver
            self.window?.level = settingsLevel ?? NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
            self.window?.orderFrontRegardless()
            self.window?.makeKey()
            completion(response)
        }
    }

    @objc private func loadFont(_ sender: NSButton) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = ["ttf", "otf", "ttc"].compactMap { UTType(filenameExtension: $0) }
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        beginFilePanel(panel) { [weak self] response in
            guard response == .OK, let self else { return }
            var names = Set(NSFontManager.shared.availableFontFamilies)
            for url in panel.urls {
                let registeredURL = PixelFontRegistrar.importFont(from: url) ?? url
                for descriptor in CTFontManagerCreateFontDescriptorsFromURL(registeredURL as CFURL) as? [CTFontDescriptor] ?? [] {
                    if let family = CTFontDescriptorCopyAttribute(descriptor, kCTFontFamilyNameAttribute) as? String {
                        names.insert(family)
                    }
                    if let postScriptName = CTFontDescriptorCopyAttribute(descriptor, kCTFontNameAttribute) as? String {
                        names.insert(postScriptName)
                    }
                }
            }
            // FontManager's family cache can lag behind process registration;
            // include descriptor names so the imported font is immediately selectable.
            names.formUnion(NSFontManager.shared.availableFontFamilies)
            for row in self.styleRows.values { row.setFontNames(names.sorted()) }
        }
    }

    @objc private func resetStyles(_ sender: NSButton) {
        model.resetStyles()
        for (key, row) in styleRows { row.apply(style: model.styles.style(for: key)) }
    }

    fileprivate func styleChanged(key: DashboardStyleKey, fontName: String, size: CGFloat, color: NSColor, x: CGFloat, y: CGFloat, smoothRendering: Bool) {
        model.updateStyle(
            TextStyle(fontName: fontName, pointSize: max(size, 6), colorHex: color.hexString, x: x, y: y, smoothRendering: smoothRendering),
            for: key
        )
    }

    fileprivate func showColorPanel(for colorWell: NSColorWell) {
        let panel = NSColorPanel.shared
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.setTarget(colorWell)
        panel.orderFrontRegardless()
        DispatchQueue.main.async {
            let visible = DashboardDisplayPreference.preferredScreen().visibleFrame
            let frame = panel.frame
            panel.setFrameOrigin(NSPoint(
                x: min(max(visible.minX, visible.midX - frame.width / 2), visible.maxX - frame.width),
                y: min(max(visible.minY, visible.midY - frame.height / 2), visible.maxY - frame.height)
            ))
            panel.makeKeyAndOrderFront(nil)
        }
    }
}

private final class DashboardColorWell: NSColorWell {
    var onDoubleClick: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        if event.clickCount == 2 { onDoubleClick?() }
    }
}

private final class StyleRow: NSView {
    let key: DashboardStyleKey
    weak var owner: SettingsWindowController?
    private let fontPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let xField = NSTextField(string: "")
    private let yField = NSTextField(string: "")
    private let sizeField = NSTextField(string: "")
    private let colorWell = DashboardColorWell(frame: .zero)
    private let redField = NSTextField(string: "")
    private let greenField = NSTextField(string: "")
    private let blueField = NSTextField(string: "")
    private let smoothButton = NSButton(checkboxWithTitle: "Smooth + 8x", target: nil, action: nil)
    private var suppressColorCallback = false
    private var pendingRGB: [Int]?

    init(key: DashboardStyleKey, style: TextStyle, owner: SettingsWindowController) {
        self.key = key
        self.owner = owner
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedWhite: 0.90, alpha: 0.75).cgColor
        build(style: style)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func build(style: TextStyle) {
        let label = NSTextField(labelWithString: key.displayName)
        label.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        label.textColor = NSColor(calibratedWhite: 0.12, alpha: 1)
        label.frame = NSRect(x: 10, y: 10, width: 142, height: 18)
        addSubview(label)

        for field in [xField, yField] {
            field.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
            field.alignment = .right
            field.target = self
            field.action = #selector(positionChanged(_:))
            addSubview(field)
        }
        xField.frame = NSRect(x: 154, y: 7, width: 52, height: 24)
        yField.frame = NSRect(x: 212, y: 7, width: 52, height: 24)

        fontPopup.addItem(withTitle: "Pixel Grid (built-in)")
        fontPopup.addItems(withTitles: NSFontManager.shared.availableFontFamilies.sorted())
        fontPopup.frame = NSRect(x: 274, y: 6, width: 235, height: 26)
        fontPopup.target = self
        fontPopup.action = #selector(fontChanged(_:))
        addSubview(fontPopup)

        sizeField.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        sizeField.alignment = .right
        sizeField.frame = NSRect(x: 518, y: 7, width: 52, height: 24)
        sizeField.target = self
        sizeField.action = #selector(sizeChanged(_:))
        addSubview(sizeField)

        colorWell.frame = NSRect(x: 580, y: 5, width: 48, height: 28)
        colorWell.target = self
        colorWell.action = #selector(colorChanged(_:))
        colorWell.onDoubleClick = { [weak self] in
            guard let self else { return }
            self.owner?.showColorPanel(for: self.colorWell)
        }
        addSubview(colorWell)

        let rgbFields = [("R", redField, CGFloat(638)), ("G", greenField, CGFloat(696)), ("B", blueField, CGFloat(754))]
        for (title, field, x) in rgbFields {
            let label = NSTextField(labelWithString: title)
            label.font = NSFont.monospacedSystemFont(ofSize: 9, weight: .bold)
            label.textColor = NSColor(calibratedWhite: 0.18, alpha: 1)
            label.frame = NSRect(x: x, y: 11, width: 10, height: 16)
            addSubview(label)
            field.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
            field.alignment = .right
            field.frame = NSRect(x: x + 11, y: 7, width: 42, height: 24)
            field.target = self
            field.action = #selector(rgbChanged(_:))
            addSubview(field)
        }
        smoothButton.font = NSFont.systemFont(ofSize: 10)
        smoothButton.frame = NSRect(x: 814, y: 7, width: 90, height: 24)
        smoothButton.target = self
        smoothButton.action = #selector(smoothChanged(_:))
        addSubview(smoothButton)
        apply(style: style)
    }

    func setFontNames(_ names: [String]) {
        let current = fontPopup.indexOfSelectedItem == 0 ? TextStyle.builtInPixelFont : (fontPopup.titleOfSelectedItem ?? "Menlo")
        fontPopup.removeAllItems()
        fontPopup.addItem(withTitle: "Pixel Grid (built-in)")
        fontPopup.addItems(withTitles: names)
        if current == TextStyle.builtInPixelFont { fontPopup.selectItem(at: 0) }
        else { fontPopup.selectItem(withTitle: current) }
    }

    func apply(style: TextStyle) {
        pendingRGB = nil
        suppressColorCallback = false
        if style.fontName == TextStyle.builtInPixelFont {
            fontPopup.selectItem(at: 0)
        } else {
            if fontPopup.item(withTitle: style.fontName) == nil { fontPopup.addItem(withTitle: style.fontName) }
            fontPopup.selectItem(withTitle: style.fontName)
        }
        xField.stringValue = format(style.x)
        yField.stringValue = format(style.y)
        sizeField.stringValue = String(Int(style.pointSize.rounded()))
        colorWell.color = style.color
        smoothButton.state = style.smoothRendering ? .on : .off
        syncRGBFields()
    }

    private func selectedFontName() -> String {
        fontPopup.indexOfSelectedItem == 0 ? TextStyle.builtInPixelFont : (fontPopup.titleOfSelectedItem ?? "Menlo")
    }

    private func sendChange() {
        owner?.styleChanged(
            key: key,
            fontName: selectedFontName(),
            size: CGFloat(Double(sizeField.stringValue) ?? 12),
            color: colorWell.color,
            x: CGFloat(Double(xField.stringValue) ?? 0),
            y: CGFloat(Double(yField.stringValue) ?? 0),
            smoothRendering: smoothButton.state == .on
        )
    }

    @objc private func fontChanged(_ sender: NSPopUpButton) { sendChange() }
    @objc private func sizeChanged(_ sender: NSTextField) { sendChange() }
    @objc private func colorChanged(_ sender: NSColorWell) {
        guard !suppressColorCallback else { return }
        // Assigning NSColorWell.color from the RGB fields can enqueue a later
        // action. Ignore that echo so the values the user typed remain visible.
        if let pendingRGB, pendingRGB == currentColorRGBValues() { return }
        pendingRGB = nil
        syncRGBFields()
        sendChange()
    }
    @objc private func rgbChanged(_ sender: NSTextField) {
        let values = currentRGBValues()
        pendingRGB = values
        suppressColorCallback = true
        // Temporarily detach the target as well as suppressing the callback.
        // NSColorWell may deliver its action asynchronously after assignment.
        colorWell.target = nil
        colorWell.color = NSColor(
            calibratedRed: CGFloat(values[0]) / 255,
            green: CGFloat(values[1]) / 255,
            blue: CGFloat(values[2]) / 255,
            alpha: 1
        )
        sendChange()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.colorWell.target = self
            self.suppressColorCallback = false
        }
    }
    @objc private func positionChanged(_ sender: NSTextField) { sendChange() }
    @objc private func smoothChanged(_ sender: NSButton) { sendChange() }
    private func currentRGBValues() -> [Int] {
        [redField, greenField, blueField].map { field in
            min(max(Int(field.stringValue) ?? 0, 0), 255)
        }
    }
    private func currentColorRGBValues() -> [Int] {
        guard let rgb = colorWell.color.usingColorSpace(.deviceRGB) else { return [] }
        return [rgb.redComponent, rgb.greenComponent, rgb.blueComponent].map { component in
            Int(round(component * 255))
        }
    }
    private func syncRGBFields() {
        guard let rgb = colorWell.color.usingColorSpace(.deviceRGB) else { return }
        redField.stringValue = String(Int(round(rgb.redComponent * 255)))
        greenField.stringValue = String(Int(round(rgb.greenComponent * 255)))
        blueField.stringValue = String(Int(round(rgb.blueComponent * 255)))
    }

    private func format(_ value: CGFloat) -> String {
        String(format: "%.2f", Double(value)).replacingOccurrences(of: ".00", with: "")
    }
}

private final class WeatherSettingsWindowController: NSWindowController, NSWindowDelegate {
    private let model: DashboardModel
    private weak var parentWindow: NSWindow?
    private let sourcePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let iconSetPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let apiHostField = NSTextField(string: "")
    private let apiKeyField = NSSecureTextField(string: "")
    private let cityField = NSTextField(string: "")
    private let refreshField = NSTextField(string: "")
    private let iconXField = NSTextField(string: "")
    private let iconYField = NSTextField(string: "")
    private let iconSizeField = NSTextField(string: "")

    init(model: DashboardModel, parentWindow: NSWindow?) {
        self.model = model
        self.parentWindow = parentWindow
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 650, height: 570), styleMask: [.titled, .closable, .utilityWindow], backing: .buffered, defer: false)
        panel.title = "Weather Source Settings"
        panel.isFloatingPanel = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 2)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.backgroundColor = NSColor(calibratedWhite: 0.96, alpha: 1)
        panel.appearance = NSAppearance(named: .aqua)
        super.init(window: panel)
        panel.delegate = self
        buildContent()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func showWindow(_ sender: Any?) {
        reloadFields()
        super.showWindow(sender)
        NSApp.activate(ignoringOtherApps: true)
        if let panel = window {
            if let parentWindow, panel.parent == nil { parentWindow.addChildWindow(panel, ordered: .above) }
            panel.center()
            panel.orderFrontRegardless()
            panel.makeKey()
        }
    }

    func windowWillClose(_ notification: Notification) {
        guard let panel = window else { return }
        parentWindow?.removeChildWindow(panel)
        parentWindow?.makeKeyAndOrderFront(nil)
    }

    private func buildContent() {
        guard let content = window?.contentView else { return }
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor(calibratedWhite: 0.96, alpha: 1).cgColor

        let title = makeLabel("WEATHER SOURCE", size: 18, bold: true)
        title.textColor = NSColor(calibratedRed: 0.04, green: 0.31, blue: 0.38, alpha: 1)
        title.frame = NSRect(x: 28, y: 524, width: 560, height: 26)
        content.addSubview(title)

        addLabel("Source", y: 480, to: content)
        sourcePopup.addItems(withTitles: WeatherSource.allCases.map(\.displayName))
        sourcePopup.frame = NSRect(x: 220, y: 476, width: 380, height: 28)
        sourcePopup.target = self
        sourcePopup.action = #selector(sourceChanged(_:))
        content.addSubview(sourcePopup)

        addLabel("Weather icon set", y: 436, to: content)
        iconSetPopup.addItems(withTitles: WeatherIconSet.allCases.map(\.displayName))
        iconSetPopup.frame = NSRect(x: 220, y: 432, width: 380, height: 28)
        content.addSubview(iconSetPopup)

        addLabel("QWeather API Host", y: 392, to: content)
        configure(field: apiHostField, y: 388, placeholder: "abcxyz.qweatherapi.com", in: content)
        addLabel("QWeather API KEY", y: 348, to: content)
        configure(field: apiKeyField, y: 344, placeholder: "Stored in macOS Keychain", in: content)
        addLabel("City / Location", y: 304, to: content)
        configure(field: cityField, y: 300, placeholder: "Fuzhou / 101230101 / 119.30,26.08", in: content)
        addLabel("Refresh interval (min)", y: 260, to: content)
        configure(field: refreshField, y: 256, placeholder: "30", in: content)

        addLabel("Icon position X / Y", y: 216, to: content)
        iconXField.frame = NSRect(x: 220, y: 212, width: 180, height: 26)
        iconYField.frame = NSRect(x: 420, y: 212, width: 180, height: 26)
        for field in [iconXField, iconYField] {
            field.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
            content.addSubview(field)
        }
        addLabel("Icon size (px)", y: 172, to: content)
        configure(field: iconSizeField, y: 168, placeholder: "128", in: content)

        let note = NSTextField(wrappingLabelWithString: "QWeather is the default source. Copy your dedicated API Host from QWeather Console → Settings and create an API KEY credential under Project Management. The key is kept in macOS Keychain; the dashboard refreshes immediately after Apply.")
        note.font = NSFont.systemFont(ofSize: 11)
        note.textColor = NSColor.secondaryLabelColor
        note.frame = NSRect(x: 28, y: 68, width: 572, height: 70)
        content.addSubview(note)

        let apply = NSButton(title: "Apply & Refresh", target: self, action: #selector(apply(_:)))
        apply.bezelStyle = .rounded
        apply.frame = NSRect(x: 470, y: 24, width: 130, height: 28)
        content.addSubview(apply)
        reloadFields()
    }

    private func makeLabel(_ text: String, size: CGFloat, bold: Bool) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.monospacedSystemFont(ofSize: size, weight: bold ? .bold : .regular)
        label.textColor = NSColor(calibratedWhite: 0.12, alpha: 1)
        return label
    }

    private func addLabel(_ text: String, y: CGFloat, to view: NSView) {
        let label = makeLabel(text, size: 11, bold: true)
        label.frame = NSRect(x: 28, y: y, width: 185, height: 18)
        view.addSubview(label)
    }

    private func configure(field: NSTextField, y: CGFloat, placeholder: String, in view: NSView) {
        field.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        field.placeholderString = placeholder
        field.frame = NSRect(x: 220, y: y, width: 380, height: 26)
        view.addSubview(field)
    }

    private func reloadFields() {
        let settings = model.weatherSettings
        sourcePopup.selectItem(at: WeatherSource.allCases.firstIndex(of: settings.source) ?? 0)
        iconSetPopup.selectItem(at: WeatherIconSet.allCases.firstIndex(of: settings.iconSet) ?? 0)
        apiHostField.stringValue = settings.apiHost
        apiKeyField.stringValue = settings.apiKey
        cityField.stringValue = settings.city
        refreshField.stringValue = String(Int(settings.refreshInterval / 60))
        iconXField.stringValue = String(Int(settings.iconX))
        iconYField.stringValue = String(Int(settings.iconY))
        iconSizeField.stringValue = String(Int(settings.iconSize))
        updateFieldAvailability()
    }

    @objc private func sourceChanged(_ sender: NSPopUpButton) {
        updateFieldAvailability()
    }

    private func updateFieldAvailability() {
        let usesQWeather = sourcePopup.indexOfSelectedItem == 0
        apiHostField.isEnabled = usesQWeather
        apiKeyField.isEnabled = usesQWeather
    }

    @objc private func apply(_ sender: NSButton) {
        var settings = model.weatherSettings
        settings.source = WeatherSource.allCases[sourcePopup.indexOfSelectedItem]
        settings.iconSet = WeatherIconSet.allCases[iconSetPopup.indexOfSelectedItem]
        settings.apiHost = apiHostField.stringValue
        settings.apiKey = apiKeyField.stringValue
        settings.city = cityField.stringValue
        let minutes = Double(refreshField.stringValue) ?? settings.refreshInterval / 60
        settings.refreshInterval = minutes * 60
        settings.iconX = CGFloat(Double(iconXField.stringValue) ?? Double(settings.iconX))
        settings.iconY = CGFloat(Double(iconYField.stringValue) ?? Double(settings.iconY))
        settings.iconSize = CGFloat(Double(iconSizeField.stringValue) ?? Double(settings.iconSize))
        model.updateWeatherSettings(settings)
        window?.close()
    }
}

private final class PlanUsageSettingsWindowController: NSWindowController, NSWindowDelegate {
    private let model: DashboardModel
    private weak var parentWindow: NSWindow?
    private var fields: [String: NSTextField] = [:]
    private let statusLabel = NSTextField(wrappingLabelWithString: "")

    init(model: DashboardModel, parentWindow: NSWindow?) {
        self.model = model
        self.parentWindow = parentWindow
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 650, height: 400), styleMask: [.titled, .closable, .utilityWindow], backing: .buffered, defer: false)
        panel.title = "Plan Usage & OAuth"
        panel.isFloatingPanel = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 2)
        panel.backgroundColor = NSColor(calibratedWhite: 0.96, alpha: 1)
        panel.appearance = NSAppearance(named: .aqua)
        super.init(window: panel)
        panel.delegate = self
        buildContent()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func showWindow(_ sender: Any?) {
        reloadFields()
        super.showWindow(sender)
        window?.center()
        NSApp.activate(ignoringOtherApps: true)
        window?.orderFrontRegardless()
        window?.makeKey()
    }

    func windowWillClose(_ notification: Notification) {
        guard let window else { return }
        parentWindow?.removeChildWindow(window)
        parentWindow?.makeKeyAndOrderFront(nil)
    }

    private func buildContent() {
        guard let content = window?.contentView else { return }
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor(calibratedWhite: 0.96, alpha: 1).cgColor
        let title = label("PLAN USAGE / OAUTH", size: 18, bold: true)
        title.textColor = NSColor(calibratedRed: 0.04, green: 0.31, blue: 0.38, alpha: 1)
        title.frame = NSRect(x: 28, y: 356, width: 500, height: 26)
        content.addSubview(title)
        addField("Plan display name", key: "planLabel", value: "", y: 312, to: content)
        addField("Usage bucket ID", key: "limitID", value: "", y: 272, to: content)
        addField("Codex executable", key: "codexExecutable", value: "", y: 232, to: content)
        let schedule = label("BALANCE refresh: 10 min  ·  RESET refresh: 60 min", size: 11, bold: true)
        schedule.textColor = NSColor(calibratedRed: 0.04, green: 0.31, blue: 0.38, alpha: 1)
        schedule.frame = NSRect(x: 28, y: 196, width: 590, height: 18)
        content.addSubview(schedule)
        let note = NSTextField(wrappingLabelWithString: "ChatGPT OAuth is handled by the official Codex app-server and uses the same account as Codex. Tokens are stored and refreshed by Codex; Hermes Dashboard only reads the selected quota window. Leave the plan name blank to use the account plan type.")
        note.font = NSFont.systemFont(ofSize: 11)
        note.textColor = NSColor.secondaryLabelColor
        note.frame = NSRect(x: 28, y: 117, width: 590, height: 58)
        content.addSubview(note)

        statusLabel.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        statusLabel.textColor = NSColor.secondaryLabelColor
        statusLabel.frame = NSRect(x: 28, y: 72, width: 590, height: 36)
        content.addSubview(statusLabel)

        let authorize = NSButton(title: "Authorize with ChatGPT", target: self, action: #selector(authorize(_:)))
        authorize.bezelStyle = .rounded
        authorize.frame = NSRect(x: 28, y: 24, width: 180, height: 30)
        content.addSubview(authorize)
        let save = NSButton(title: "Apply & Refresh", target: self, action: #selector(apply(_:)))
        save.bezelStyle = .rounded
        save.frame = NSRect(x: 480, y: 24, width: 140, height: 30)
        content.addSubview(save)
        reloadFields()
    }

    private func label(_ text: String, size: CGFloat, bold: Bool = false) -> NSTextField {
        let value = NSTextField(labelWithString: text)
        value.font = NSFont.monospacedSystemFont(ofSize: size, weight: bold ? .bold : .regular)
        value.textColor = NSColor(calibratedWhite: 0.12, alpha: 1)
        return value
    }

    private func addField(_ title: String, key: String, value: String, y: CGFloat, to view: NSView) {
        let label = label(title, size: 11, bold: true)
        label.frame = NSRect(x: 28, y: y + 4, width: 190, height: 18)
        view.addSubview(label)
        let field = NSTextField(string: value)
        field.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        field.frame = NSRect(x: 220, y: y, width: 400, height: 26)
        view.addSubview(field)
        fields[key] = field
    }

    @objc private func apply(_ sender: NSButton) {
        saveFieldsAndRefresh()
        statusLabel.stringValue = "Refreshing plan usage…"
    }

    @objc private func authorize(_ sender: NSButton) {
        saveFieldsAndRefresh()
        sender.isEnabled = false
        statusLabel.stringValue = "Opening ChatGPT authorization…"
        model.beginPlanOAuth { [weak self, weak sender] message in
            self?.statusLabel.stringValue = message
            sender?.isEnabled = true
            self?.reloadFields()
        }
    }

    private func reloadFields() {
        guard !fields.isEmpty else { return }
        let settings = model.planUsageSettings
        fields["planLabel"]?.stringValue = settings.planLabel
        fields["limitID"]?.stringValue = settings.limitID
        fields["codexExecutable"]?.stringValue = settings.codexExecutable
        let identity = model.planUsage.email ?? "No ChatGPT account"
        statusLabel.stringValue = "\(identity) · \(model.planUsage.status) · \(model.planUsage.allowanceText) · RESET \(model.planUsage.resetCountdown())"
    }

    private func saveFieldsAndRefresh() {
        var settings = model.planUsageSettings
        settings.planLabel = fields["planLabel"]?.stringValue ?? settings.planLabel
        settings.limitID = fields["limitID"]?.stringValue ?? settings.limitID
        settings.codexExecutable = fields["codexExecutable"]?.stringValue ?? settings.codexExecutable
        settings.refreshInterval = 600
        model.updatePlanUsageSettings(settings)
    }
}

private final class RuntimeColorSettingsWindowController: NSWindowController, NSWindowDelegate {
    private let model: DashboardModel
    private weak var parentWindow: NSWindow?
    private let showColorPanel: (NSColorWell) -> Void
    private var rows: [RuntimeIconKey: (automatic: NSButton, well: DashboardColorWell, hex: NSTextField)] = [:]

    init(model: DashboardModel, parentWindow: NSWindow?, showColorPanel: @escaping (NSColorWell) -> Void) {
        self.model = model
        self.parentWindow = parentWindow
        self.showColorPanel = showColorPanel
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 520, height: 430), styleMask: [.titled, .closable, .utilityWindow], backing: .buffered, defer: false)
        panel.title = "Runtime Value Colors"
        panel.isFloatingPanel = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 2)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.backgroundColor = NSColor(calibratedWhite: 0.96, alpha: 1)
        panel.appearance = NSAppearance(named: .aqua)
        super.init(window: panel)
        panel.delegate = self
        buildContent()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func showWindow(_ sender: Any?) {
        reloadRows()
        super.showWindow(sender)
        if let panel = window {
            let frame = (parentWindow?.screen ?? DashboardDisplayPreference.preferredScreen()).visibleFrame
            panel.setFrameOrigin(NSPoint(x: frame.midX - panel.frame.width / 2, y: frame.midY - panel.frame.height / 2))
            if let parentWindow, panel.parent == nil { parentWindow.addChildWindow(panel, ordered: .above) }
            NSApp.activate(ignoringOtherApps: true)
            panel.orderFrontRegardless()
            panel.makeKey()
        }
    }

    func windowWillClose(_ notification: Notification) {
        for row in rows.values { row.well.deactivate() }
        guard let window else { return }
        parentWindow?.removeChildWindow(window)
        parentWindow?.makeKeyAndOrderFront(nil)
    }

    private func buildContent() {
        guard let content = window?.contentView else { return }
        let title = NSTextField(labelWithString: "RUNTIME VALUE COLORS")
        title.font = NSFont.monospacedSystemFont(ofSize: 18, weight: .bold)
        title.textColor = NSColor(calibratedRed: 0.04, green: 0.31, blue: 0.38, alpha: 1)
        title.frame = NSRect(x: 28, y: 386, width: 460, height: 26)
        content.addSubview(title)
        for (text, x) in [("FIELD", CGFloat(28)), ("MODE", 145), ("COLOR", 250), ("HEX / RRGGBB", 322)] {
            let label = NSTextField(labelWithString: text)
            label.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .bold)
            label.textColor = NSColor.secondaryLabelColor
            label.frame = NSRect(x: x, y: 351, width: 140, height: 18)
            content.addSubview(label)
        }
        for (index, key) in RuntimeIconKey.allCases.enumerated() {
            let y = 312 - CGFloat(index) * 40
            let label = NSTextField(labelWithString: key.displayName)
            label.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .bold)
            label.frame = NSRect(x: 28, y: y + 4, width: 110, height: 20)
            content.addSubview(label)
            let automatic = NSButton(checkboxWithTitle: "Auto", target: self, action: #selector(automaticChanged(_:)))
            automatic.frame = NSRect(x: 145, y: y, width: 85, height: 28)
            automatic.tag = index
            content.addSubview(automatic)
            let well = DashboardColorWell(frame: NSRect(x: 248, y: y, width: 48, height: 28))
            well.tag = index
            well.target = self
            well.action = #selector(colorChanged(_:))
            well.onDoubleClick = { [weak self, weak well] in
                guard let self, let well else { return }
                self.showColorPanel(well)
            }
            well.setAccessibilityLabel("\(key.displayName) value color")
            content.addSubview(well)
            let hex = NSTextField(string: "")
            hex.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
            hex.frame = NSRect(x: 322, y: y, width: 140, height: 28)
            hex.tag = index
            hex.target = self
            hex.action = #selector(hexChanged(_:))
            hex.setAccessibilityLabel("\(key.displayName) value hex color")
            content.addSubview(hex)
            rows[key] = (automatic, well, hex)
        }
        let note = NSTextField(wrappingLabelWithString: "Right-hand field values only. Auto follows status colors. Choose a color or enter HEX; changes are saved immediately.")
        note.font = NSFont.systemFont(ofSize: 11)
        note.textColor = NSColor.secondaryLabelColor
        note.frame = NSRect(x: 28, y: 18, width: 464, height: 38)
        content.addSubview(note)
        reloadRows()
    }

    private func reloadRows() {
        for (key, row) in rows {
            row.automatic.state = model.layout.runtimeValueColors[key.rawValue] == nil ? .on : .off
            let color = model.runtimeValueColor(for: key)
            row.well.color = color
            row.hex.stringValue = color.hexString
        }
    }

    private func save(_ color: NSColor?, for key: RuntimeIconKey) {
        var layout = model.layout
        layout.runtimeValueColors[key.rawValue] = color?.hexString
        model.updateLayout(layout)
        reloadRows()
    }

    @objc private func automaticChanged(_ sender: NSButton) {
        let key = RuntimeIconKey.allCases[sender.tag]
        save(sender.state == .on ? nil : model.runtimeValueColor(for: key), for: key)
    }

    @objc private func colorChanged(_ sender: NSColorWell) {
        let key = RuntimeIconKey.allCases[sender.tag]
        // Assigning a color during reload must not turn Auto into an override.
        guard sender.color.hexString != model.runtimeValueColor(for: key).hexString else { return }
        save(sender.color, for: key)
    }

    @objc private func hexChanged(_ sender: NSTextField) {
        let key = RuntimeIconKey.allCases[sender.tag]
        guard let color = NSColor(hex: sender.stringValue) else {
            reloadRows()
            return
        }
        save(color, for: key)
    }
}

private final class RuntimeIconSettingsWindowController: NSWindowController, NSWindowDelegate {
    private let model: DashboardModel
    private weak var parentWindow: NSWindow?
    private var rows: [(RuntimeIconKey, NSPopUpButton, NSTextField, NSTextField, NSTextField, NSTextField)] = []

    init(model: DashboardModel, parentWindow: NSWindow?) {
        self.model = model
        self.parentWindow = parentWindow
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 730, height: 390), styleMask: [.titled, .closable, .utilityWindow], backing: .buffered, defer: false)
        panel.title = "Runtime Status Icons"
        panel.isFloatingPanel = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 2)
        panel.backgroundColor = NSColor(calibratedWhite: 0.96, alpha: 1)
        panel.appearance = NSAppearance(named: .aqua)
        super.init(window: panel)
        panel.delegate = self
        buildContent()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.center()
        NSApp.activate(ignoringOtherApps: true)
        window?.orderFrontRegardless()
        window?.makeKey()
    }

    func windowWillClose(_ notification: Notification) {
        guard let window else { return }
        parentWindow?.removeChildWindow(window)
        parentWindow?.makeKeyAndOrderFront(nil)
    }

    private func buildContent() {
        guard let content = window?.contentView else { return }
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor(calibratedWhite: 0.96, alpha: 1).cgColor
        let title = NSTextField(labelWithString: "RUNTIME STATUS ICONS")
        title.font = NSFont.monospacedSystemFont(ofSize: 18, weight: .bold)
        title.textColor = NSColor(calibratedRed: 0.04, green: 0.31, blue: 0.38, alpha: 1)
        title.frame = NSRect(x: 28, y: 346, width: 500, height: 26)
        content.addSubview(title)
        for (text, x, width) in [("SOURCE", CGFloat(145), CGFloat(150)), ("X", 320, 60), ("Y", 390, 60), ("SIZE", 460, 60), ("CUSTOM FILE", 530, 170)] {
            let heading = NSTextField(labelWithString: text)
            heading.font = NSFont.monospacedSystemFont(ofSize: 9, weight: .bold)
            heading.textColor = NSColor.secondaryLabelColor
            heading.frame = NSRect(x: x, y: 318, width: width, height: 16)
            content.addSubview(heading)
        }
        for (index, key) in RuntimeIconKey.allCases.enumerated() {
            let y = 282 - CGFloat(index) * 36
            let label = NSTextField(labelWithString: key.displayName)
            label.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .bold)
            label.textColor = NSColor(calibratedWhite: 0.12, alpha: 1)
            label.frame = NSRect(x: 28, y: y + 4, width: 110, height: 18)
            content.addSubview(label)
            let popup = NSPopUpButton(frame: NSRect(x: 145, y: y, width: 150, height: 26), pullsDown: false)
            popup.addItems(withTitles: (0..<6).map { "Pattern \($0 + 1)" } + ["Bundled icon", "Custom file"])
            let current = model.layout.runtimeIcons[key.rawValue] ?? DashboardLayout.defaultRuntimeIcons[key.rawValue]!
            if current.name.hasPrefix("bundle:") {
                popup.selectItem(at: 6)
            } else if current.name.hasPrefix("file:") {
                popup.selectItem(at: 7)
            } else {
                popup.selectItem(at: current.pattern)
            }
            content.addSubview(popup)
            let xField = NSTextField(string: format(current.x))
            xField.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
            xField.frame = NSRect(x: 320, y: y, width: 60, height: 26)
            content.addSubview(xField)
            let yField = NSTextField(string: format(current.y))
            yField.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
            yField.frame = NSRect(x: 390, y: y, width: 60, height: 26)
            content.addSubview(yField)
            let sizeField = NSTextField(string: format(current.size))
            sizeField.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
            sizeField.frame = NSRect(x: 460, y: y, width: 60, height: 26)
            content.addSubview(sizeField)
            let path = NSTextField(string: current.name.hasPrefix("file:") ? String(current.name.dropFirst(5)) : "")
            path.font = NSFont.monospacedSystemFont(ofSize: 9, weight: .regular)
            path.placeholderString = "PNG/GIF path for Custom file"
            path.frame = NSRect(x: 530, y: y, width: 170, height: 26)
            content.addSubview(path)
            rows.append((key, popup, xField, yField, sizeField, path))
        }
        let apply = NSButton(title: "Apply", target: self, action: #selector(apply(_:)))
        apply.bezelStyle = .rounded
        apply.frame = NSRect(x: 610, y: 18, width: 90, height: 28)
        content.addSubview(apply)
    }

    @objc private func apply(_ sender: NSButton) {
        var layout = model.layout
        for (key, popup, x, y, size, path) in rows {
            let name: String
            switch popup.indexOfSelectedItem {
            case 0..<6:
                name = "pattern-\(popup.indexOfSelectedItem)"
            case 6:
                name = DashboardLayout.defaultRuntimeIcons[key.rawValue]?.name ?? "pattern-0"
            default:
                let customPath = path.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                name = customPath.isEmpty ? (layout.runtimeIcons[key.rawValue]?.name ?? "pattern-0") : "file:\(customPath)"
            }
            let iconSize = min(max(CGFloat(Double(size.stringValue) ?? 24), 8), 96)
            layout.runtimeIcons[key.rawValue] = RuntimeIconStyle(name: name, x: CGFloat(Double(x.stringValue) ?? 28), y: CGFloat(Double(y.stringValue) ?? 5), size: iconSize)
        }
        model.updateLayout(layout)
        window?.close()
    }

    private func format(_ value: CGFloat) -> String {
        String(format: "%.2f", Double(value)).replacingOccurrences(of: ".00", with: "")
    }
}

private final class LayoutSettingsWindowController: NSWindowController, NSWindowDelegate {
    private enum FieldTag {
        static let padding = 1
        static let runtimeX = 10
        static let runtimeY = 11
        static let agentX = 20
        static let agentY = 21
        static let sessionX = 30
        static let sessionY = 31
        static let runtimeOpacity = 40
        static let agentOpacity = 41
        static let sessionOpacity = 42
        static let sessionCardOpacity = 43
        static let runtimeTitleSpacing = 44
        static let runtimeIconTitleSpacing = 45
    }

    private let model: DashboardModel
    private weak var parentWindow: NSWindow?
    private var fields: [Int: NSTextField] = [:]
    private var runtimeIconController: RuntimeIconSettingsWindowController?

    init(model: DashboardModel, parentWindow: NSWindow?) {
        self.model = model
        self.parentWindow = parentWindow
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 600, height: 500), styleMask: [.titled, .closable, .utilityWindow], backing: .buffered, defer: false)
        panel.title = "Dashboard Layout & Opacity"
        panel.isFloatingPanel = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 2)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.backgroundColor = NSColor(calibratedWhite: 0.96, alpha: 1)
        panel.appearance = NSAppearance(named: .aqua)
        super.init(window: panel)
        panel.delegate = self
        buildContent()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        reloadFields()
        NSApp.activate(ignoringOtherApps: true)
        if let panel = window {
            if let parentWindow, panel.parent == nil {
                parentWindow.addChildWindow(panel, ordered: .above)
            }
            panel.center()
            panel.orderFrontRegardless()
            panel.makeKey()
        }
    }

    func windowWillClose(_ notification: Notification) {
        guard let panel = window else { return }
        parentWindow?.removeChildWindow(panel)
        parentWindow?.makeKeyAndOrderFront(nil)
    }

    private func buildContent() {
        guard let content = window?.contentView else { return }
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor(calibratedWhite: 0.96, alpha: 1).cgColor

        let title = NSTextField(labelWithString: "LAYOUT / MODULE OPACITY")
        title.font = NSFont.monospacedSystemFont(ofSize: 18, weight: .bold)
        title.textColor = NSColor(calibratedRed: 0.04, green: 0.31, blue: 0.38, alpha: 1)
        title.frame = NSRect(x: 28, y: 460, width: 520, height: 26)
        content.addSubview(title)

        addLabel("CANVAS PADDING", x: 28, y: 422, width: 220, to: content)
        addField(tag: FieldTag.padding, value: model.layout.padding, x: 270, y: 418, to: content)
        addPositionRow("RUNTIME STATUS", position: model.layout.runtimeStatus, xTag: FieldTag.runtimeX, yTag: FieldTag.runtimeY, y: 378, to: content)
        addPositionRow("HERMES AGENT", position: model.layout.hermesAgent, xTag: FieldTag.agentX, yTag: FieldTag.agentY, y: 338, to: content)
        addPositionRow("ACTIVE SESSION", position: model.layout.activeSession, xTag: FieldTag.sessionX, yTag: FieldTag.sessionY, y: 298, to: content)

        addLabel("MODULE BACKGROUND OPACITY (0.0 - 1.0)", x: 28, y: 258, width: 360, to: content)
        addLabel("RUNTIME", x: 28, y: 218, width: 100, to: content)
        addField(tag: FieldTag.runtimeOpacity, value: model.layout.runtimeOpacity, x: 130, y: 214, to: content)
        addLabel("AGENT", x: 220, y: 218, width: 80, to: content)
        addField(tag: FieldTag.agentOpacity, value: model.layout.agentOpacity, x: 300, y: 214, to: content)
        addLabel("SESSION", x: 390, y: 218, width: 90, to: content)
        addField(tag: FieldTag.sessionOpacity, value: model.layout.activeSessionOpacity, x: 480, y: 214, to: content)
        addLabel("SESSION CARDS", x: 28, y: 178, width: 120, to: content)
        addField(tag: FieldTag.sessionCardOpacity, value: model.layout.sessionCardOpacity, x: 160, y: 174, to: content)

        addLabel("TITLE / CONTENT GAP", x: 28, y: 138, width: 220, to: content)
        addField(tag: FieldTag.runtimeTitleSpacing, value: model.layout.runtimeTitleSpacing, x: 270, y: 134, to: content)
        addLabel("ICON / TITLE GAP", x: 28, y: 98, width: 220, to: content)
        addField(tag: FieldTag.runtimeIconTitleSpacing, value: model.layout.runtimeIconTitleSpacing, x: 270, y: 94, to: content)
        let iconButton = NSButton(title: "Runtime Icons…", target: self, action: #selector(showRuntimeIcons(_:)))
        iconButton.bezelStyle = .rounded
        iconButton.frame = NSRect(x: 370, y: 132, width: 130, height: 28)
        content.addSubview(iconButton)

        let note = NSTextField(wrappingLabelWithString: "X / Y values are design-canvas coordinates. Changes apply immediately and are saved for the next launch.")
        note.font = NSFont.systemFont(ofSize: 11)
        note.textColor = NSColor.secondaryLabelColor
        note.frame = NSRect(x: 28, y: 48, width: 520, height: 40)
        content.addSubview(note)
    }

    private func addLabel(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat, to view: NSView) {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .bold)
        label.textColor = NSColor(calibratedWhite: 0.12, alpha: 1)
        label.frame = NSRect(x: x, y: y, width: width, height: 18)
        view.addSubview(label)
    }

    private func addPositionRow(_ title: String, position: DashboardModulePosition, xTag: Int, yTag: Int, y: CGFloat, to view: NSView) {
        addLabel(title, x: 28, y: y + 4, width: 220, to: view)
        addLabel("X", x: 250, y: y + 4, width: 18, to: view)
        addField(tag: xTag, value: position.x, x: 272, y: y, to: view)
        addLabel("Y", x: 360, y: y + 4, width: 18, to: view)
        addField(tag: yTag, value: position.y, x: 382, y: y, to: view)
    }

    private func addField(tag: Int, value: CGFloat, x: CGFloat, y: CGFloat, to view: NSView) {
        let field = NSTextField(string: format(value))
        field.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        field.alignment = .right
        field.tag = tag
        field.frame = NSRect(x: x, y: y, width: 70, height: 24)
        field.target = self
        field.action = #selector(valueChanged(_:))
        view.addSubview(field)
        fields[tag] = field
    }

    private func format(_ value: CGFloat) -> String {
        String(format: "%.2f", Double(value)).replacingOccurrences(of: ".00", with: "")
    }

    private func reloadFields() {
        let values: [Int: CGFloat] = [
            FieldTag.padding: model.layout.padding,
            FieldTag.runtimeX: model.layout.runtimeStatus.x,
            FieldTag.runtimeY: model.layout.runtimeStatus.y,
            FieldTag.agentX: model.layout.hermesAgent.x,
            FieldTag.agentY: model.layout.hermesAgent.y,
            FieldTag.sessionX: model.layout.activeSession.x,
            FieldTag.sessionY: model.layout.activeSession.y,
            FieldTag.runtimeOpacity: model.layout.runtimeOpacity,
            FieldTag.agentOpacity: model.layout.agentOpacity,
            FieldTag.sessionOpacity: model.layout.activeSessionOpacity,
            FieldTag.sessionCardOpacity: model.layout.sessionCardOpacity
            ,FieldTag.runtimeTitleSpacing: model.layout.runtimeTitleSpacing,
            FieldTag.runtimeIconTitleSpacing: model.layout.runtimeIconTitleSpacing
        ]
        for (tag, value) in values { fields[tag]?.stringValue = format(value) }
    }

    @objc private func valueChanged(_ sender: NSTextField) {
        var layout = model.layout
        let value: (Int) -> CGFloat = { tag in CGFloat(Double(self.fields[tag]?.stringValue ?? "") ?? 0) }
        layout.padding = min(max(value(FieldTag.padding), 0), 120)
        layout.runtimeStatus = DashboardModulePosition(x: value(FieldTag.runtimeX), y: value(FieldTag.runtimeY))
        layout.hermesAgent = DashboardModulePosition(x: value(FieldTag.agentX), y: value(FieldTag.agentY))
        layout.activeSession = DashboardModulePosition(x: value(FieldTag.sessionX), y: value(FieldTag.sessionY))
        layout.runtimeOpacity = min(max(value(FieldTag.runtimeOpacity), 0), 1)
        layout.agentOpacity = min(max(value(FieldTag.agentOpacity), 0), 1)
        layout.activeSessionOpacity = min(max(value(FieldTag.sessionOpacity), 0), 1)
        layout.sessionCardOpacity = min(max(value(FieldTag.sessionCardOpacity), 0), 1)
        layout.runtimeTitleSpacing = min(max(value(FieldTag.runtimeTitleSpacing), 0), 120)
        layout.runtimeIconTitleSpacing = min(max(value(FieldTag.runtimeIconTitleSpacing), 0), 120)
        model.updateLayout(layout)
        reloadFields()
    }

    @objc private func showRuntimeIcons(_ sender: NSButton) {
        if runtimeIconController == nil { runtimeIconController = RuntimeIconSettingsWindowController(model: model, parentWindow: window) }
        runtimeIconController?.showWindow(nil)
    }
}
