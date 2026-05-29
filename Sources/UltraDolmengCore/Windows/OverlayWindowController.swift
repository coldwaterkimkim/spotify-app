import AppKit
import Combine
import SwiftUI

@MainActor
final class OverlayWindowController: NSObject {
    private let settings: AppSettings
    private let coordinator: PlaybackCoordinator
    private let onOpenSettings: () -> Void
    private var cancellables = Set<AnyCancellable>()
    private var screenObserver: NSObjectProtocol?
    private var moveObserver: NSObjectProtocol?
    private var isProgrammaticMove = false
    private var hasManualPosition = false

    private lazy var panel: NSPanel = {
        let defaultWidth = CaptionLayout.defaultMaxWidth + CaptionLayout.windowHorizontalInset
        let defaultHeight = defaultWidth / CaptionLayout.windowAspectRatio
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: defaultWidth, height: defaultHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.level = settings.alwaysOnTop ? .floating : .normal
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.ignoresMouseEvents = settings.mousePassThrough
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.contentView = MovablePanelHostingView(
            rootView: CaptionOverlayView(coordinator: coordinator, settings: settings),
            onOpenSettings: onOpenSettings
        )
        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.panel.isVisible, self.isProgrammaticMove == false else { return }
                self.hasManualPosition = true
            }
        }
        return panel
    }()

    init(settings: AppSettings, coordinator: PlaybackCoordinator, onOpenSettings: @escaping () -> Void) {
        self.settings = settings
        self.coordinator = coordinator
        self.onOpenSettings = onOpenSettings
        super.init()
        bind()
    }

    func showIfNeeded() {
        if coordinator.caption.current.isEmpty {
            hide()
            return
        }

        applyWindowPreferences()
        if panel.isVisible == false, hasManualPosition == false {
            positionAtBottomCenter()
        }

        if panel.isVisible == false {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        guard panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.24
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            Task { @MainActor in
                self?.panel.orderOut(nil)
            }
        }
    }

    private func bind() {
        coordinator.$caption
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.showIfNeeded()
            }
            .store(in: &cancellables)

        settings.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.applyWindowPreferences()
                    if self?.hasManualPosition == false {
                        self?.positionAtBottomCenter()
                    }
                }
            }
            .store(in: &cancellables)

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                if self?.hasManualPosition == false {
                    self?.positionAtBottomCenter()
                }
            }
        }
    }

    private func applyWindowPreferences() {
        panel.level = settings.alwaysOnTop ? .floating : .normal
        panel.ignoresMouseEvents = settings.mousePassThrough

        let oldCenter = NSPoint(x: panel.frame.midX, y: panel.frame.midY)
        let shouldPreserveCenter = hasManualPosition && panel.isVisible
        panel.setContentSize(preferredPanelSize)

        if shouldPreserveCenter {
            setFrameOrigin(
                NSPoint(
                    x: oldCenter.x - panel.frame.width / 2,
                    y: oldCenter.y - panel.frame.height / 2
                )
            )
        }
    }

    private func positionAtBottomCenter() {
        guard let screen = panel.screen ?? NSScreen.main else { return }
        let frame = screen.visibleFrame
        let size = panel.frame.size
        let x = frame.midX - size.width / 2
        let y = frame.minY + settings.bottomOffset
        setFrameOrigin(NSPoint(x: x.rounded(), y: y.rounded()))
    }

    private var preferredPanelSize: NSSize {
        let width = settings.captionMaxWidth * CaptionLayout.visualScale(for: settings.captionFontSize) +
            CaptionLayout.windowHorizontalInset
        let height = width / CaptionLayout.windowAspectRatio
        return NSSize(width: width, height: height)
    }

    private func setFrameOrigin(_ origin: NSPoint) {
        isProgrammaticMove = true
        panel.setFrameOrigin(origin)
        isProgrammaticMove = false
    }

    deinit {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
        if let moveObserver {
            NotificationCenter.default.removeObserver(moveObserver)
        }
    }
}

private final class MovablePanelHostingView<Content: View>: NSHostingView<Content> {
    private let onOpenSettings: () -> Void

    init(rootView: Content, onOpenSettings: @escaping () -> Void) {
        self.onOpenSettings = onOpenSettings
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    required init(rootView: Content) {
        fatalError("init(rootView:) has not been implemented")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var mouseDownCanMoveWindow: Bool {
        false
    }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) {
            onOpenSettings()
            return
        }

        window?.performDrag(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        onOpenSettings()
    }
}
