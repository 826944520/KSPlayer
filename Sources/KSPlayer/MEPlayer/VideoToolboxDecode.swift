


import FFmpegKit
import Libavformat
#if canImport(VideoToolbox)
import VideoToolbox

class VideoToolboxDecode: DecodeProtocol {
    private var session: DecompressionSession {
        didSet {
            VTDecompressionSessionInvalidate(oldValue.decompressionSession)
        }
    }

    private let options: KSOptions
    private var startTime = Int64(0)
    private var lastPosition = Int64(0)
    private var needReconfig = false

    init(options: KSOptions, session: DecompressionSession) {
        self.options = options
        self.session = session
    }

    func decodeFrame(from packet: Packet, completionHandler: @escaping (Result<MEFrame, Error>) -> Void) {
        if needReconfig {
            KSLog(level: .info, "[video] VT session reconfig for track \(session.assetTrack.trackID)")
            guard let newSession = DecompressionSession(assetTrack: session.assetTrack, options: options) else {
                KSLog(level: .error, "[video] VTDecompressionSession reconfig failed — switching to software decode")
                needReconfig = false
                completionHandler(.failure(NSError(errorCode: .codecVideoReceiveFrame, avErrorCode: kVTInvalidSessionErr)))
                return
            }
            session = newSession
            doFlushCodec()
            needReconfig = false
        }
        guard let corePacket = packet.corePacket?.pointee, let data = corePacket.data else {
            KSLog(level: .debug, "[video] VT decode dropped packet (no corePacket/data) stream \(packet.assetTrack.trackID)")
            return
        }
        do {
            let sampleBuffer = try session.formatDescription.getSampleBuffer(isConvertNALSize: session.assetTrack.isConvertNALSize, data: data, size: Int(corePacket.size))
            let flags: VTDecodeFrameFlags = [
                ._EnableAsynchronousDecompression,
            ]
            var flagOut = VTDecodeInfoFlags.frameDropped
            let timestamp = packet.timestamp
            let packetFlags = corePacket.flags
            let duration = corePacket.duration
            let size = corePacket.size
            let status = VTDecompressionSessionDecodeFrame(session.decompressionSession, sampleBuffer: sampleBuffer, flags: flags, infoFlagsOut: &flagOut) { [weak self] status, infoFlags, imageBuffer, _, _ in
                guard let self, !infoFlags.contains(.frameDropped) else {
                    return
                }
                guard status == noErr else {
                    KSLog(level: .error, "[video] VT decode callback failed status=\(status) keyframe=\(packet.isKeyFrame)")
                    if status == kVTInvalidSessionErr || status == kVTVideoDecoderMalfunctionErr || status == kVTVideoDecoderBadDataErr {
                        if packet.isKeyFrame {
                            completionHandler(.failure(NSError(errorCode: .codecVideoReceiveFrame, avErrorCode: status)))
                        } else {

                            self.needReconfig = true
                        }
                    }
                    return
                }
                let frame = VideoVTBFrame(fps: session.assetTrack.nominalFrameRate, isDovi: session.assetTrack.dovi != nil)
                frame.corePixelBuffer = imageBuffer
                frame.timebase = session.assetTrack.timebase
                if packet.isKeyFrame, packetFlags & AV_PKT_FLAG_DISCARD != 0, self.lastPosition > 0 {
                    self.startTime = self.lastPosition - timestamp
                }
                self.lastPosition = max(self.lastPosition, timestamp)
                frame.position = packet.position
                frame.timestamp = self.startTime + timestamp
                frame.duration = duration
                frame.size = size
                self.lastPosition += frame.duration
                completionHandler(.success(frame))
            }
            if status == noErr {
                if !flags.contains(._EnableAsynchronousDecompression) {
                    VTDecompressionSessionWaitForAsynchronousFrames(session.decompressionSession)
                }
            } else if status == kVTInvalidSessionErr || status == kVTVideoDecoderMalfunctionErr || status == kVTVideoDecoderBadDataErr {
                KSLog(level: .error, "[video] VTDecompressionSessionDecodeFrame failed status=\(status)")
                if packet.isKeyFrame {
                    throw NSError(errorCode: .codecVideoReceiveFrame, avErrorCode: status)
                } else {

                    needReconfig = true
                }
            } else {
                KSLog(level: .error, "[video] VTDecompressionSessionDecodeFrame unexpected status=\(status)")
            }
        } catch {
            completionHandler(.failure(error))
        }
    }

    func doFlushCodec() {
        lastPosition = 0
        startTime = 0
    }

    func shutdown() {
        VTDecompressionSessionInvalidate(session.decompressionSession)
    }

    func decode() {
        lastPosition = 0
        startTime = 0
    }
}

class DecompressionSession {
    fileprivate let formatDescription: CMFormatDescription
    fileprivate let decompressionSession: VTDecompressionSession
    fileprivate var assetTrack: FFmpegAssetTrack
    init?(assetTrack: FFmpegAssetTrack, options: KSOptions) {
        self.assetTrack = assetTrack
        guard let pixelFormatType = assetTrack.pixelFormatType, let formatDescription = assetTrack.formatDescription else {
            KSLog(level: .error, "[video] DecompressionSession: missing pixelFormatType/formatDescription (codecId=\(assetTrack.codecpar.codec_id.rawValue))")
            return nil
        }
        self.formatDescription = formatDescription
        #if os(macOS)
        VTRegisterProfessionalVideoWorkflowVideoDecoders()
        if #available(macOS 11.0, *) {
            VTRegisterSupplementalVideoDecoderIfAvailable(formatDescription.mediaSubType.rawValue)
        }
        #endif

