


import AVFoundation
import CoreAudio

public protocol AudioOutput: FrameOutput {
    var playbackRate: Float { get set }
    var volume: Float { get set }
    var isMuted: Bool { get set }
    init()
    func prepare(audioFormat: AVAudioFormat)
}

public protocol AudioDynamicsProcessor {
    var audioUnitForDynamicsProcessor: AudioUnit { get }
}

public extension AudioDynamicsProcessor {
    var attackTime: Float {
        get {
            var value = AudioUnitParameterValue(1.0)
            AudioUnitGetParameter(audioUnitForDynamicsProcessor, kDynamicsProcessorParam_AttackTime, kAudioUnitScope_Global, 0, &value)
            return value
        }
        set {
            AudioUnitSetParameter(audioUnitForDynamicsProcessor, kDynamicsProcessorParam_AttackTime, kAudioUnitScope_Global, 0, AudioUnitParameterValue(newValue), 0)
        }
    }

    var releaseTime: Float {
        get {
            var value = AudioUnitParameterValue(1.0)
            AudioUnitGetParameter(audioUnitForDynamicsProcessor, kDynamicsProcessorParam_ReleaseTime, kAudioUnitScope_Global, 0, &value)
            return value
        }
        set {
            AudioUnitSetParameter(audioUnitForDynamicsProcessor, kDynamicsProcessorParam_ReleaseTime, kAudioUnitScope_Global, 0, AudioUnitParameterValue(newValue), 0)
        }
    }

    var threshold: Float {
        get {
            var value = AudioUnitParameterValue(1.0)
            AudioUnitGetParameter(audioUnitForDynamicsProcessor, kDynamicsProcessorParam_Threshold, kAudioUnitScope_Global, 0, &value)
            return value
        }
        set {
            AudioUnitSetParameter(audioUnitForDynamicsProcessor, kDynamicsProcessorParam_Threshold, kAudioUnitScope_Global, 0, AudioUnitParameterValue(newValue), 0)
        }
    }

    var expansionRatio: Float {
        get {
            var value = AudioUnitParameterValue(1.0)
            AudioUnitGetParameter(audioUnitForDynamicsProcessor, kDynamicsProcessorParam_ExpansionRatio, kAudioUnitScope_Global, 0, &value)
            return value
        }
        set {
            AudioUnitSetParameter(audioUnitForDynamicsProcessor, kDynamicsProcessorParam_ExpansionRatio, kAudioUnitScope_Global, 0, AudioUnitParameterValue(newValue), 0)
        }
    }

    var overallGain: Float {
        get {
            var value = AudioUnitParameterValue(1.0)
            AudioUnitGetParameter(audioUnitForDynamicsProcessor, kDynamicsProcessorParam_OverallGain, kAudioUnitScope_Global, 0, &value)
            return value
        }
        set {
            AudioUnitSetParameter(audioUnitForDynamicsProcessor, kDynamicsProcessorParam_OverallGain, kAudioUnitScope_Global, 0, AudioUnitParameterValue(newValue), 0)
        }
    }
}

public final class AudioEngineDynamicsPlayer: AudioEnginePlayer, AudioDynamicsProcessor {
    private let dynamicsProcessor = AVAudioUnitEffect(audioComponentDescription:
        AudioComponentDescription(componentType: kAudioUnitType_Effect,
                                  componentSubType: kAudioUnitSubType_DynamicsProcessor,
                                  componentManufacturer: kAudioUnitManufacturer_Apple,
                                  componentFlags: 0,
                                  componentFlagsMask: 0))
    public var audioUnitForDynamicsProcessor: AudioUnit {
        dynamicsProcessor.audioUnit
    }

    override func audioNodes() -> [AVAudioNode] {
        var nodes: [AVAudioNode] = [dynamicsProcessor]
        nodes.append(contentsOf: super.audioNodes())
        return nodes
    }

    public required init() {
        super.init()
        engine.attach(dynamicsProcessor)
    }
}

public class AudioEnginePlayer: AudioOutput {
    public let engine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode?
    // Fix: Protect shared state with a lock to prevent data races between audio render thread and main thread
    private let stateLock = NSLock()
    private var sourceNodeAudioFormat: AVAudioFormat? {
        didSet {
            stateLock.lock()
            sourceNodeAudioFormatSync = oldValue
            stateLock.unlock()
        }
    }
    // Synchronized copy for audio render thread
    private var sourceNodeAudioFormatSync: AVAudioFormat?


