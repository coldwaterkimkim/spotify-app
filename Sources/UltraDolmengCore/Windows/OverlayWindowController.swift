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
    private let interaction = OverlayInteractionState()

    private lazy var panel: NSPanel = {
        let defaultWidth = CaptionLayout.defaultMaxWidth
        let defaultHeight = CaptionLayout.captionPanelHeight(for: CaptionLayout.defaultFontSize)
        let panel = EdgeReachablePanel(
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
        panel.ignoresMouseEvents = false
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.contentView = MovablePanelHostingView(
            rootView: CaptionOverlayView(
                coordinator: coordinator,
                settings: settings,
                interaction: interaction,
                onQueueToggle: { [weak self] in
                    self?.toggleQueuePanel()
                },
                onPrevious: { [weak self] in
                    self?.coordinator.skipToPrevious()
                },
                onPlayPause: { [weak self] in
                    self?.coordinator.togglePlayPause()
                },
                onNext: { [weak self] in
                    self?.coordinator.skipToNext()
                }
            ),
            onOpenSettings: onOpenSettings,
            shouldForwardMouseDown: { [weak self] point, bounds in
                self?.shouldForwardMouseDown(at: point, in: bounds) ?? false
            }
        )
        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.panel.isVisible, self.isProgrammaticMove == false else { return }
                self.hasManualPosition = true
                self.updateQueuePanelFrame(animated: false)
            }
        }
        return panel
    }()

    private lazy var queuePanel: NSPanel = {
        let panel = EdgeReachablePanel(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: preferredPanelSize.width,
                height: CaptionLayout.queuePanelHeight
            ),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.level = settings.alwaysOnTop ? .floating : .normal
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.ignoresMouseEvents = false
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.contentView = NSHostingView(
            rootView: QueueOverlayView(
                coordinator: coordinator,
                settings: settings,
                onSelectItem: { [weak self] index, _ in
                    self?.coordinator.skipToQueueItem(at: index)
                }
            )
        )
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
        if coordinator.shouldShowCaptionOverlay == false {
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
        hideQueuePanel(animated: true)
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
                    self?.updateQueuePanelFrame(animated: false)
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
        queuePanel.level = settings.alwaysOnTop ? .floating : .normal
        panel.ignoresMouseEvents = false

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
        let frame = screen.frame
        let size = panel.frame.size
        let x = frame.midX - size.width / 2
        let y = frame.minY + CaptionLayout.defaultBottomOffset
        setFrameOrigin(NSPoint(x: x.rounded(), y: y.rounded()))
    }

    private var preferredPanelSize: NSSize {
        let width = settings.captionMaxWidth * CaptionLayout.visualScale(for: settings.captionFontSize)
        return NSSize(width: width, height: preferredCaptionHeight)
    }

    private var preferredCaptionHeight: Double {
        CaptionLayout.captionPanelHeight(for: settings.captionFontSize)
    }

    private func setFrameOrigin(_ origin: NSPoint) {
        isProgrammaticMove = true
        panel.setFrameOrigin(origin)
        updateQueuePanelFrame(animated: false)
        isProgrammaticMove = false
    }

    private func shouldForwardMouseDown(at point: NSPoint, in bounds: NSRect) -> Bool {
        let buttonWidth: Double = 30
        let buttonSpacing: Double = 22
        let centerGroupWidth = buttonWidth * 3 + buttonSpacing * 2
        let centerGroupMinX = bounds.midX - centerGroupWidth / 2
        let firstButtonCenterX = centerGroupMinX + buttonWidth / 2
        let buttonCenters = [
            firstButtonCenterX,
            firstButtonCenterX + buttonWidth + buttonSpacing,
            firstButtonCenterX + (buttonWidth + buttonSpacing) * 2
        ]
        let isInCenterButton = buttonCenters.contains { centerX in
            point.x >= centerX - buttonWidth / 2 && point.x <= centerX + buttonWidth / 2
        }

        let queueButtonMinX = bounds.maxX - 12 - buttonWidth
        let isInQueueButton = point.x >= queueButtonMinX && point.x <= queueButtonMinX + buttonWidth
        return isInCenterButton || isInQueueButton
    }

    private func toggleQueuePanel() {
        if interaction.isQueueExpanded {
            hideQueuePanel(animated: true)
        } else {
            showQueuePanel()
        }
    }

    private func showQueuePanel() {
        coordinator.refreshQueue()
        interaction.isQueueExpanded = true
        updateQueuePanelFrame(animated: false, openingOffset: 14)

        if queuePanel.isVisible == false {
            queuePanel.alphaValue = 0
            queuePanel.orderFrontRegardless()
        }

        updateQueuePanelFrame(animated: true)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            queuePanel.animator().alphaValue = 1
        }
    }

    private func hideQueuePanel(animated: Bool) {
        guard interaction.isQueueExpanded || queuePanel.isVisible else { return }
        interaction.isQueueExpanded = false

        guard animated else {
            queuePanel.alphaValue = 0
            queuePanel.orderOut(nil)
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            queuePanel.animator().alphaValue = 0
            queuePanel.animator().setFrame(queuePanelFrame(openingOffset: 10), display: true)
        } completionHandler: {
            Task { @MainActor in
                self.queuePanel.orderOut(nil)
            }
        }
    }

    private func updateQueuePanelFrame(animated: Bool, openingOffset: Double = 0) {
        guard queuePanel.isVisible || interaction.isQueueExpanded else { return }
        let frame = queuePanelFrame(openingOffset: openingOffset)
        queuePanel.setContentSize(frame.size)

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.16
                queuePanel.animator().setFrame(frame, display: true)
            }
        } else {
            queuePanel.setFrame(frame, display: true)
        }
    }

    private func queuePanelFrame(openingOffset: Double = 0) -> NSRect {
        let size = NSSize(width: preferredPanelSize.width, height: CaptionLayout.queuePanelHeight)
        let x = panel.frame.minX
        let y = panel.frame.maxY + CaptionLayout.queuePanelSpacing - openingOffset
        return NSRect(origin: NSPoint(x: x, y: y), size: size)
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

private final class EdgeReachablePanel: NSPanel {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        guard let displayFrame = screen?.frame else {
            return frameRect
        }

        var constrained = frameRect
        if constrained.width <= displayFrame.width {
            constrained.origin.x = min(max(constrained.origin.x, displayFrame.minX), displayFrame.maxX - constrained.width)
        }
        if constrained.height <= displayFrame.height {
            constrained.origin.y = min(max(constrained.origin.y, displayFrame.minY), displayFrame.maxY - constrained.height)
        }
        return constrained
    }
}

private final class MovablePanelHostingView<Content: View>: NSHostingView<Content> {
    private let onOpenSettings: () -> Void
    private let shouldForwardMouseDown: (NSPoint, NSRect) -> Bool

    init(
        rootView: Content,
        onOpenSettings: @escaping () -> Void,
        shouldForwardMouseDown: @escaping (NSPoint, NSRect) -> Bool
    ) {
        self.onOpenSettings = onOpenSettings
        self.shouldForwardMouseDown = shouldForwardMouseDown
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

        let point = convert(event.locationInWindow, from: nil)
        if shouldForwardMouseDown(point, bounds) {
            super.mouseDown(with: event)
            return
        }

        window?.performDrag(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        onOpenSettings()
    }
}
