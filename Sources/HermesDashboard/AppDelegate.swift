import AppKit

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

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.presentationOptions = [.hideDock, .hideMenuBar]

        let screen = NSScreen.main ?? NSScreen.screens[0]
        let window = DashboardWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false, screen: screen)
        window.backgroundColor = PixelPalette.ink
        window.isOpaque = true
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.hasShadow = false
        window.title = "Hermes Dashboard"

        let view = DashboardView(model: model)
        window.contentView = view
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
        globalShortcutMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return }
            let key = event.charactersIgnoringModifiers?.lowercased()
            if event.modifierFlags.contains(.command) && key == "," {
                self.showSettings()
            }
        }

        NSCursor.hide()
        model.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.stop()
        if let localShortcutMonitor { NSEvent.removeMonitor(localShortcutMonitor) }
        if let globalShortcutMonitor { NSEvent.removeMonitor(globalShortcutMonitor) }
        localShortcutMonitor = nil
        globalShortcutMonitor = nil
        NSCursor.unhide()
        NSApp.presentationOptions = []
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func showSettings() {
        if settingsController == nil {
            settingsController = SettingsWindowController(model: model)
        }
        settingsController?.showWindow(nil)
    }

    @discardableResult
    private func handleLocalShortcut(_ event: NSEvent) -> Bool {
        let key = event.charactersIgnoringModifiers?.lowercased()
        if event.modifierFlags.contains(.command) && key == "," {
            showSettings()
            return true
        }
        let isDashboardWindow = event.window === window
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
