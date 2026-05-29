import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    private let settings: AppSettings
    private let coordinator: PlaybackCoordinator
    private var window: NSWindow?
    private var windowDelegate: WindowDelegate?

    init(settings: AppSettings, coordinator: PlaybackCoordinator) {
        self.settings = settings
        self.coordinator = coordinator
    }

    func show() {
        if let window {
            bringToFront(window)
            return
        }

        let view = SettingsView(settings: settings, coordinator: coordinator) {
            NSApp.terminate(nil)
        }

        let window = SettingsWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 650),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "울트라돌멩의솦티파이리릭 설정"
        window.level = .normal
        window.contentView = NSHostingView(rootView: view)
        window.center()
        window.isReleasedWhenClosed = false
        let delegate = WindowDelegate { [weak self] in
            self?.window = nil
            self?.windowDelegate = nil
        }
        window.delegate = delegate
        windowDelegate = delegate
        self.window = window

        bringToFront(window)
    }

    private func bringToFront(_ window: NSWindow) {
        window.level = .floating
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak window] in
            window?.level = .normal
        }
    }
}

private final class SettingsWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private final class WindowDelegate: NSObject, NSWindowDelegate {
    let onClose: () -> Void

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}
