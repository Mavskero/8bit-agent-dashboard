import AppKit
import CoreText
import UniformTypeIdentifiers

final class SettingsWindowController: NSWindowController {
    private let model: DashboardModel
    private let sourcePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let wallpaperLabel = NSTextField(labelWithString: "No GIF selected")
    private let assetFolderLabel = NSTextField(labelWithString: "Use built-in pixel icons")
    private let statusPathLabel = NSTextField(labelWithString: "")
    private var styleRows: [DashboardStyleKey: StyleRow] = [:]

    init(model: DashboardModel) {
        self.model = model
        let window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 820, height: 720), styleMask: [.titled, .closable, .utilityWindow], backing: .buffered, defer: false)
        window.title = "Hermes Dashboard Settings"
        window.isFloatingPanel = true
        window.level = .floating
        window.backgroundColor = NSColor(calibratedWhite: 0.08, alpha: 1)
        window.minSize = NSSize(width: 760, height: 620)
        super.init(window: window)
        buildContent()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.center()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
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

        let wallpaperTitle = makeLabel("GIF WALLPAPER")
        wallpaperTitle.frame = NSRect(x: 28, y: 580, width: 240, height: 20)
        content.addSubview(wallpaperTitle)
        wallpaperLabel.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        wallpaperLabel.textColor = PixelPalette.cream
        wallpaperLabel.lineBreakMode = .byTruncatingMiddle
        wallpaperLabel.stringValue = model.wallpaperPath ?? "No GIF selected"
        wallpaperLabel.frame = NSRect(x: 280, y: 580, width: 350, height: 20)
        content.addSubview(wallpaperLabel)
        addButton("Choose GIF…", x: 640, y: 576, width: 80, action: #selector(chooseWallpaper(_:)), to: content)
        addButton("Clear", x: 728, y: 576, width: 54, action: #selector(clearWallpaper(_:)), to: content)

        let assetTitle = makeLabel("WEATHER / AGENT ASSET FOLDER")
        assetTitle.frame = NSRect(x: 28, y: 534, width: 240, height: 20)
        content.addSubview(assetTitle)
        assetFolderLabel.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        assetFolderLabel.textColor = PixelPalette.cream
        assetFolderLabel.lineBreakMode = .byTruncatingMiddle
        assetFolderLabel.stringValue = model.assetFolderPath ?? "Use built-in pixel icons"
        assetFolderLabel.frame = NSRect(x: 280, y: 534, width: 350, height: 20)
        content.addSubview(assetFolderLabel)
        addButton("Choose Folder…", x: 640, y: 530, width: 100, action: #selector(chooseAssetFolder(_:)), to: content)
        addButton("Clear", x: 748, y: 530, width: 54, action: #selector(clearAssetFolder(_:)), to: content)

        let assetHint = NSTextField(wrappingLabelWithString: "Optional names: weather-clear.png / weather-rain.gif and hermes-working.png / hermes-thinking.gif / hermes-done.png. Subfolders weather/, hermes/ and icons/ are also searched.")
        assetHint.font = NSFont.systemFont(ofSize: 10)
        assetHint.textColor = NSColor.secondaryLabelColor
        assetHint.frame = NSRect(x: 280, y: 486, width: 470, height: 38)
        content.addSubview(assetHint)

        let styleTitle = makeLabel("TEXT STYLE OVERRIDES")
        styleTitle.frame = NSRect(x: 28, y: 449, width: 300, height: 20)
        content.addSubview(styleTitle)
        let columnHint = NSTextField(labelWithString: "POSITION                                      FONT FAMILY                         SIZE       COLOR")
        columnHint.font = NSFont.monospacedSystemFont(ofSize: 9, weight: .regular)
        columnHint.textColor = PixelPalette.cyanDim
        columnHint.frame = NSRect(x: 38, y: 426, width: 730, height: 16)
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
        let scroll = NSScrollView(frame: NSRect(x: 28, y: 82, width: 750, height: 334))
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

    @objc private func sourceChanged(_ sender: NSPopUpButton) {
        model.runtimeSource = sender.indexOfSelectedItem == 0 ? .codex : .hermes
        updateStatusPathLabel()
    }

    private func updateStatusPathLabel() {
        let folder = model.runtimeSource == .codex ? "Codex" : "HermesAgent"
        statusPathLabel.stringValue = "Status: ~/Library/Application Support/\(folder)/status.json    •    Shortcut: ⌘, or S"
    }

    @objc private func chooseWallpaper(_ sender: NSButton) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.gif]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { [weak self] response in
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
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            self.model.setAssetFolder(url: url)
            self.assetFolderLabel.stringValue = url.path
        }
    }

    @objc private func clearAssetFolder(_ sender: NSButton) {
        model.setAssetFolder(url: nil)
        assetFolderLabel.stringValue = "Use built-in pixel icons"
    }

    @objc private func loadFont(_ sender: NSButton) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.font]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.begin { [weak self] response in
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

    fileprivate func styleChanged(key: DashboardStyleKey, fontName: String, size: CGFloat, color: NSColor) {
        model.updateStyle(TextStyle(fontName: fontName, pointSize: max(size, 6), colorHex: color.hexString), for: key)
    }
}

private final class StyleRow: NSView {
    let key: DashboardStyleKey
    weak var owner: SettingsWindowController?
    private let fontPopup = NSPopUpButton(frame: .zero, pullsDown: false)
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
        label.frame = NSRect(x: 10, y: 10, width: 190, height: 18)
        addSubview(label)

        fontPopup.addItem(withTitle: "Pixel Grid (built-in)")
        fontPopup.addItems(withTitles: NSFontManager.shared.availableFontFamilies.sorted())
        fontPopup.frame = NSRect(x: 205, y: 6, width: 300, height: 26)
        fontPopup.target = self
        fontPopup.action = #selector(fontChanged(_:))
        addSubview(fontPopup)

        sizeField.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        sizeField.alignment = .right
        sizeField.frame = NSRect(x: 516, y: 7, width: 58, height: 24)
        sizeField.target = self
        sizeField.action = #selector(sizeChanged(_:))
        addSubview(sizeField)

        colorWell.frame = NSRect(x: 594, y: 5, width: 48, height: 28)
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
        sizeField.stringValue = String(Int(style.pointSize.rounded()))
        colorWell.color = style.color
    }

    private func selectedFontName() -> String {
        fontPopup.indexOfSelectedItem == 0 ? TextStyle.builtInPixelFont : (fontPopup.titleOfSelectedItem ?? "Menlo")
    }

    private func sendChange() {
        owner?.styleChanged(key: key, fontName: selectedFontName(), size: CGFloat(Double(sizeField.stringValue) ?? 12), color: colorWell.color)
    }

    @objc private func fontChanged(_ sender: NSPopUpButton) { sendChange() }
    @objc private func sizeChanged(_ sender: NSTextField) { sendChange() }
    @objc private func colorChanged(_ sender: NSColorWell) { sendChange() }
}
