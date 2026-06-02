import AppKit
import SwiftUI

@MainActor
final class OverlayInteractionState: ObservableObject {
    @Published var isQueueExpanded = false
}

struct CaptionOverlayView: View {
    @ObservedObject var coordinator: PlaybackCoordinator
    @ObservedObject var settings: AppSettings
    @ObservedObject var interaction: OverlayInteractionState
    let onQueueToggle: () -> Void
    let onPrevious: () -> Void
    let onPlayPause: () -> Void
    let onNext: () -> Void

    @State private var isHovering = false

    private var captionFontSize: Double {
        CaptionLayout.fontSize(for: settings.captionFontSize)
    }

    private var captionScale: Double {
        CaptionLayout.visualScale(for: settings.captionFontSize)
    }

    private var visibleCaptionWidth: Double {
        settings.captionMaxWidth * captionScale
    }

    private var captionPanelHeight: Double {
        CaptionLayout.captionPanelHeight(for: settings.captionFontSize)
    }

    private var shouldShowControls: Bool {
        isHovering || interaction.isQueueExpanded
    }

    var body: some View {
        ZStack {
            if coordinator.shouldShowCaptionOverlay {
                captionPanel
            }
        }
        .frame(width: visibleCaptionWidth, height: captionPanelHeight)
        .background(Color.clear)
        .onHover { hovering in
            isHovering = hovering
        }
    }

    private var captionPanel: some View {
        ZStack {
            Text(coordinator.caption.current)
                .font(.system(size: captionFontSize, weight: .light, design: .default))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .allowsTightening(true)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 54)
                .opacity(shouldShowControls ? 0.2 : 1)
                .animation(.easeOut(duration: 0.12), value: shouldShowControls)

            HStack(spacing: 22) {
                controlButton(systemName: "backward.fill", label: "이전 곡", action: onPrevious)
                controlButton(systemName: coordinator.isPlaybackActive ? "pause.fill" : "play.fill", label: "재생/일시정지", action: onPlayPause)
                controlButton(systemName: "forward.fill", label: "다음 곡", action: onNext)
            }
            .opacity(isHovering ? 1 : 0)
            .animation(.easeOut(duration: 0.12), value: isHovering)

            HStack {
                Spacer()
                Button(action: onQueueToggle) {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 13, weight: .regular))
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.9))
                .opacity(shouldShowControls ? 1 : 0)
                .disabled(shouldShowControls == false)
                .accessibilityLabel("다음 재생목록")
            }
            .padding(.trailing, 12)
        }
        .frame(width: visibleCaptionWidth, height: captionPanelHeight)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.black.opacity(settings.captionOpacity))
        )
    }

    private func controlButton(systemName: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .regular))
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white.opacity(0.92))
        .accessibilityLabel(label)
    }
}

struct QueueOverlayView: View {
    @ObservedObject var coordinator: PlaybackCoordinator
    @ObservedObject var settings: AppSettings
    let onSelectItem: (Int, QueueItemInfo) -> Void

    private var captionScale: Double {
        CaptionLayout.visualScale(for: settings.captionFontSize)
    }

    private var visibleCaptionWidth: Double {
        settings.captionMaxWidth * captionScale
    }

    var body: some View {
        Group {
            if coordinator.isQueueLoading {
                loadingView
            } else if let queueStatusText = coordinator.queueStatusText {
                statusView(queueStatusText)
            } else {
                queueList
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(width: visibleCaptionWidth, height: CaptionLayout.queuePanelHeight, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.black.opacity(max(0.64, settings.captionOpacity - 0.04)))
        )
    }

    private var loadingView: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("불러오는 중")
                .lineLimit(1)
        }
        .font(.system(size: 12, weight: .light))
        .foregroundStyle(.white.opacity(0.78))
    }

    private func statusView(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .light))
            .foregroundStyle(.white.opacity(0.78))
            .lineLimit(1)
    }

    private var queueList: some View {
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: 7) {
                ForEach(Array(coordinator.queueItems.enumerated()), id: \.element.id) { index, item in
                    Button {
                        onSelectItem(index, item)
                    } label: {
                        queueRow(index: index, item: item)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 1)
        }
        .scrollIndicators(.hidden)
        .overlay {
            ScrollIndicatorSuppressor()
                .allowsHitTesting(false)
        }
    }

    private func queueRow(index: Int, item: QueueItemInfo) -> some View {
        HStack(spacing: 9) {
            Text("\(index + 1)")
                .font(.system(size: 11, weight: .light, design: .monospaced))
                .foregroundStyle(.white.opacity(0.5))
                .frame(width: 14, alignment: .trailing)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.system(size: 12.5, weight: .regular))
                    .foregroundStyle(.white.opacity(0.94))
                    .lineLimit(1)
                Text(item.artist)
                    .font(.system(size: 11, weight: .light))
                    .foregroundStyle(.white.opacity(0.58))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
    }
}

private struct ScrollIndicatorSuppressor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = ScrollIndicatorSuppressingView(frame: .zero)
        view.scheduleSuppression()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? ScrollIndicatorSuppressingView else {
            return
        }
        view.scheduleSuppression()
    }
}

private final class ScrollIndicatorSuppressingView: NSView {
    private var isSuppressionScheduled = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        scheduleSuppression()
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        scheduleSuppression()
    }

    override func layout() {
        super.layout()
        scheduleSuppression()
    }

    func scheduleSuppression() {
        guard isSuppressionScheduled == false else { return }
        isSuppressionScheduled = true
        let delays: [TimeInterval] = [0, 0.05, 0.2, 0.6]
        for (index, delay) in delays.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.suppressScrollIndicators()
                if index == delays.count - 1 {
                    self?.isSuppressionScheduled = false
                }
            }
        }
    }

    private func suppressScrollIndicators() {
        let roots = [
            enclosingScrollView,
            window?.contentView
        ].compactMap { $0 }

        roots
            .flatMap { scrollViews(in: $0) }
            .forEach(configure)
    }

    private func scrollViews(in root: NSView) -> [NSScrollView] {
        var result: [NSScrollView] = []
        if let scrollView = root as? NSScrollView {
            result.append(scrollView)
        }
        for subview in root.subviews {
            result.append(contentsOf: scrollViews(in: subview))
        }
        return result
    }

    private func configure(_ scrollView: NSScrollView) {
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.verticalScroller?.isHidden = true
        scrollView.horizontalScroller?.isHidden = true
    }
}
