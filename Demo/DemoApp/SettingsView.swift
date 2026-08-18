import KSPlayer
import SwiftUI

/// Demo settings, wiring the library's real `KSOptions` knobs.
/// Static knobs (手势/预览) take effect immediately; instance-level knobs
/// (解码/缓冲/播放) apply the next time a player starts.
struct SettingsView: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section("解码") {
                Toggle("硬件解码", isOn: $settings.hardwareDecode)
                Toggle("异步解压（VTDecompressionSession）", isOn: $settings.asynchronousDecompression)
            }

            Section("缓冲") {
                Stepper(value: $settings.preferredForwardBufferDuration, in: 0.5...30, step: 0.5) {
                    Text("预缓冲 \(settings.preferredForwardBufferDuration, specifier: "%.1f") 秒")
                }
                Stepper(value: $settings.maxBufferDuration, in: 5...120, step: 5) {
                    Text("最大缓冲 \(settings.maxBufferDuration, specifier: "%.1f") 秒")
                }
                Toggle("二次打开（降低 seek 后缓冲要求）", isOn: $settings.isSecondOpen)
                Toggle("精确 seek", isOn: $settings.isAccurateSeek)
            }

            Section("播放") {
                Toggle("循环播放", isOn: $settings.isLoopPlay)
                Toggle("本地缓存（FFmpeg cache 协议）", isOn: $settings.cache)
                Toggle("自动选择内嵌字幕", isOn: $settings.autoSelectEmbedSubtitle)
                Toggle("低延迟音频（IO buffer 0.02s）", isOn: lowLatencyAudioBinding)
            }

            Section("手势与预览") {
                Toggle("双击分区 ±10s seek", isOn: $settings.doubleTapZoneSeek)
                Stepper(value: $settings.doubleTapSeekInterval, in: 5...30, step: 5) {
                    Text("双击 seek 间隔 \(Int(settings.doubleTapSeekInterval)) 秒")
                }
                Toggle("拖动缩略图预览", isOn: $settings.enableScrubPreview)
                Toggle("双指缩放（平面模式）", isOn: $settings.enableZoomGestures)
            }

            Section {
                Button("清空播放历史", role: .destructive) {
                    history.clear()
                }
                .disabled(history.entries.isEmpty)
            }
        }
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
    }

    @EnvironmentObject private var history: HistoryStore

    private var lowLatencyAudioBinding: Binding<Bool> {
        Binding(
            get: { settings.preferredIOBufferDuration != nil },
            set: { settings.preferredIOBufferDuration = $0 ? 0.02 : nil }
        )
    }
}
