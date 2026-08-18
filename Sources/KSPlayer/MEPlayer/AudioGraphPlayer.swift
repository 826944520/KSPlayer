


import AudioToolbox
import AVFAudio
import CoreAudio

public final class AudioGraphPlayer: AudioOutput, AudioDynamicsProcessor {
    public private(set) var audioUnitForDynamicsProcessor: AudioUnit
    private let graph: AUGraph
    private var audioUnitForMixer: AudioUnit!
    private var audioUnitForTimePitch: AudioUnit!
    private var audioUnitForOutput: AudioUnit!
    private var currentRenderReadOffset = UInt32(0)
    private var sourceNodeAudioFormat: AVAudioFormat?
    private var sampleSize = UInt32(MemoryLayout<Float>.size)
    #if os(macOS)
    private var volumeBeforeMute: Float = 0.0
    #endif
    private var outputLatency = TimeInterval(0)
    public weak var renderSource: OutputRenderSourceDelegate?
    private var currentRender: AudioFrame? {
        didSet {
            if currentRender == nil {
                currentRenderReadOffset = 0
            }
        }
    }

    public func play() {
        let status = AUGraphStart(graph)
        if status != noErr {
            KSLog(level: .error, "[audio] AUGraphStart failed status=\(status)")
        }
    }

    public func pause() {
        let status = AUGraphStop(graph)
        if status != noErr {
            KSLog(level: .error, "[audio] AUGraphStop failed status=\(status)")
        }
    }

    public var playbackRate: Float {
        get {
            var playbackRate = AudioUnitParameterValue(0.0)
            AudioUnitGetParameter(audioUnitForTimePitch, kNewTimePitchParam_Rate, kAudioUnitScope_Global, 0, &playbackRate)
            return playbackRate
        }
        set {
            AudioUnitSetParameter(audioUnitForTimePitch, kNewTimePitchParam_Rate, kAudioUnitScope_Global, 0, newValue, 0)
        }
    }

    public var volume: Float {
        get {
            var volume = AudioUnitParameterValue(0.0)
            #if os(macOS)
            let inID = kStereoMixerParam_Volume
            #else
            let inID = kMultiChannelMixerParam_Volume
            #endif
            AudioUnitGetParameter(audioUnitForMixer, inID, kAudioUnitScope_Input, 0, &volume)
            return volume
        }
        set {
            #if os(macOS)
            let inID = kStereoMixerParam_Volume
            #else
            let inID = kMultiChannelMixerParam_Volume
            #endif
            AudioUnitSetParameter(audioUnitForMixer, inID, kAudioUnitScope_Input, 0, newValue, 0)
        }
    }

    public var isMuted: Bool {
        get {
            var value = AudioUnitParameterValue(1.0)
            #if os(macOS)
            AudioUnitGetParameter(audioUnitForMixer, kStereoMixerParam_Volume, kAudioUnitScope_Input, 0, &value)
            #else
            AudioUnitGetParameter(audioUnitForMixer, kMultiChannelMixerParam_Enable, kAudioUnitScope_Input, 0, &value)
            #endif
            return value == 0
        }
        set {
            let value = newValue ? 0 : 1
            #if os(macOS)
            if value == 0 {
                volumeBeforeMute = volume
            }
            AudioUnitSetParameter(audioUnitForMixer, kStereoMixerParam_Volume, kAudioUnitScope_Input, 0, min(Float(value), volumeBeforeMute), 0)
            #else
            AudioUnitSetParameter(audioUnitForMixer, kMultiChannelMixerParam_Enable, kAudioUnitScope_Input, 0, AudioUnitParameterValue(value), 0)
            #endif
        }
    }