        let attributes: NSMutableDictionary = [
            kCVPixelBufferPixelFormatTypeKey: pixelFormatType,
            kCVPixelBufferMetalCompatibilityKey: true,
            kCVPixelBufferWidthKey: assetTrack.codecpar.width,
            kCVPixelBufferHeightKey: assetTrack.codecpar.height,
            kCVPixelBufferIOSurfacePropertiesKey: NSDictionary(),
        ]
        var session: VTDecompressionSession?

        let status = VTDecompressionSessionCreate(allocator: kCFAllocatorDefault, formatDescription: formatDescription, decoderSpecification: CMFormatDescriptionGetExtensions(formatDescription), imageBufferAttributes: attributes, outputCallback: nil, decompressionSessionOut: &session)

        guard status == noErr, let decompressionSession = session else {
            KSLog(level: .error, "[video] VTDecompressionSessionCreate failed status=\(status) codecId=\(assetTrack.codecpar.codec_id.rawValue)")
            return nil
        }
        if #available(iOS 14.0, tvOS 14.0, macOS 11.0, *) {
            let propStatus = VTSessionSetProperty(decompressionSession, key: kVTDecompressionPropertyKey_PropagatePerFrameHDRDisplayMetadata,
                                                  value: kCFBooleanTrue)
            if propStatus != noErr {
                KSLog(level: .error, "[video] VTSessionSetProperty HDR metadata failed status=\(propStatus)")
            }
        }
        if let destinationDynamicRange = options.availableDynamicRange(nil) {
            let pixelTransferProperties = [kVTPixelTransferPropertyKey_DestinationColorPrimaries: destinationDynamicRange.colorPrimaries,
                                           kVTPixelTransferPropertyKey_DestinationTransferFunction: destinationDynamicRange.transferFunction,
                                           kVTPixelTransferPropertyKey_DestinationYCbCrMatrix: destinationDynamicRange.yCbCrMatrix]
            let propStatus = VTSessionSetProperty(decompressionSession,
                                                  key: kVTDecompressionPropertyKey_PixelTransferProperties,
                                                  value: pixelTransferProperties as CFDictionary)
            if propStatus != noErr {
                KSLog(level: .error, "[video] VTSessionSetProperty pixelTransfer failed status=\(propStatus)")
            }
        }
        self.decompressionSession = decompressionSession
    }
}
#endif

extension CMFormatDescription {
    fileprivate func getSampleBuffer(isConvertNALSize: Bool, data: UnsafeMutablePointer<UInt8>, size: Int) throws -> CMSampleBuffer {
        if isConvertNALSize {
            var ioContext: UnsafeMutablePointer<AVIOContext>?
            let status = avio_open_dyn_buf(&ioContext)
            if status == 0 {
                var nalSize: UInt32 = 0
                let end = data + size
                var nalStart = data
                while nalStart < end {
                    nalSize = UInt32(nalStart[0]) << 16 | UInt32(nalStart[1]) << 8 | UInt32(nalStart[2])
                    avio_wb32(ioContext, nalSize)
                    nalStart += 3
                    avio_write(ioContext, nalStart, Int32(nalSize))
                    nalStart += Int(nalSize)
                }
                var demuxBuffer: UnsafeMutablePointer<UInt8>?
                let demuxSze = avio_close_dyn_buf(ioContext, &demuxBuffer)
                return try createSampleBuffer(data: demuxBuffer, size: Int(demuxSze))
            } else {
                throw NSError(errorCode: .codecVideoReceiveFrame, avErrorCode: status)
            }
        } else {
            return try createSampleBuffer(data: data, size: size)
        }
    }

    private func createSampleBuffer(data: UnsafeMutablePointer<UInt8>?, size: Int) throws -> CMSampleBuffer {
        var blockBuffer: CMBlockBuffer?
        var sampleBuffer: CMSampleBuffer?

        var status = CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: data, blockLength: size, blockAllocator: kCFAllocatorNull, customBlockSource: nil, offsetToData: 0, dataLength: size, flags: 0, blockBufferOut: &blockBuffer)
        if status == noErr {
            status = CMSampleBufferCreate(allocator: kCFAllocatorDefault, dataBuffer: blockBuffer, dataReady: true, makeDataReadyCallback: nil, refcon: nil, formatDescription: self, sampleCount: 1, sampleTimingEntryCount: 0, sampleTimingArray: nil, sampleSizeEntryCount: 0, sampleSizeArray: nil, sampleBufferOut: &sampleBuffer)
            if let sampleBuffer {
                return sampleBuffer
            }
        }
        throw NSError(errorCode: .codecVideoReceiveFrame, avErrorCode: status)

    }
}

extension CMVideoCodecType {
    var avc: String {
        switch self {
        case kCMVideoCodecType_MPEG4Video:
            return "esds"
        case kCMVideoCodecType_H264:
            return "avcC"
        case kCMVideoCodecType_HEVC:
            return "hvcC"
        case kCMVideoCodecType_VP9:
            return "vpcC"
        default: return "avcC"
        }
    }
}
