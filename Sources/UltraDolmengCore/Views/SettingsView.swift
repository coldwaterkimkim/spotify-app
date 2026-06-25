import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var coordinator: PlaybackCoordinator
    let onQuit: () -> Void

    @State private var clientIDDraft = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                spotifySection

                Divider()

                overlaySection

                Divider()

                behaviorSection

                footer
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 500, height: 560)

        .onAppear {
            clientIDDraft = settings.spotifyClientID
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("울트라돌멩의솦티파이리릭")
                .font(.title2.weight(.semibold))
            Text("Spotify 재생에 맞춰 하단 중앙에 원문 가사 1줄만 띄우는 자막 오버레이야.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var spotifySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Spotify 연결")

            TextField("Spotify Client ID", text: $clientIDDraft)
                .textFieldStyle(.roundedBorder)
                .onSubmit(saveClientID)

            Text("Spotify Dashboard의 Redirect URI에 \(settings.redirectURIHint)를 등록해야 해.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            HStack {
                Button("Client ID 저장") {
                    saveClientID()
                }

                Button(coordinator.isConnected ? "다시 연결" : "Spotify 연결") {
                    saveClientID()
                    coordinator.connectSpotify()
                }
                .keyboardShortcut(.defaultAction)

                if coordinator.isConnected {
                    Button("연결 해제") {
                        coordinator.disconnectSpotify()
                    }
                }
            }

            Text(coordinator.statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    private var overlaySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionTitle("자막 모양")
                Spacer()
                Button(coordinator.demoMode ? "미리보기 끄기" : "미리보기 켜기") {
                    if coordinator.demoMode {
                        coordinator.hideDemoOverlay()
                    } else {
                        coordinator.showDemoOverlay()
                    }
                }
            }

            Toggle("항상 위에 띄우기", isOn: $settings.alwaysOnTop)

            sliderRow(
                title: "배경 투명도",
                value: $settings.captionOpacity,
                range: 0.45...0.9,
                formattedValue: "\(Int(settings.captionOpacity * 100))%"
            )

            HStack(spacing: 8) {
                presetButton("연함", opacity: 0.58)
                presetButton("기본", opacity: 0.74)
                presetButton("진함", opacity: 0.84)
            }

            sliderRow(
                title: "자막 크기",
                value: $settings.captionFontSize,
                range: CaptionLayout.minFontSize...CaptionLayout.maxFontSize,
                formattedValue: "\(Int(CaptionLayout.visualScale(for: settings.captionFontSize) * 100))%"
            )

            sliderRow(
                title: "최대 폭",
                value: $settings.captionMaxWidth,
                range: CaptionLayout.minMaxWidth...CaptionLayout.maxMaxWidth,
                formattedValue: "\(Int(settings.captionMaxWidth))px"
            )
        }
    }

    private var behaviorSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("동작")

            sliderRow(
                title: "일시정지 후 숨김",
                value: $settings.pauseFadeDelay,
                range: 0.5...8,
                formattedValue: String(format: "%.1fs", settings.pauseFadeDelay)
            )

            sliderRow(
                title: "가사 싱크 보정",
                value: $settings.lyricsOffset,
                range: -3...3,
                formattedValue: String(format: "%+.1fs", settings.lyricsOffset)
            )
        }
    }

    private var footer: some View {
        HStack {
            Text("Dock/Menu bar 아이콘 없이 백그라운드에서 작동해. 앱을 다시 열면 이 설정 창이 열려.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("종료") {
                onQuit()
            }
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.headline)
    }

    private func sliderRow(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        formattedValue: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title)
                Spacer()
                Text(formattedValue)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(value: value, in: range)
        }
    }

    private func presetButton(_ title: String, opacity: Double) -> some View {
        Button(title) {
            settings.captionOpacity = opacity
        }
        .buttonStyle(.bordered)
    }

    private func saveClientID() {
        settings.spotifyClientID = clientIDDraft
    }
}
