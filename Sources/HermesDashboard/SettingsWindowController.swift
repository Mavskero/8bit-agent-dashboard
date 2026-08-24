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

    init(model: DashboardModel, parentWindow: NSWindow?, onDisplayChanged: @escaping (NSScreen) -> Void) {
        self.model = model
        self.parentWindow = parentWindow
        self.onDisplayChanged = onDisplayChanged
        let window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 820, height: 720), styleMask: [.titled, .closable, .utilityWindow], backing: .buffered, defer: false)
        window.title = "Hermes Dashboard Settings"
        window.isFloatingPanel = true
        window.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.hidesOnDeactivate = false
        window.backgroundColor = NSColor(calibratedWhite: 0.08, alpha: 1)
        window.minSize = NSSize(width: 760, height: 620)
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
        content.layer?.backgroundColor = NSColor(calibratedWhite: 0.08, alpha: 1).cgColor

        let title = NSTextField(labelWithString: "DASHBOARD CONTROL")
        title.font = NSFont.monospacedSystemFont(ofSize: 18, weight: .bold)
        title.textColor = PixelPalette.cyan
        title.frame = NSRect(x: 28, y: 674, width: 750, height: 26)
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

        let displayLabel = makeLabel("DEFAULT DISPLAY")
        displayLabel.frame = NSRect(x: 28, y: 584, width: 240, height: 20)
        content.addSubview(displayLabel)
        displayPopup.frame = NSRect(x: 280, y: 580, width: 360, height: 28)
        displayPopup.target = self
        displayPopup.action = #selector(displayChanged(_:))
        content.addSubview(displayPopup)
        reloadDisplays()

        let wallpaperTitle = makeLabel("GIF WALLPAPER")
        wallpaperTitle.frame = NSRect(x: 28, y: 540, width: 240, height: 20)
        content.addSubview(wallpaperTitle)
        wallpaperLabel.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        wallpaperLabel.textColor = PixelPalette.cream
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
        assetFolderLabel.textColor = PixelPalette.cream
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
        let styleTitle = makeLabel("TEXT STYLE OVERRIDES")
        styleTitle.frame = NSRect(x: 28, y: 376, width: 300, height: 20)
        content.addSubview(styleTitle)
        let columnHint = NSTextField(labelWithString: "POSITION X       Y       FONT FAMILY                         SIZE       COLOR")
        columnHint.font = NSFont.monospacedSystemFont(ofSize: 9, weight: .regular)
        columnHint.textColor = PixelPalette.cyanDim
        columnHint.frame = NSRect(x: 38, y: 353, width: 730, height: 16)
        content.addSubview(columnHint)

        let documentHeight = CGFloat(DashboardStyleKey.allCases.count) * 44 + 12
        let document = NSView(frame: NSRect(x: 0, y: 0, width: 760, height: documentHeight))
        for (index, key) in DashboardStyleKey.allCases.enumerated() {
            let y = documentHeight - CGFloat(index + 1) * 44
            let row = StyleRow(key: key, style: model.styles.style(for: key), owner: self)
            row.frame = NSRect(x: 20, y: y, width: 720, height: 40)
            document.addSubview(row)
            styleRows[key] = row
        }
        let scroll = NSScrollView(frame: NSRect(x: 28, y: 82, width: 750, height: 260))
        scroll.documentView = document
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        content.addSubview(scroll)

        addButton("Load Font…", x: 28, y: 44, width: 100, action: #selector(loadFont(_:)), to: content)
        addButton("Reset Text Styles", x: 140, y: 44, width: 130, action: #selector(resetStyles(_:)), to: content)
        let note = NSTextField(wrappingLabelWithString: "Styles are saved immediately. Built-in Pixel Grid keeps the original 8-bit look; Load Font… registers a local .ttf/.otf/.ttc font for the popups.")
        note.font = NSFont.systemFont(ofSize: 10)
        note.textColor = NSColor.secondaryLabelColor
        note.frame = NSRect(x: 290, y: 42, width: 480, height: 28)
        content.addSubview(note)

        statusPathLabel.font = NSFont.monospacedSystemFont(ofSize: 9, weight: .regular)
        statusPathLabel.textColor = PixelPalette.cyanDim
        statusPathLabel.frame = NSRect(x: 28, y: 18, width: 750, height: 18)
        content.addSubview(statusPathLabel)
        updateStatusPathLabel()
    }

    private func makeLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .bold)
        label.textColor = PixelPalette.cream
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
        panel.allowedContentTypes = [.font]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        beginFilePanel(panel) { [weak self] response in
            guard response == .OK, let self else { return }
            for url in panel.urls { _ = CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil) }
            let names = NSFontManager.shared.availableFontFamilies.sorted()
            for row in self.styleRows.values { row.setFontNames(names) }
        }
    }

    @objc private func resetStyles(_ sender: NSButton) {
        model.resetStyles()
        for (key, row) in styleRows { row.apply(style: model.styles.style(for: key)) }
    }

    fileprivate func styleChanged(key: DashboardStyleKey, fontName: String, size: CGFloat, color: NSColor, x: CGFloat, y: CGFloat) {
        model.updateStyle(
            TextStyle(fontName: fontName, pointSize: max(size, 6), colorHex: color.hexString, x: x, y: y),
            for: key
        )
    }
}