    public init() {
        var newGraph: AUGraph!
        NewAUGraph(&newGraph)
        graph = newGraph
        var descriptionForTimePitch = AudioComponentDescription()
        descriptionForTimePitch.componentType = kAudioUnitType_FormatConverter
        descriptionForTimePitch.componentSubType = kAudioUnitSubType_NewTimePitch
        descriptionForTimePitch.componentManufacturer = kAudioUnitManufacturer_Apple
        var descriptionForDynamicsProcessor = AudioComponentDescription()
        descriptionForDynamicsProcessor.componentType = kAudioUnitType_Effect
        descriptionForDynamicsProcessor.componentManufacturer = kAudioUnitManufacturer_Apple
        descriptionForDynamicsProcessor.componentSubType = kAudioUnitSubType_DynamicsProcessor
        var descriptionForMixer = AudioComponentDescription()
        descriptionForMixer.componentType = kAudioUnitType_Mixer
        descriptionForMixer.componentManufacturer = kAudioUnitManufacturer_Apple
        #if os(macOS)
        descriptionForMixer.componentSubType = kAudioUnitSubType_StereoMixer
        #else
        descriptionForMixer.componentSubType = kAudioUnitSubType_MultiChannelMixer
        #endif
        var descriptionForOutput = AudioComponentDescription()
        descriptionForOutput.componentType = kAudioUnitType_Output
        descriptionForOutput.componentManufacturer = kAudioUnitManufacturer_Apple
        #if os(macOS)
        descriptionForOutput.componentSubType = kAudioUnitSubType_DefaultOutput
        #else
        descriptionForOutput.componentSubType = kAudioUnitSubType_RemoteIO
        #endif
        var nodeForTimePitch = AUNode()
        var nodeForDynamicsProcessor = AUNode()
        var nodeForMixer = AUNode()
        var nodeForOutput = AUNode()
        var status = AUGraphAddNode(graph, &descriptionForTimePitch, &nodeForTimePitch)
        if status != noErr { KSLog(level: .error, "[audio] AUGraphAddNode(timePitch) failed status=\(status)") }
        status = AUGraphAddNode(graph, &descriptionForMixer, &nodeForMixer)
        if status != noErr { KSLog(level: .error, "[audio] AUGraphAddNode(mixer) failed status=\(status)") }
        status = AUGraphAddNode(graph, &descriptionForDynamicsProcessor, &nodeForDynamicsProcessor)
        if status != noErr { KSLog(level: .error, "[audio] AUGraphAddNode(dynamics) failed status=\(status)") }
        status = AUGraphAddNode(graph, &descriptionForOutput, &nodeForOutput)
        if status != noErr { KSLog(level: .error, "[audio] AUGraphAddNode(output) failed status=\(status)") }
        status = AUGraphOpen(graph)
        if status != noErr { KSLog(level: .error, "[audio] AUGraphOpen failed status=\(status)") }
        status = AUGraphConnectNodeInput(graph, nodeForTimePitch, 0, nodeForDynamicsProcessor, 0)
        if status != noErr { KSLog(level: .error, "[audio] AUGraphConnect(timePitch→dynamics) failed status=\(status)") }
        status = AUGraphConnectNodeInput(graph, nodeForDynamicsProcessor, 0, nodeForMixer, 0)
        if status != noErr { KSLog(level: .error, "[audio] AUGraphConnect(dynamics→mixer) failed status=\(status)") }
        status = AUGraphConnectNodeInput(graph, nodeForMixer, 0, nodeForOutput, 0)
        if status != noErr { KSLog(level: .error, "[audio] AUGraphConnect(mixer→output) failed status=\(status)") }
        AUGraphNodeInfo(graph, nodeForTimePitch, &descriptionForTimePitch, &audioUnitForTimePitch)
        var dynamicsUnit: AudioUnit?
        status = AUGraphNodeInfo(graph, nodeForDynamicsProcessor, &descriptionForDynamicsProcessor, &dynamicsUnit)
        if status != noErr || dynamicsUnit == nil {
            KSLog(level: .error, "[audio] AUGraphNodeInfo(dynamics) failed status=\(status)")
        }
        AUGraphNodeInfo(graph, nodeForMixer, &descriptionForMixer, &audioUnitForMixer)
        AUGraphNodeInfo(graph, nodeForOutput, &descriptionForOutput, &audioUnitForOutput)
        if let dynamicsUnit {
            self.audioUnitForDynamicsProcessor = dynamicsUnit
        } else {
            // The dynamics node sits in the required chain (timePitch→dynamics→mixer);
            // if its unit failed to instantiate, reuse the mixer unit so the protocol
            // property still holds a valid AudioUnit instead of crashing on a force unwrap.
            self.audioUnitForDynamicsProcessor = audioUnitForMixer
        }
        addRenderNotify(audioUnit: audioUnitForOutput)
        var value = UInt32(1)
        status = AudioUnitSetProperty(audioUnitForTimePitch,
                                      kAudioOutputUnitProperty_EnableIO,
                                      kAudioUnitScope_Output, 0,
                                      &value,
                                      UInt32(MemoryLayout<UInt32>.size))
        if status != noErr {
            KSLog(level: .error, "[audio] EnableIO(timePitch) failed status=\(status)")
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
        sampleSize = audioFormat.sampleSize
        var audioStreamBasicDescription = audioFormat.formatDescription.audioStreamBasicDescription
        let audioStreamBasicDescriptionSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        let channelLayout = audioFormat.channelLayout?.layout
        // AudioUnit is an opaque pointer (COpaquePointer-backed struct), so we
        // identify units by position/name rather than `===`/`!=` (which only
        // work on class instances).
        let units: [(name: String, unit: AudioUnit?)] = [
            (name: "timePitch", unit: audioUnitForTimePitch),
            (name: "dynamics", unit: audioUnitForDynamicsProcessor),
            (name: "mixer", unit: audioUnitForMixer),
            (name: "output", unit: audioUnitForOutput),
        ]
        for (unitName, unit) in units {
            guard let unit else { continue }
            var unitStatus = AudioUnitSetProperty(unit,
                                                  kAudioUnitProperty_StreamFormat,
                                                  kAudioUnitScope_Input, 0,
                                                  &audioStreamBasicDescription,
                                                  audioStreamBasicDescriptionSize)
            if unitStatus != noErr {
                KSLog(level: .error, "[audio] \(unitName) set StreamFormat(input) failed status=\(unitStatus)")
            }
            unitStatus = AudioUnitSetProperty(unit,
                                              kAudioUnitProperty_AudioChannelLayout,
                                              kAudioUnitScope_Input, 0,
                                              channelLayout,
                                              UInt32(MemoryLayout<AudioChannelLayout>.size))
            if unitStatus != noErr {
                KSLog(level: .error, "[audio] \(unitName) set AudioChannelLayout(input) failed status=\(unitStatus)")
            }
            if unitName != "output" {
                unitStatus = AudioUnitSetProperty(unit,
                                                  kAudioUnitProperty_StreamFormat,
                                                  kAudioUnitScope_Output, 0,
                                                  &audioStreamBasicDescription,
                                                  audioStreamBasicDescriptionSize)
                if unitStatus != noErr {
                    KSLog(level: .error, "[audio] \(unitName) set StreamFormat(output) failed status=\(unitStatus)")
                }
                unitStatus = AudioUnitSetProperty(unit,
                                                  kAudioUnitProperty_AudioChannelLayout,
                                                  kAudioUnitScope_Output, 0,
                                                  channelLayout,
                                                  UInt32(MemoryLayout<AudioChannelLayout>.size))
                if unitStatus != noErr {
                    KSLog(level: .error, "[audio] \(unitName) set AudioChannelLayout(output) failed status=\(unitStatus)")
                }
            }
            if unitName == "timePitch" {
                var inputCallbackStruct = renderCallbackStruct()
                unitStatus = AudioUnitSetProperty(unit,
                                                  kAudioUnitProperty_SetRenderCallback,
                                                  kAudioUnitScope_Input, 0,
                                                  &inputCallbackStruct,
                                                  UInt32(MemoryLayout<AURenderCallbackStruct>.size))
                if unitStatus != noErr {
                    KSLog(level: .error, "[audio] \(unitName) set RenderCallback failed status=\(unitStatus)")
                }
            }
        }
        let graphStatus = AUGraphInitialize(graph)
        if graphStatus != noErr {
            KSLog(level: .error, "[audio] AUGraphInitialize failed status=\(graphStatus)")
        }
        KSLog(level: .info, "[audio] AudioGraphPlayer prepared rate=\(audioFormat.sampleRate) ch=\(audioFormat.channelCount) fmt=\(audioFormat.sampleSize * 8)-bit")
    }

    public func flush() {
        currentRender = nil
        #if !os(macOS)
        outputLatency = AVAudioSession.sharedInstance().outputLatency
        #endif
    }

    deinit {
        AUGraphStop(graph)
        AUGraphUninitialize(graph)
        AUGraphClose(graph)
        DisposeAUGraph(graph)
    }
}

extension AudioGraphPlayer {
    private func renderCallbackStruct() -> AURenderCallbackStruct {
        var inputCallbackStruct = AURenderCallbackStruct()
        inputCallbackStruct.inputProcRefCon = Unmanaged.passUnretained(self).toOpaque()
        inputCallbackStruct.inputProc = { refCon, _, _, _, inNumberFrames, ioData in
            guard let ioData else {
                return noErr
            }
            let `self` = Unmanaged<AudioGraphPlayer>.fromOpaque(refCon).takeUnretainedValue()
            self.audioPlayerShouldInputData(ioData: UnsafeMutableAudioBufferListPointer(ioData), numberOfFrames: inNumberFrames)
            return noErr
        }
        return inputCallbackStruct
    }

