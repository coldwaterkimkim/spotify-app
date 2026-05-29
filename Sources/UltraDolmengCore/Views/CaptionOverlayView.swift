import SwiftUI

struct CaptionOverlayView: View {
    @ObservedObject var coordinator: PlaybackCoordinator
    @ObservedObject var settings: AppSettings
    private var captionFontSize: Double {
        CaptionLayout.fontSize(for: settings.captionFontSize)
    }

    private var captionScale: Double {
        CaptionLayout.visualScale(for: settings.captionFontSize)
    }

    private var visibleCaptionWidth: Double {
        settings.captionMaxWidth * captionScale
    }

    var body: some View {
        ZStack {
            if coordinator.caption.current.isEmpty == false {
                VStack(spacing: 4) {
                    Text(coordinator.caption.current)
                        .font(.system(size: captionFontSize, weight: .light, design: .default))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .allowsTightening(true)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .frame(width: visibleCaptionWidth)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.black.opacity(settings.captionOpacity))
                )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
    }
}