private final class StyleRow: NSView {
    let key: DashboardStyleKey
    weak var owner: SettingsWindowController?
    private let fontPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let xField = NSTextField(string: "")
    private let yField = NSTextField(string: "")
    private let sizeField = NSTextField(string: "")
    private let colorWell = NSColorWell(frame: .zero)

    init(key: DashboardStyleKey, style: TextStyle, owner: SettingsWindowController) {
        self.key = key
        self.owner = owner
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedWhite: 0.12, alpha: 0.35).cgColor
        build(style: style)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func build(style: TextStyle) {
        let label = NSTextField(labelWithString: key.displayName)
        label.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        label.textColor = PixelPalette.cream
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

        colorWell.frame = NSRect(x: 586, y: 5, width: 48, height: 28)
        colorWell.target = self
        colorWell.action = #selector(colorChanged(_:))
        addSubview(colorWell)
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
            y: CGFloat(Double(yField.stringValue) ?? 0)
        )
    }

    @objc private func fontChanged(_ sender: NSPopUpButton) { sendChange() }
    @objc private func sizeChanged(_ sender: NSTextField) { sendChange() }
    @objc private func colorChanged(_ sender: NSColorWell) { sendChange() }
    @objc private func positionChanged(_ sender: NSTextField) { sendChange() }

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
    }

    private let model: DashboardModel
    private weak var parentWindow: NSWindow?
    private var fields: [Int: NSTextField] = [:]

    init(model: DashboardModel, parentWindow: NSWindow?) {
        self.model = model
        self.parentWindow = parentWindow
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 600, height: 500), styleMask: [.titled, .closable, .utilityWindow], backing: .buffered, defer: false)
        panel.title = "Dashboard Layout & Opacity"
        panel.isFloatingPanel = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 2)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.backgroundColor = NSColor(calibratedWhite: 0.08, alpha: 1)
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
        content.layer?.backgroundColor = NSColor(calibratedWhite: 0.08, alpha: 1).cgColor

        let title = NSTextField(labelWithString: "LAYOUT / MODULE OPACITY")
        title.font = NSFont.monospacedSystemFont(ofSize: 18, weight: .bold)
        title.textColor = PixelPalette.cyan
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

        let note = NSTextField(wrappingLabelWithString: "X / Y values are design-canvas coordinates. Changes apply immediately and are saved for the next launch.")
        note.font = NSFont.systemFont(ofSize: 11)
        note.textColor = NSColor.secondaryLabelColor
        note.frame = NSRect(x: 28, y: 120, width: 520, height: 40)
        content.addSubview(note)
    }

    private func addLabel(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat, to view: NSView) {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .bold)
        label.textColor = PixelPalette.cream
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
        model.updateLayout(layout)
        reloadFields()
    }
}
