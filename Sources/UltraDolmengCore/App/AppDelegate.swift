import AppKit

public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var settings: AppSettings!
    private var coordinator: PlaybackCoordinator!
    private var overlayWindowController: OverlayWindowController!
    private var settingsWindowController: SettingsWindowController!
    private var suppressReopenUntil: Date?

    public override init() {
        super.init()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        settings = AppSettings()
        coordinator = PlaybackCoordinator(settings: settings)
        settingsWindowController = SettingsWindowController(settings: settings, coordinator: coordinator)
        overlayWindowController = OverlayWindowController(settings: settings, coordinator: coordinator) { [weak self] in
            self?.settingsWindowController.show()
        }

        coordinator.start()
        if isBackgroundLaunch {
            suppressReopenUntil = Date().addingTimeInterval(2)
        }

        if CommandLine.arguments.contains("--demo") {
            settingsWindowController.show()
            coordinator.showDemoOverlay()
        } else if shouldShowSettingsOnLaunch {
            settingsWindowController.show()
        }
    }

    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if let suppressReopenUntil, Date() < suppressReopenUntil {
            return false
        }

        suppressReopenUntil = nil
        settingsWindowController.show()
        return true
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    public func applicationWillTerminate(_ notification: Notification) {
        coordinator.stop()
    }

    private var shouldShowSettingsOnLaunch: Bool {
        isBackgroundLaunch == false &&
            CommandLine.arguments.contains("--no-settings") == false
    }

    private var isBackgroundLaunch: Bool {
        CommandLine.arguments.contains("--background")
    }
}
