import KSPlayer
import SwiftUI
import UniformTypeIdentifiers

/// Demo home screen: recent history, a curated sample library, local-file
/// import, and a URL field. Selecting anything opens the full-screen player.
struct HomeView: View {
    @EnvironmentObject private var history: HistoryStore
    @EnvironmentObject private var settings: AppSettings

    @State private var draftURL = HomeView.defaultURL.absoluteString
    @State private var activeDisplay: DisplayEnum = .plane
    @State private var showSettings = false
    @State private var showImporter = false
    @State private var activePlayback: Playback?

    static let defaultURL = URL(
        string: "https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_fmp4/master.m3u8"
    )!

    private let samples: [(String, URL)] = [
        ("Apple HLS (bipbop, 自适应)", Self.defaultURL),
        ("Big Buck Bunny (MP4)", URL(string: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4")!),
        ("Sintel (MP4)", URL(string: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/Sintel.mp4")!),
        ("Tears of Steel (MP4)", URL(string: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/TearsOfSteel.mp4")!),
        ("For Bigger Blazes (MP4)", URL(string: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerBlazes.mp4")!),
    ]

    var body: some View {
        NavigationStack {
            List {
                Section("最近观看") {
                    if history.entries.isEmpty {
                        Text("还没有播放记录")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(history.entries) { entry in
                            Button {
                                play([entry.url])
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.title)
                                    Text(entry.url.absoluteString)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                        .onDelete(perform: deleteHistory)
                        .onMove(perform: moveHistory)
                    }
                }

                Section("精选示例") {
                    ForEach(samples, id: \.1) { title, url in
                        Button {
                            play([url])
                        } label: {
                            HStack {
                                Text(title)
                                Spacer()
                                Image(systemName: "play.circle")
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                }

                Section("本地文件") {
                    Button {
                        showImporter = true
                    } label: {
                        Label("选择本地视频 / 音频（可多选，自动作为播放列表）", systemImage: "folder.badge.plus")
                    }
                }

                Section("URL 播放") {
                    HStack(spacing: 8) {
                        TextField("视频 URL（文件名含 vr 自动全景）", text: $draftURL)
                            .textFieldStyle(.roundedBorder)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                            .onSubmit(submitURL)
                        Button("播放") {
                            submitURL()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    Picker("显示模式", selection: $activeDisplay) {
                        Text("平面").tag(DisplayEnum.plane)
                        Text("全景").tag(DisplayEnum.vr)
                        Text("VR盒子").tag(DisplayEnum.vrBox)
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle("KSPlayer")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Label("设置", systemImage: "gearshape")
                    }
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                SettingsView(settings: settings)
            }
            .environmentObject(history)
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.movie, .audio, .audiovisualContent],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                play(urls)
            }
        }
        .fullScreenCover(item: $activePlayback) { playback in
            PlayerView(
                urls: playback.urls,
                startIndex: playback.startIndex,
                display: playback.display,
                settings: settings
            )
            .environmentObject(history)
        }
    }

    /// Wraps a playback session so `fullScreenCover(item:)` can present it.
    private struct Playback: Identifiable {
        let id = UUID()
        let urls: [URL]
        let startIndex: Int
        let display: DisplayEnum
    }

    private func play(_ urls: [URL]) {
        guard let first = urls.first else { return }
        // Restore old demo behaviour: any URL whose filename contains "vr"
        // (case-insensitive) starts in panorama mode.
        if first.lastPathComponent.lowercased().contains("vr") {
            activeDisplay = .vr
        }
        activePlayback = Playback(urls: urls, startIndex: 0, display: activeDisplay)
        history.add(url: first, title: nil)
    }

    private func submitURL() {
        guard let url = URL(string: draftURL), !draftURL.isEmpty else { return }
        play([url])
    }

    private func deleteHistory(_ indexSet: IndexSet) {
        indexSet.map { history.entries[$0] }.forEach(history.remove)
    }

    private func moveHistory(_ source: IndexSet, _ destination: Int) {
        history.moveEntries(from: source, to: destination)
    }
}