    private let timePitch = AVAudioUnitTimePitch()
    private var sampleSize = UInt32(MemoryLayout<Float>.size) {
        didSet {
            stateLock.lock()
            sampleSizeSync = oldValue
            stateLock.unlock()
        }
    }
    private var sampleSizeSync = UInt32(MemoryLayout<Float>.size)
    private var currentRenderReadOffset = UInt32(0) {
        didSet {
            stateLock.lock()
            currentRenderReadOffsetSync = oldValue
            stateLock.unlock()
        }
    }
    private var currentRenderReadOffsetSync = UInt32(0)
    private var outputLatency = TimeInterval(0)
    public weak var renderSource: OutputRenderSourceDelegate?
    private var currentRender: AudioFrame? {
        didSet {
            stateLock.lock()
            if currentRender == nil {
                currentRenderReadOffset = 0
                currentRenderReadOffsetSync = 0
            }
            stateLock.unlock()
        }
    }

    public var playbackRate: Float {
        get {
            timePitch.rate
        }
        set {
            timePitch.rate = min(32, max(1 / 32, newValue))
        }
    }

    public var volume: Float {
        get {
            sourceNode?.volume ?? 1
        }
        set {
            sourceNode?.volume = newValue
        }
    }

    public var isMuted: Bool {
        get {
            engine.mainMixerNode.outputVolume == 0.0
        }
        set {
            engine.mainMixerNode.outputVolume = newValue ? 0.0 : 1.0
        }
    }

    public required init() {
        engine.attach(timePitch)
        if let audioUnit = engine.outputNode.audioUnit {
            addRenderNotify(audioUnit: audioUnit)
        }
        #if !os(macOS)
        outputLatency = AVAudioSession.sharedInstance().outputLatency
        #endif
    }

    public func prepare(audioFormat: AVAudioFormat) {
        if sourceNodeAudioFormat == audioFormat {
            return
        }
        sourceNodeAudioFormat = audioFormat
        #if !os(macOS)
        try? AVAudioSession.sharedInstance().setPreferredOutputNumberOfChannels(Int(audioFormat.channelCount))
        KSLog("[audio] set preferredOutputNumberOfChannels: \(audioFormat.channelCount)")
        #endif
        KSLog("[audio] outputFormat AudioFormat: \(audioFormat)")
        if let channelLayout = audioFormat.channelLayout {
            KSLog("[audio] outputFormat channelLayout \(channelLayout.channelDescriptions)")
        }
        let isRunning = engine.isRunning
        engine.stop()
        engine.reset()
        sourceNode = AVAudioSourceNode(format: audioFormat) { [weak self] _, timestamp, frameCount, audioBufferList in
            if timestamp.pointee.mSampleTime == 0 {
                return noErr
            }
            self?.audioPlayerShouldInputData(ioData: UnsafeMutableAudioBufferListPointer(audioBufferList), numberOfFrames: frameCount)
            return noErr
        }
        guard let sourceNode else {
            return
        }
        KSLog("[audio] new sourceNode inputFormat: \(sourceNode.inputFormat(forBus: 0))")
        sampleSize = audioFormat.sampleSize
        engine.attach(sourceNode)
        var nodes: [AVAudioNode] = [sourceNode]
        nodes.append(contentsOf: audioNodes())
        if audioFormat.channelCount > 2 {
            nodes.append(engine.outputNode)
        }

        engine.connect(nodes: nodes, format: audioFormat)
        engine.prepare()
        if isRunning {
            try? engine.start()

            DispatchQueue.main.async { [weak self] in
                self?.play()
            }
        }
    }

    func audioNodes() -> [AVAudioNode] {
        [timePitch, engine.mainMixerNode]
    }

    public func play() {
        if !engine.isRunning {
            do {
                try engine.start()
            } catch {
                KSLog(error)
            }
        }
    }

    public func pause() {
        if engine.isRunning {
            engine.pause()
        }
    }

    public func flush() {
        stateLock.lock()
        currentRender = nil
        currentRenderReadOffset = 0
        currentRenderReadOffsetSync = 0
        stateLock.unlock()
        #if !os(macOS)

        outputLatency = AVAudioSession.sharedInstance().outputLatency
        #endif
    }

