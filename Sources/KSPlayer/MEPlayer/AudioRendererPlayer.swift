


import AVFoundation
import Foundation

public class AudioRendererPlayer: AudioOutput {
    public var playbackRate: Float = 1 {
        didSet {
            if !isPaused {
                synchronizer.rate = playbackRate
            }
        }
    }

    public var volume: Float {
        get {
            renderer.volume
        }
        set {
            renderer.volume = newValue
        }
    }

    public var isMuted: Bool {
        get {
            renderer.isMuted
        }
        set {
            renderer.isMuted = newValue
        }
    }

    public weak var renderSource: OutputRenderSourceDelegate?
    private var periodicTimeObserver: Any?
    private let renderer = AVSampleBufferAudioRenderer()
    private let synchronizer = AVSampleBufferRenderSynchronizer()
    private let serializationQueue = DispatchQueue(label: "ks.player.serialization.queue")
    var isPaused: Bool {
        synchronizer.rate == 0
    }

    public required init() {
        synchronizer.addRenderer(renderer)
        // delaysRateChangeUntilHasSufficientMediaData needs macOS 11.3+ / iOS 14.5+,
        // but the package deploys to macOS 10.15 — read it only inside #available.
        if #available(macOS 11.3, iOS 14.5, tvOS 14.5, *) {
            synchronizer.delaysRateChangeUntilHasSufficientMediaData = false
            KSLog(level: .info, "[audio] AudioRendererPlayer initialized (delaysRateChange=\(synchronizer.delaysRateChangeUntilHasSufficientMediaData))")
        } else {
            KSLog(level: .info, "[audio] AudioRendererPlayer initialized (delaysRateChange=unsupported)")
        }
        if #available(tvOS 15.0, iOS 15.0, macOS 12.0, *) {
            renderer.allowedAudioSpatializationFormats = .monoStereoAndMultichannel
        }
    }

    public func prepare(audioFormat: AVAudioFormat) {
        #if !os(macOS)
        try? AVAudioSession.sharedInstance().setPreferredOutputNumberOfChannels(Int(audioFormat.channelCount))
        KSLog("[audio] set preferredOutputNumberOfChannels: \(audioFormat.channelCount)")
        #endif
    }

    public func play() {
        let time: CMTime
        // hasSufficientMediaDataForReliablePlaybackStart needs macOS 11.3+ /
        // iOS 14.5+; capture it inside #available (macOS 10.15 deployment).
        var hasSufficientData = false
        if #available(macOS 11.3, iOS 14.5, tvOS 14.5, *) {
            hasSufficientData = renderer.hasSufficientMediaDataForReliablePlaybackStart
            if renderer.hasSufficientMediaDataForReliablePlaybackStart {
                time = synchronizer.currentTime()
            } else {
                if let currentRender = renderSource?.getAudioOutputRender() {
                    time = currentRender.cmtime
                } else {
                    time = .zero
                }
            }
        } else {
            if let currentRender = renderSource?.getAudioOutputRender() {
                time = currentRender.cmtime
            } else {
                time = .zero
            }
        }
        synchronizer.setRate(playbackRate, time: time)
        KSLog(level: .info, "[audio] AudioRendererPlayer.play rate=\(playbackRate) hasData=\(hasSufficientData) time=\(time.seconds)")

        renderSource?.setAudio(time: time, position: -1)
        renderer.requestMediaDataWhenReady(on: serializationQueue) { [weak self] in
            guard let self else {
                return
            }
            self.request()
        }
        periodicTimeObserver = synchronizer.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.01), queue: .main) { [weak self] time in
            guard let self else {
                return
            }
            self.renderSource?.setAudio(time: time, position: -1)
        }
    }

    public func pause() {
        synchronizer.rate = 0
        renderer.stopRequestingMediaData()
        if let periodicTimeObserver {
            synchronizer.removeTimeObserver(periodicTimeObserver)
            self.periodicTimeObserver = nil
        }
    }

    public func flush() {
        renderer.flush()
    }

    private func request() {
        var stalled = false
        while renderer.isReadyForMoreMediaData, !isPaused {
            guard var render = renderSource?.getAudioOutputRender() else {
                // Ran out of audio frames while the renderer wants more — buffer
                // starved (event-level; throttled by the state transition).
                if !stalled {
                    stalled = true
                    KSLog(level: .debug, "[audio] AudioRendererPlayer starved: no audio render")
                }
                break
            }
            stalled = false
            var array = [render]
            let loopCount = Int32(render.audioFormat.sampleRate) / 20 / Int32(render.numberOfSamples) - 2
            if loopCount > 0 {
                for _ in 0 ..< loopCount {
                    if let render = renderSource?.getAudioOutputRender() {
                        array.append(render)
                    }
                }
            }
            if array.count > 1 {
                render = AudioFrame(array: array)
            }
            guard let sampleBuffer = render.toCMSampleBuffer() else {
                KSLog(level: .error, "[audio] AudioRendererPlayer toCMSampleBuffer failed — dropped \(array.count) frame(s) fmt=\(render.audioFormat.description) ts=\(render.timestamp)")
                continue
            }
            let channelCount = render.audioFormat.channelCount
            renderer.audioTimePitchAlgorithm = channelCount > 2 ? .spectral : .timeDomain
            renderer.enqueue(sampleBuffer)
            #if !os(macOS)
            if AVAudioSession.sharedInstance().preferredOutputNumberOfChannels != channelCount {
                try? AVAudioSession.sharedInstance().setPreferredOutputNumberOfChannels(Int(channelCount))
            }
            #endif
        }
    }
}
