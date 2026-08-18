


import AudioToolbox
import AVFAudio
import CoreAudio

public final class AudioUnitPlayer: AudioOutput {
    private var audioUnitForOutput: AudioUnit!
    private var currentRenderReadOffset = UInt32(0)
    private var sourceNodeAudioFormat: AVAudioFormat?
    private var sampleSize = UInt32(MemoryLayout<Float>.size)
    public weak var renderSource: OutputRenderSourceDelegate?
    private var currentRender: AudioFrame? {
        didSet {
            if currentRender == nil {
                currentRenderReadOffset = 0
            }
        }
    }

    private var isPlaying = false
    private var underflowCount = 0
    public func play() {
        if !isPlaying {
            isPlaying = true
            guard let audioUnitForOutput else {
                KSLog(level: .error, "[audio] play() with nil audioUnitForOutput")
                return
            }
            let status = AudioOutputUnitStart(audioUnitForOutput)
            if status != noErr {
                KSLog(level: .error, "[audio] AudioOutputUnitStart failed status=\(status)")
            }
        }
    }

    public func pause() {
        if isPlaying {
            isPlaying = false
            guard let audioUnitForOutput else {
                KSLog(level: .error, "[audio] pause() with nil audioUnitForOutput")
                return
            }
            let status = AudioOutputUnitStop(audioUnitForOutput)
            if status != noErr {
                KSLog(level: .error, "[audio] AudioOutputUnitStop failed status=\(status)")
            }
        }
    }

    public var playbackRate: Float = 1
    public var volume: Float = 1
    public var isMuted: Bool = false
    private var outputLatency = TimeInterval(0)
    public init() {
        var descriptionForOutput = AudioComponentDescription()
        descriptionForOutput.componentType = kAudioUnitType_Output
        descriptionForOutput.componentManufacturer = kAudioUnitManufacturer_Apple
        #if os(macOS)
        descriptionForOutput.componentSubType = kAudioUnitSubType_HALOutput
        #else
        descriptionForOutput.componentSubType = kAudioUnitSubType_RemoteIO
        outputLatency = AVAudioSession.sharedInstance().outputLatency
        #endif
        guard let nodeForOutput = AudioComponentFindNext(nil, &descriptionForOutput) else {
            KSLog(level: .error, "[audio] AudioComponentFindNext failed (no output component)")
            return
        }
        let newStatus = AudioComponentInstanceNew(nodeForOutput, &audioUnitForOutput)
        if newStatus != noErr {
            KSLog(level: .error, "[audio] AudioComponentInstanceNew failed status=\(newStatus)")
        }
        var value = UInt32(1)
        let ioStatus = AudioUnitSetProperty(audioUnitForOutput,
                                            kAudioOutputUnitProperty_EnableIO,
                                            kAudioUnitScope_Output, 0,
                                            &value,
                                            UInt32(MemoryLayout<UInt32>.size))
        if ioStatus != noErr {
            KSLog(level: .error, "[audio] EnableIO failed status=\(ioStatus)")
        }
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
        let fmtStatus = AudioUnitSetProperty(audioUnitForOutput,
                                             kAudioUnitProperty_StreamFormat,
                                             kAudioUnitScope_Input, 0,
                                             &audioStreamBasicDescription,
                                             UInt32(MemoryLayout<AudioStreamBasicDescription>.size))
        if fmtStatus != noErr {
            KSLog(level: .error, "[audio] set StreamFormat failed status=\(fmtStatus) rate=\(audioFormat.sampleRate) ch=\(audioFormat.channelCount)")
        }
        let channelLayout = audioFormat.channelLayout?.layout
        let layoutStatus = AudioUnitSetProperty(audioUnitForOutput,
                                                kAudioUnitProperty_AudioChannelLayout,
                                                kAudioUnitScope_Input, 0,
                                                channelLayout,
                                                UInt32(MemoryLayout<AudioChannelLayout>.size))
        if layoutStatus != noErr {
            KSLog(level: .error, "[audio] set AudioChannelLayout failed status=\(layoutStatus)")
        }
        var inputCallbackStruct = renderCallbackStruct()
        let cbStatus = AudioUnitSetProperty(audioUnitForOutput,
                                            kAudioUnitProperty_SetRenderCallback,
                                            kAudioUnitScope_Input, 0,
                                            &inputCallbackStruct,
                                            UInt32(MemoryLayout<AURenderCallbackStruct>.size))
        if cbStatus != noErr {
            KSLog(level: .error, "[audio] set RenderCallback failed status=\(cbStatus)")
        }
        addRenderNotify(audioUnit: audioUnitForOutput)
        let initStatus = AudioUnitInitialize(audioUnitForOutput)
        if initStatus != noErr {
            KSLog(level: .error, "[audio] AudioUnitInitialize failed status=\(initStatus)")
        }
        KSLog(level: .info, "[audio] AudioUnitPlayer prepared rate=\(audioFormat.sampleRate) ch=\(audioFormat.channelCount) fmt=\(audioFormat.sampleSize * 8)-bit")
    }

    public func flush() {
        currentRender = nil
        #if !os(macOS)
        outputLatency = AVAudioSession.sharedInstance().outputLatency
        #endif
    }

    deinit {
        AudioUnitUninitialize(audioUnitForOutput)
    }
}

extension AudioUnitPlayer {
    private func renderCallbackStruct() -> AURenderCallbackStruct {
        var inputCallbackStruct = AURenderCallbackStruct()
        inputCallbackStruct.inputProcRefCon = Unmanaged.passUnretained(self).toOpaque()
        inputCallbackStruct.inputProc = { refCon, _, _, _, inNumberFrames, ioData in
            guard let ioData else {
                return noErr
            }
            let `self` = Unmanaged<AudioUnitPlayer>.fromOpaque(refCon).takeUnretainedValue()
            self.audioPlayerShouldInputData(ioData: UnsafeMutableAudioBufferListPointer(ioData), numberOfFrames: inNumberFrames)
            return noErr
        }
        return inputCallbackStruct
    }

    private func addRenderNotify(audioUnit: AudioUnit) {
        AudioUnitAddRenderNotify(audioUnit, { refCon, ioActionFlags, inTimeStamp, _, _, _ in
            let `self` = Unmanaged<AudioUnitPlayer>.fromOpaque(refCon).takeUnretainedValue()
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
                // Audio underflow: render callback ran out of frames. Throttled
                // (the callback is real-time; log every 60th underflow only).
                underflowCount += 1
                if underflowCount % 60 == 1 {
                    KSLog(level: .debug, "[audio] underflow: no audio frame (count=\(underflowCount))")
                }
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
                    if isMuted {
                        memset(destination + ioDataWriteOffset, 0, bytesToCopy)
                    } else {
                        (destination + ioDataWriteOffset).copyMemory(from: source + offset, byteCount: bytesToCopy)
                    }
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
