import KSPlayer
import SwiftUI

/// KSPlayer demo: a playable video (URL) with a display-mode switch.
/// Display modes map to KSPlayer's `DisplayEnum`:
///   - plane: normal playback (KSAVPlayer)
///   - vr:    panorama / 360 rendering (KSMEPlayer, touch-drag to look around)
///   - vrBox: VR-box split-screen (KSMEPlayer)
///
/// The player is rebuilt via `.id()` when the committed URL or display mode
/// changes, because KSVideoPlayer.updateView only recreates the layer when the
/// URL differs — a display-mode change alone would otherwise be ignored.
struct ContentView: View {
    private let coordinator = KSVideoPlayer.Coordinator()

    @State private var draftURL: String = Self.defaultURL.absoluteString
    @State private var activeURL: URL = Self.defaultURL
    @State private var activeDisplay: DisplayEnum = .plane

    private static let defaultURL = URL(
        string: "https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_fmp4/master.m3u8"
    )!

    private static let displayModes: [(DisplayEnum, String)] = [
        (.plane, "平面"),
        (.vr, "全景"),
        (.vrBox, "VR盒子"),
    ]

    var body: some View {
        KSVideoPlayer(coordinator: coordinator, url: activeURL, options: options)
            .id("\(activeURL)|\(activeDisplay)")
            .ignoresSafeArea()
            .safeAreaInset(edge: .bottom, spacing: 0) {
                controls
            }
    }

    private var options: KSOptions {
        var options = KSOptions()
        options.display = activeDisplay
        return options
    }

    private var controls: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                TextField("视频 URL（文件名含 vr 自动全景）", text: $draftURL)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .onSubmit(startPlayback)
                Button("播放") {
                    startPlayback()
                }
                .buttonStyle(.borderedProminent)
            }
            Picker("显示模式", selection: $activeDisplay) {
                ForEach(Self.displayModes, id: \.0) { mode, label in
                    Text(label).tag(mode)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding()
        .background(.ultraThinMaterial)
    }

    private func startPlayback() {
        guard let url = URL(string: draftURL), !draftURL.isEmpty else { return }
        activeURL = url
        // Restore old demo behaviour: any URL whose filename contains "vr"
        // (case-insensitive) starts in panorama mode.
        if url.lastPathComponent.lowercased().contains("vr") {
            activeDisplay = .vr
        }
    }
}