    private func addRenderNotify(audioUnit: AudioUnit) {
        // Fix: Use retain to prevent use-after-free if player is deallocated before callback fires
        AudioUnitAddRenderNotify(audioUnit, { refCon, ioActionFlags, inTimeStamp, _, _, _ in
            let `self` = Unmanaged<AudioEnginePlayer>.fromOpaque(refCon).takeRetainedValue()
            autoreleasepool {
                if ioActionFlags.pointee.contains(.unitRenderAction_PostRender) {
                    self.audioPlayerDidRenderSample(sampleTimestamp: inTimeStamp.pointee)
                }
            }
            // Release the retain
            _ = Unmanaged.passRetained(self)
            return noErr
        }, Unmanaged.passRetained(self).toOpaque())
    }

    deinit {
        // Remove render notify to prevent callbacks after deallocation
        if let audioUnit = engine.outputNode.audioUnit {
            AudioUnitRemoveRenderNotify(audioUnit, { refCon, ioActionFlags, inTimeStamp, _, _, _ in
                _ = Unmanaged<AudioEnginePlayer>.fromOpaque(refCon).takeRetainedValue()
                return noErr
            }, Unmanaged.passUnretained(self).toOpaque())
        }
    }



    private func audioPlayerShouldInputData(ioData: UnsafeMutableAudioBufferListPointer, numberOfFrames: UInt32) {
        // Fix: Acquire lock to safely access synchronized state
        stateLock.lock()
        let localCurrentRender = currentRender
        let localCurrentRenderReadOffset = currentRenderReadOffsetSync
        let localSampleSize = sampleSizeSync
        let localSourceNodeAudioFormat = sourceNodeAudioFormatSync
        stateLock.unlock()

        var ioDataWriteOffset = 0
        var numberOfSamples = numberOfFrames
        while numberOfSamples > 0 {
            if localCurrentRender == nil {
                stateLock.lock()
                if currentRender == nil {
                    currentRender = renderSource?.getAudioOutputRender()
                }
                stateLock.unlock()
            }
            guard let currentRender else {
                break
            }
            stateLock.lock()
            let residueLinesize = currentRender.numberOfSamples - currentRenderReadOffsetSync
            let currentReadOffset = currentRenderReadOffsetSync
            let currentSampleSize = sampleSizeSync
            let sourceFormat = sourceNodeAudioFormatSync
            stateLock.unlock()
            guard residueLinesize > 0 else {
                stateLock.lock()
                self.currentRender = nil
                currentRenderReadOffsetSync = 0
                stateLock.unlock()
                continue
            }
            if sourceFormat != currentRender.audioFormat {
                runOnMainThread { [weak self] in
                    guard let self else {
                        return
                    }
                    self.prepare(audioFormat: currentRender.audioFormat)
                }
                return
            }
            let framesToCopy = min(numberOfSamples, residueLinesize)
            let bytesToCopy = Int(framesToCopy * currentSampleSize)
            let offset = Int(currentReadOffset * currentSampleSize)
            for i in 0 ..< min(ioData.count, currentRender.data.count) {
                if let source = currentRender.data[i], let destination = ioData[i].mData {
                    (destination + ioDataWriteOffset).copyMemory(from: source + offset, byteCount: bytesToCopy)
                }
            }
            numberOfSamples -= framesToCopy
            ioDataWriteOffset += bytesToCopy
            stateLock.lock()
            currentRenderReadOffsetSync += framesToCopy
            currentRenderReadOffset = currentRenderReadOffsetSync
            stateLock.unlock()
        }
        let sizeCopied = (numberOfFrames - numberOfSamples) * localSampleSize
        for i in 0 ..< ioData.count {
            let sizeLeft = Int(ioData[i].mDataByteSize - sizeCopied)
            if sizeLeft > 0 {
                memset(ioData[i].mData! + Int(sizeCopied), 0, sizeLeft)
            }
        }
    }

    private func audioPlayerDidRenderSample(sampleTimestamp _: AudioTimeStamp) {
        if let currentRender {
            let currentPreparePosition = currentRender.timestamp + currentRender.duration * Int64(currentRenderReadOffset) / Int64(currentRender.numberOfSamples)
            if currentPreparePosition > 0 {
                var time = currentRender.timebase.cmtime(for: currentPreparePosition)
                if outputLatency != 0 {

                    time = time - CMTime(seconds: outputLatency, preferredTimescale: time.timescale)
                }
                renderSource?.setAudio(time: time, position: currentRender.position)
            }
        }
    }
}

extension AVAudioEngine {
    func connect(nodes: [AVAudioNode], format: AVAudioFormat?) {
        if nodes.count < 2 {
            return
        }
        for i in 0 ..< nodes.count - 1 {
            connect(nodes[i], to: nodes[i + 1], format: format)
        }
    }
}