    private func addRenderNotify(audioUnit: AudioUnit) {
        AudioUnitAddRenderNotify(audioUnit, { refCon, ioActionFlags, inTimeStamp, _, _, _ in
            let `self` = Unmanaged<AudioGraphPlayer>.fromOpaque(refCon).takeUnretainedValue()
            autoreleasepool {
                if ioActionFlags.pointee.contains(.unitRenderAction_PostRender) {
                    self.audioPlayerDidRenderSample(sampleTimestamp: inTimeStamp.pointee)
                }
            }
            return noErr
        }, Unmanaged.passUnretained(self).toOpaque())
    }

    private func audioPlayerShouldInputData(ioData: UnsafeMutableAudioBufferListPointer, numberOfFrames: UInt32) {
        var ioDataWriteOffset = 0
        var numberOfSamples = numberOfFrames
        while numberOfSamples > 0 {
            if currentRender == nil {
                currentRender = renderSource?.getAudioOutputRender()
            }
            guard let currentRender else {
                break
            }
            let residueLinesize = currentRender.numberOfSamples - currentRenderReadOffset
            guard residueLinesize > 0 else {
                self.currentRender = nil
                continue
            }
            if sourceNodeAudioFormat != currentRender.audioFormat {
                runOnMainThread { [weak self] in
                    guard let self else {
                        return
                    }
                    self.prepare(audioFormat: currentRender.audioFormat)
                }
                return
            }
            let framesToCopy = min(numberOfSamples, residueLinesize)
            let bytesToCopy = Int(framesToCopy * sampleSize)
            let offset = Int(currentRenderReadOffset * sampleSize)
            for i in 0 ..< min(ioData.count, currentRender.data.count) {
                if let source = currentRender.data[i], let destination = ioData[i].mData {
                    (destination + ioDataWriteOffset).copyMemory(from: source + offset, byteCount: bytesToCopy)
                }
            }
            numberOfSamples -= framesToCopy
            ioDataWriteOffset += bytesToCopy
            currentRenderReadOffset += framesToCopy
        }
        let sizeCopied = (numberOfFrames - numberOfSamples) * sampleSize
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
