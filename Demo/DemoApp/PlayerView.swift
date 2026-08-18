import KSPlayer
import SwiftUI

/// Full-screen demo player: the bare `KSVideoPlayer` representable wrapped in a
/// custom SwiftUI chrome (top bar, playlist/skip bar, debug sheet, first-run
/// double-tap hint).
///
/// The playlist advances by swapping the active URL; the representable's
/// `updateView` picks up the new URL and prepares it (the same proven rebuild
/// pattern the original demo used). `KSPlayerLayer.next()/previous()` are also
/// exposed by the library for programmatic control.
struct PlayerView: View {
    private let coordinator = KSVideoPlayer.Coordinator()
    let urls: [URL]
    let startIndex: Int
    var display: DisplayEnum
    @ObservedObject var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    @State private var currentIndex: Int
    @State private var stateLabel = "loading"
    @State private var isPlaying = true
    @State private var currentTime: Double = 0
    @State private var totalTime: Double = 0
    @State private var showDebug = false
    @State private var showHint = !UserDefaults.standard.bool(forKey: "ksp.doubleTapHintDismissed")

    init(urls: [URL], startIndex: Int, display: DisplayEnum, settings: AppSettings) {
        self.urls = urls
        self.startIndex = startIndex
        self.display = display
        self.settings = settings
        _currentIndex = State(initialValue: min(max(startIndex, 0), max(0, urls.count - 1)))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let url = urls.indices.contains(currentIndex) ? urls[currentIndex] : urls.first {
                KSVideoPlayer(coordinator: coordinator, url: url, options: options)
                    .ignoresSafeArea()
                    .onAppear {
                        // Feed the layer the full playlist so
                        // KSPlayerLayer.next()/previous() can advance it. Only
                        // when still on the first URL, to avoid a restart.
                        if let layer = coordinator.playerLayer, layer.url == urls.first {
                            layer.set(urls: urls, options: options)
                        }
                    }
                    .onStateChanged { _, state in
                        stateLabel = "\(state)"
                        isPlaying = state.isPlaying
                        if state == .playedToTheEnd {
                            next()
                        }
                    }
                    .onPlay { current, total in
                        currentTime = current
                        totalTime = total
                    }
            }

            chrome
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showDebug) {
            DebugSheet(playerLayer: coordinator.playerLayer, stateLabel: stateLabel)
        }
        .overlay(alignment: .top) {
            if showHint {
                hintBanner
            }
        }
    }

    private var options: KSOptions {
        let options = KSOptions()
        options.display = display
        settings.apply(to: options)
        return options
    }

    private var titleText: String {
        if let url = urls.indices.contains(currentIndex) ? urls[currentIndex] : urls.first {
            return url.lastPathComponent.isEmpty ? (url.host ?? "KSPlayer") : url.lastPathComponent
        }
        return "KSPlayer"
    }

    private var chrome: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
                Text(titleText)
                    .lineLimit(1)
                Spacer()
                Text(stateLabel)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.7))
            }
            .font(.headline)
            .foregroundStyle(.white)
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)

            Spacer()

            VStack(spacing: 12) {
                if totalTime > 0 {
                    Slider(
                        value: Binding(
                            get: { currentTime },
                            set: { coordinator.seek(time: $0) }
                        ),
                        in: 0...totalTime
                    )
                    .tint(.white)
                    HStack {
                        Text(currentTime.demoTimeText)
                        Spacer()
                        Text(totalTime.demoTimeText)
                    }
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.8))
                }

                HStack(spacing: 24) {
                    Button {
                        previous()
                    } label: {
                        Image(systemName: "backward.end.fill")
                    }
                    Button {
                        coordinator.skip(interval: -15)
                    } label: {
                        Image(systemName: "gobackward.15")
                    }
                    Button {
                        togglePlay()
                    } label: {
                        Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 44))
                    }
                    Button {
                        coordinator.skip(interval: 15)
                    } label: {
                        Image(systemName: "goforward.15")
                    }
                    Button {
                        next()
                    } label: {
                        Image(systemName: "forward.end.fill")
                    }
                }
                .font(.title2)
                .foregroundStyle(.white)
            }
            .padding()
            .background(.ultraThinMaterial)
        }
    }

    private var hintBanner: some View {
        HStack(spacing: 8) {
            Text("双击画面左侧 / 右侧 快退 / 快进 10 秒")
                .font(.caption)
            Button {
                showHint = false
                UserDefaults.standard.set(true, forKey: "ksp.doubleTapHintDismissed")
            } label: {
                Image(systemName: "xmark.circle.fill")
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .padding(.top, 8)
    }

    private func togglePlay() {
        if isPlaying {
            coordinator.playerLayer?.pause()
        } else {
            coordinator.playerLayer?.play()
        }
    }

    private func next() {
        coordinator.playerLayer?.next()
        syncIndexFromLayer()
    }

    private func previous() {
        coordinator.playerLayer?.previous()
        syncIndexFromLayer()
    }

    /// Keep `currentIndex` in sync with the layer's active URL so the
    /// representable's `updateView` sees a matching URL and does no extra work.
    private func syncIndexFromLayer() {
        if let url = coordinator.playerLayer?.url, let index = urls.firstIndex(of: url) {
            currentIndex = index
        }
    }
}

/// Read-only debug sheet: FFmpeg `DynamicInfo` on the KSMEPlayer (vr/vrBox)
/// path, or AVPlayer-level metrics on the KSAVPlayer (plane) path.
struct DebugSheet: View {
    let playerLayer: KSPlayerLayer?
    let stateLabel: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("状态") {
                    LabeledContent("State", value: stateLabel)
                    if let player = playerLayer?.player {
                        LabeledContent("Duration", value: "\(Int(player.duration)) 秒")
                        LabeledContent("Playable (缓冲)", value: "\(Int(player.playableTime)) 秒")
                        LabeledContent("Playback rate", value: "\(player.playbackRate)x")
                        LabeledContent("Muted", value: player.isMuted ? "是" : "否")
                    }
                }

                if let info = playerLayer?.player.dynamicInfo {
                    Section("FFmpeg 动态信息") {
                        LabeledContent("Display FPS", value: String(format: "%.1f", info.displayFPS))
                        LabeledContent("A/V 同步差", value: "\(info.audioVideoSyncDiff) 秒")
                        LabeledContent("丢帧", value: "\(info.droppedVideoFrameCount)")
                        LabeledContent("丢包", value: "\(info.droppedVideoPacketCount)")
                        LabeledContent("已读字节", value: "\(info.bytesRead)")
                        LabeledContent("音频码率", value: "\(info.audioBitrate) kbps")
                        LabeledContent("视频码率", value: "\(info.videoBitrate) kbps")
                    }
                } else {
                    Section("动态信息") {
                        Text("当前播放器（AVPlayer 路径）不提供 FFmpeg dynamicInfo。\n显示 duration / playableTime / rate 等 AVPlayer 指标。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("调试信息")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private extension TimeInterval {
    /// MM:SS (or H:MM:SS past the hour).
    var demoTimeText: String {
        let total = Int(self.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%02d:%02d", minutes, seconds)
    }
}
