import AppKit
import CoreText

enum PixelFontRegistrar {
    static func registerBundledFonts() {
        guard let resourceURL = Bundle.main.resourceURL else { return }
        for filename in ["Silkscreen-Regular.ttf", "Silkscreen-Bold.ttf"] {
            let url = resourceURL.appendingPathComponent("Fonts", isDirectory: true).appendingPathComponent(filename)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            _ = CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}

final class DashboardApplication: NSApplication {
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown,
           let delegate = delegate as? DashboardAppDelegate,
           delegate.handleApplicationKeyEvent(event) {
            return
        }
        super.sendEvent(event)
    }
}

final class DashboardWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class DashboardAppDelegate: NSObject, NSApplicationDelegate {
    private let model = DashboardModel()
    private var window: DashboardWindow?
    private var dashboardView: DashboardView?
    private var settingsController: SettingsWindowController?
    private var globalShortcutMonitor: Any?
    private var localShortcutMonitor: Any?
    private var mouseActivityMonitor: Any?
    private var cursorHideTimer: Timer?
    private var cursorIsHidden = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        PixelFontRegistrar.registerBundledFonts()
        NSApp.setActivationPolicy(.regular)
        NSApp.presentationOptions = [.hideDock, .hideMenuBar]

        let screen = DashboardDisplayPreference.preferredScreen()
        // `contentRect` is interpreted in the coordinate system of the screen
        // passed to this initializer. Passing a screen's global frame here
        // offsets secondary displays twice (for example, x = -2560 instead
        // of x = -1280), leaving the dashboard outside the visible display.
        let window = DashboardWindow(
            contentRect: NSRect(origin: .zero, size: screen.frame.size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        window.setFrame(screen.frame, display: false)
        window.backgroundColor = PixelPalette.ink
        window.isOpaque = true
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.hasShadow = false
        window.title = "Hermes Dashboard"
        window.acceptsMouseMovedEvents = true

        let view = DashboardView(model: model)
        window.contentView = view
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(view)
        self.window = window
        self.dashboardView = view

        // A borderless screen-saver-level window may not deliver keyDown to its
        // content view consistently. Register both monitors so S / Cmd+, work
        // whether the dashboard or the settings panel owns focus.
        localShortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleLocalShortcut(event) == true ? nil : event
        }
        mouseActivityMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel]) { [weak self] event in
            self?.handleMouseActivity()
            return event
        }
        globalShortcutMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return }
            let key = event.charactersIgnoringModifiers?.lowercased()
            if event.modifierFlags.contains(.command) && key == "," {
                self.showSettings()
            }
        }

        // A previous forced termination can leave the process-level hide count
        // unbalanced; always begin with a visible pointer.
        NSCursor.unhide()
        handleMouseActivity()
        model.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.stop()
        if let localShortcutMonitor { NSEvent.removeMonitor(localShortcutMonitor) }
        if let globalShortcutMonitor { NSEvent.removeMonitor(globalShortcutMonitor) }
        if let mouseActivityMonitor { NSEvent.removeMonitor(mouseActivityMonitor) }
        localShortcutMonitor = nil
        globalShortcutMonitor = nil
        mouseActivityMonitor = nil
        cursorHideTimer?.invalidate()
        cursorHideTimer = nil
        if cursorIsHidden { NSCursor.unhide() }
        cursorIsHidden = false
        NSApp.presentationOptions = []
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func showSettings() {
        handleMouseActivity()
        if settingsController == nil {
            settingsController = SettingsWindowController(model: model, parentWindow: window) { [weak self] screen in
                self?.moveDashboard(to: screen)
            }
        }
        settingsController?.showWindow(nil)
    }

    private func moveDashboard(to screen: NSScreen) {
        guard let window else { return }
        let settingsIsKey = settingsController?.window?.isKeyWindow == true
        window.setFrame(screen.frame, display: true, animate: false)
        dashboardView?.needsLayout = true
        dashboardView?.needsDisplay = true
        if settingsIsKey {
            settingsController?.window?.orderFrontRegardless()
            settingsController?.window?.makeKey()
        } else {
            window.makeKeyAndOrderFront(nil)
        }
    }

    @discardableResult
    func handleApplicationKeyEvent(_ event: NSEvent) -> Bool {
        handleLocalShortcut(event)
    }

    func handleMouseActivity() {
        if cursorIsHidden {
            NSCursor.unhide()
            cursorIsHidden = false
        }
        cursorHideTimer?.invalidate()
        cursorHideTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: false) { [weak self] _ in
            guard let self, !self.cursorIsHidden else { return }
            NSCursor.hide()
            self.cursorIsHidden = true
        }
    }

    private func handleLocalShortcut(_ event: NSEvent) -> Bool {
        if event.keyCode == 53 {
            NSApp.terminate(nil)
            return true
        }
        let key = event.charactersIgnoringModifiers?.lowercased()
        if event.modifierFlags.contains(.command) && key == "," {
            showSettings()
            return true
        }
        let isDashboardWindow = event.window === window || (event.window == nil && settingsController?.window?.isKeyWindow != true)
        let settingsIsKey = settingsController?.window?.isKeyWindow == true
        if isDashboardWindow && !settingsIsKey && key == "s" && !event.modifierFlags.contains(.command) && !event.modifierFlags.contains(.control) && !event.modifierFlags.contains(.option) {
            showSettings()
            return true
        }
        if event.modifierFlags.contains(.command) && key == "q" && (isDashboardWindow || settingsIsKey) {
            NSApp.terminate(nil)
            return true
        }
        return false
    }
}
