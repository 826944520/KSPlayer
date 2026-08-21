import Foundation
import KSPlayer

/// Demo playback preferences. Instance-level knobs are applied to a fresh
/// `KSOptions` each time a player starts (via `apply(to:)`); global statics
/// are applied to the library immediately when changed.
final class AppSettings: ObservableObject {
    // Instance-level (applied when building KSOptions).
    @Published var hardwareDecode = true
    @Published var asynchronousDecompression = false
    @Published var isAccurateSeek = false
    @Published var autoSelectEmbedSubtitle = true
    @Published var isSecondOpen = false
    @Published var isLoopPlay = false
    @Published var cache = KSOptions.cache
    @Published var preferredForwardBufferDuration: Double = 3 // KSOptions default
    @Published var maxBufferDuration: Double = 30 // KSOptions default

    // Global statics (applied immediately on change).
    @Published var doubleTapZoneSeek = KSOptions.doubleTapZoneSeek {
        didSet { KSOptions.doubleTapZoneSeek = doubleTapZoneSeek }
    }
    @Published var doubleTapSeekInterval = KSOptions.doubleTapSeekInterval {
        didSet { KSOptions.doubleTapSeekInterval = doubleTapSeekInterval }
    }
    @Published var enableScrubPreview = KSOptions.enableScrubPreview {
        didSet { KSOptions.enableScrubPreview = enableScrubPreview }
    }
    @Published var enableZoomGestures = KSOptions.enableZoomGestures {
        didSet { KSOptions.enableZoomGestures = enableZoomGestures }
    }
    @Published var enableToneMapping = KSOptions.enableToneMapping {
        didSet { KSOptions.enableToneMapping = enableToneMapping }
    }
    @Published var preferredIOBufferDuration: Double? = KSOptions.preferredIOBufferDuration {
        didSet { KSOptions.preferredIOBufferDuration = preferredIOBufferDuration }
    }

    /// Copy instance-level knobs onto a `KSOptions` that is about to be used
    /// by a player. Static knobs are already live.
    func apply(to options: KSOptions) {
        options.hardwareDecode = hardwareDecode
        options.asynchronousDecompression = asynchronousDecompression
        options.isAccurateSeek = isAccurateSeek
        options.autoSelectEmbedSubtitle = autoSelectEmbedSubtitle
        options.isSecondOpen = isSecondOpen
        options.isLoopPlay = isLoopPlay
        options.cache = cache
        options.preferredForwardBufferDuration = preferredForwardBufferDuration
        options.maxBufferDuration = maxBufferDuration
    }
}
