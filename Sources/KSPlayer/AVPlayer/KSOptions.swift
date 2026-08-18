


import AVFoundation
#if os(tvOS) || os(xrOS)
import DisplayCriteria
#endif
import Libavformat
import OSLog

#if canImport(UIKit)
import UIKit
#endif
open class KSOptions {

    @Published
    public var preferredForwardBufferDuration = KSOptions.preferredForwardBufferDuration

    public var maxBufferDuration = KSOptions.maxBufferDuration

    public var isSecondOpen = KSOptions.isSecondOpen

    public var isAccurateSeek = KSOptions.isAccurateSeek

    public var isLoopPlay = KSOptions.isLoopPlay

    public var loopRange: ClosedRange<TimeInterval>?

    public var isSeekedAutoPlay = KSOptions.isSeekedAutoPlay
    
    public var seekFlags = Int32(1)

    public var cache = false

    /// Directory where the `cache:` protocol (Stage 1.3) spools progressive
    /// downloads. iOS can't write to FFmpeg's default /tmp, so this must point
    /// at an app-writable directory (e.g. NSTemporaryDirectory()).
    public var cacheDirectory: URL = FileManager.default.temporaryDirectory

    public var outputURL: URL?
    public var avOptions = [String: Any]()
    public var formatContextOptions = [String: Any]()
    public var decoderOptions = [String: Any]()
    public var probesize: Int64?
    public var maxAnalyzeDuration: Int64?
    public var lowres = UInt8(0)
    public var nobuffer = false
    public var codecLowDelay = false
    public var startPlayTime: TimeInterval = 0
    public var startPlayRate: Float = 1.0
    public var registerRemoteControll: Bool = true
    public var referer: String? {
        didSet {
            if let referer {
                formatContextOptions["referer"] = "Referer: \(referer)"
            } else {
                formatContextOptions["referer"] = nil
            }
        }
    }

    public var userAgent: String? = "KSPlayer" {
        didSet {
            formatContextOptions["user_agent"] = userAgent
        }
    }


    public var audioFilters = [String]()
    public var syncDecodeAudio = false

    public var autoSelectEmbedSubtitle = true
    public var isSeekImageSubtitle = false

    public var display = DisplayEnum.plane
    public var videoDelay = 0.0
    public var autoDeInterlace = false
    public var autoRotate = true
    public var destinationDynamicRange: DynamicRange?
    public var videoAdaptable = true
    public var videoFilters = [String]()
    public var syncDecodeVideo = false
    public var hardwareDecode = KSOptions.hardwareDecode
    public var asynchronousDecompression = KSOptions.asynchronousDecompression
    public var videoDisable = false
    public var canStartPictureInPictureAutomaticallyFromInline = KSOptions.canStartPictureInPictureAutomaticallyFromInline
    public var automaticWindowResize = true
    @Published
    public var videoInterlacingType: VideoInterlacingType?
    private var videoClockDelayCount = 0

    public internal(set) var formatName = ""
    public internal(set) var prepareTime = 0.0
    public internal(set) var dnsStartTime = 0.0
    public internal(set) var tcpStartTime = 0.0
    public internal(set) var tcpConnectedTime = 0.0
    public internal(set) var openTime = 0.0
    public internal(set) var findTime = 0.0
    public internal(set) var readyTime = 0.0
    public internal(set) var readAudioTime = 0.0
    public internal(set) var readVideoTime = 0.0
    public internal(set) var decodeAudioTime = 0.0
    public internal(set) var decodeVideoTime = 0.0
    public init() {
        formatContextOptions["user_agent"] = userAgent

        formatContextOptions["scan_all_pmts"] = 1

        formatContextOptions["reconnect"] = 1
        formatContextOptions["reconnect_streamed"] = 1

        decoderOptions["threads"] = "auto"
        decoderOptions["refcounted_frames"] = "1"
    }

    
    public func appendHeader(_ header: [String: String]) {
        var oldValue = avOptions["AVURLAssetHTTPHeaderFieldsKey"] as? [String: String] ?? [
            String: String
        ]()
        oldValue.merge(header) { _, new in new }
        avOptions["AVURLAssetHTTPHeaderFieldsKey"] = oldValue
        var str = formatContextOptions["headers"] as? String ?? ""
        for (key, value) in header {
            str.append("\(key):\(value)\r\n")
        }
        formatContextOptions["headers"] = str
    }

    public func setCookie(_ cookies: [HTTPCookie]) {
        avOptions[AVURLAssetHTTPCookiesKey] = cookies
        let cookieStr = cookies.map { cookie in "\(cookie.name)=\(cookie.value)" }.joined(separator: "; ")
        appendHeader(["Cookie": cookieStr])
    }


    open func playable(capacitys: [CapacityProtocol], isFirst: Bool, isSeek: Bool) -> LoadingState {
        let packetCount = capacitys.map(\.packetCount).min() ?? 0
        let frameCount = capacitys.map(\.frameCount).min() ?? 0
        let isEndOfFile = capacitys.allSatisfy(\.isEndOfFile)
        let loadedTime = capacitys.map(\.loadedTime).min() ?? 0

        let fps = capacitys.first(where: { $0.mediaType == .video })?.fps ?? capacitys.first?.fps ?? 24
        let frameMaxCount = capacitys.map(\.frameMaxCount).min() ?? 0
        let progress = preferredForwardBufferDuration == 0 ? 100 : loadedTime * 100.0 / preferredForwardBufferDuration
        let isPlayable = capacitys.allSatisfy { capacity in
            if capacity.isEndOfFile && capacity.packetCount == 0 {
                return true
            }
            guard capacity.frameCount >= 2 else {
                return false
            }
            if capacity.isEndOfFile {
                return true
            }
            if (syncDecodeVideo && capacity.mediaType == .video) || (syncDecodeAudio && capacity.mediaType == .audio) {
                return true
            }
            if isFirst || isSeek {

                if capacity.mediaType == .audio || isSecondOpen {
                    if isFirst {
                        return true
                    } else {
                        return capacity.loadedTime >= self.preferredForwardBufferDuration / 2
                    }
                }
            }
            return capacity.loadedTime >= self.preferredForwardBufferDuration
        }
        return LoadingState(loadedTime: loadedTime, progress: progress, packetCount: packetCount,
                            frameCount: frameCount, frameMaxCount: frameMaxCount, isEndOfFile: isEndOfFile, isPlayable: isPlayable,
                            isFirst: isFirst, isSeek: isSeek, fps: fps)
    }

    open func adaptable(state: VideoAdaptationState?) -> (Int64, Int64)? {
        guard let state, let last = state.bitRateStates.last, CACurrentMediaTime() - last.time > maxBufferDuration / 2, let index = state.bitRates.firstIndex(of: last.bitRate) else {
            return nil
        }
        let isUp = state.loadedCount > Int(Double(state.fps) * maxBufferDuration / 2)
        if isUp != state.isPlayable {
            return nil
        }
        if isUp {
            if index < state.bitRates.endIndex - 1 {
                return (last.bitRate, state.bitRates[index + 1])
            }
        } else {
            if index > state.bitRates.startIndex {
                return (last.bitRate, state.bitRates[index - 1])
            }
        }
        return nil
    }


    open func wantedVideo(tracks _: [MediaPlayerTrack]) -> Int? {
        nil
    }


    open func wantedAudio(tracks _: [MediaPlayerTrack]) -> Int? {
        nil
    }

    open func videoFrameMaxCount(fps: Float, naturalSize: CGSize, isLive: Bool) -> UInt8 {
        if isLive { return 4 }

        let frameBytes = Double(naturalSize.width) * Double(naturalSize.height) * 2
        let maxFrames = frameBytes > 0 ? 1_000_000_000 / frameBytes : 240

        return UInt8(min(max(Double(fps) * 2.0, 4), maxFrames, 240))
    }

    open func audioFrameMaxCount(fps: Float, channelCount: Int) -> UInt8 {
        let count = (Int(fps) * channelCount) >> 2
        if count >= UInt8.max {
            return UInt8.max
        } else {
            return UInt8(count)
        }
    }


    open func customizeDar(sar _: CGSize, par _: CGSize) -> CGSize? {
        nil
    }


    open func isUseDisplayLayer() -> Bool {
        display == .plane
    }

    open func urlIO(log: String) {
        if log.starts(with: "Original list of addresses"), dnsStartTime == 0 {
            dnsStartTime = CACurrentMediaTime()
        } else if log.starts(with: "Starting connection attempt to"), tcpStartTime == 0 {
            tcpStartTime = CACurrentMediaTime()
        } else if log.starts(with: "Successfully connected to"), tcpConnectedTime == 0 {
            tcpConnectedTime = CACurrentMediaTime()
        }
    }

    private var idetTypeMap = [VideoInterlacingType: UInt]()
    open func filter(log: String) {
        if log.starts(with: "Repeated Field:"), autoDeInterlace {
            for str in log.split(separator: ",") {
                let map = str.split(separator: ":")
                if map.count >= 2 {
                    if String(map[0].trimmingCharacters(in: .whitespaces)) == "Multi frame" {
                        if let type = VideoInterlacingType(rawValue: map[1].trimmingCharacters(in: .whitespacesAndNewlines)) {
                            idetTypeMap[type] = (idetTypeMap[type] ?? 0) + 1
                            let tff = idetTypeMap[.tff] ?? 0
                            let bff = idetTypeMap[.bff] ?? 0
                            let progressive = idetTypeMap[.progressive] ?? 0
                            let undetermined = idetTypeMap[.undetermined] ?? 0
                            if progressive - tff - bff > 100 {
                                videoInterlacingType = .progressive
                                autoDeInterlace = false
                            } else if bff - progressive > 100 {
                                videoInterlacingType = .bff
                                autoDeInterlace = false
                            } else if tff - progressive > 100 {
                                videoInterlacingType = .tff
                                autoDeInterlace = false
                            } else if undetermined - progressive - tff - bff > 100 {
                                videoInterlacingType = .undetermined
                                autoDeInterlace = false
                            }
                        }
                    }
                }
            }
        }
    }

    open func sei(string: String) {
        KSLog("sei \(string)")
    }

    
    open func process(assetTrack: some MediaPlayerTrack) {
        if assetTrack.mediaType == .video {
            if [FFmpegFieldOrder.bb, .bt, .tt, .tb].contains(assetTrack.fieldOrder) {

                hardwareDecode = false
                asynchronousDecompression = false
                let yadif = hardwareDecode ? "yadif_videotoolbox" : "yadif"
                var yadifMode = KSOptions.yadifMode

                if KSOptions.deInterlaceAddIdet {
                    videoFilters.append("idet")
                }
                videoFilters.append("\(yadif)=mode=\(yadifMode):parity=-1:deint=1")
                if yadifMode == 1 || yadifMode == 3 {
                    assetTrack.nominalFrameRate = assetTrack.nominalFrameRate * 2
                }
            }
        }
    }

    @MainActor
    open func updateVideo(refreshRate: Float, isDovi: Bool, formatDescription: CMFormatDescription?) {
        #if os(tvOS) || os(xrOS)
        
        guard let displayManager = UIApplication.shared.windows.first?.avDisplayManager,
              displayManager.isDisplayCriteriaMatchingEnabled
        else {
            return
        }
        if var dynamicRange = formatDescription?.dynamicRange {
            if dynamicRange == .dolbyVision {
                dynamicRange = .hdr10
            }
            displayManager.preferredDisplayCriteria = AVDisplayCriteria(refreshRate: refreshRate, videoDynamicRange: dynamicRange.rawValue)
        }
        #endif
    }

    open func videoClockSync(main: KSClock, nextVideoTime: TimeInterval, fps: Double, frameCount: Int) -> (Double, ClockProcessType) {
        let desire = main.getTime() - videoDelay
        let diff = nextVideoTime - desire

        if diff >= 1 / fps / 2 {
            videoClockDelayCount = 0
            return (diff, .remain)
        } else {
            if diff < -4 / fps {
                videoClockDelayCount += 1
                let log = "[video] video delay=\(diff), clock=\(desire), delay count=\(videoClockDelayCount), frameCount=\(frameCount)"
                if frameCount == 1 {
                    if diff < -1, videoClockDelayCount % 10 == 0 {
                        KSLog("\(log) drop gop Packet")
                        return (diff, .dropGOPPacket)
                    } else if videoClockDelayCount % 5 == 0 {
                        KSLog("\(log) drop next frame")
                        return (diff, .dropNextFrame)
                    } else {
                        return (diff, .next)
                    }
                } else {
                    if diff < -8, videoClockDelayCount % 100 == 0 {
                        KSLog("\(log) seek video track")
                        return (diff, .seek)
                    }
                    if diff < -1, videoClockDelayCount % 10 == 0 {
                        KSLog("\(log) flush video track")
                        return (diff, .flush)
                    }
                    if videoClockDelayCount % 2 == 0 {
                        KSLog("\(log) drop next frame")
                        return (diff, .dropNextFrame)
                    } else {
                        return (diff, .next)
                    }
                }
            } else {
                videoClockDelayCount = 0
                return (diff, .next)
            }
        }
    }

    open func availableDynamicRange(_ contentRange: DynamicRange?) -> DynamicRange? {
        #if canImport(UIKit)
        let availableHDRModes = AVPlayer.availableHDRModes
        if let preferedDynamicRange = destinationDynamicRange {

            if availableHDRModes == AVPlayer.HDRMode(rawValue: 0) {
                return .sdr
            } else if availableHDRModes.contains(preferedDynamicRange.hdrMode) {
                return preferedDynamicRange
            } else if let contentRange,
                      availableHDRModes.contains(contentRange.hdrMode)
            {
                return contentRange
            } else if preferedDynamicRange != .sdr {
                return availableHDRModes.dynamicRange
            }
        }
        return contentRange
        #else
        return destinationDynamicRange ?? contentRange
        #endif
    }

    open func playerLayerDeinit() {
        #if os(tvOS) || os(xrOS)
        runOnMainThread {
            UIApplication.shared.windows.first?.avDisplayManager.preferredDisplayCriteria = nil
        }
        #endif
    }

    open func liveAdaptivePlaybackRate(loadingState _: LoadingState) -> Float? {
        nil

    }

    open func process(url _: URL) -> AbstractAVIOContext? {
        nil
    }
}

public enum VideoInterlacingType: String {
    case tff
    case bff
    case progressive
    case undetermined
}

public extension KSOptions {
    static var firstPlayerType: MediaPlayerProtocol.Type = KSAVPlayer.self
    static var secondPlayerType: MediaPlayerProtocol.Type? = KSMEPlayer.self

    static var preferredForwardBufferDuration = 3.0

    static var maxBufferDuration = 30.0

    static var isSecondOpen = false

    static var isAccurateSeek = false

    static var isLoopPlay = false

    static var isAutoPlay = true

    static var isSeekedAutoPlay = true
    static var hardwareDecode = true

    static var asynchronousDecompression = false
    static var isPipPopViewController = false
    static var canStartPictureInPictureAutomaticallyFromInline = true
    static var preferredFrame = true
    static var useSystemHTTPProxy = true

    /// Whether the linked FFmpeg build registers the `cache` URL protocol
    /// (libavformat cache.c). Determined at runtime because it depends on the
    /// binary's build configuration, which can't be inspected statically.
    public static let isCacheProtocolAvailable: Bool = avio_find_protocol_name("cache:test") != nil

    /// Optional AVAudioSession preferred I/O buffer duration (seconds). Set it
    /// (e.g. 0.01–0.02) for low-latency audio; nil leaves the session default.
    public static var preferredIOBufferDuration: TimeInterval? = nil

    static var logLevel = LogLevel.warning
    static var logger: LogHandler = OSLog(lable: "KSPlayer")
    internal static func deviceCpuCount() -> Int {
        var ncpu = UInt(0)
        var len: size_t = MemoryLayout.size(ofValue: ncpu)
        sysctlbyname("hw.ncpu", &ncpu, &len, nil, 0)
        return Int(ncpu)
    }

    static func setAudioSession() {
        #if os(macOS)

        #else
        var category = AVAudioSession.sharedInstance().category
        if category != .playAndRecord {
            category = .playback
        }
        #if os(tvOS)
        try? AVAudioSession.sharedInstance().setCategory(category, mode: .moviePlayback, policy: .longFormAudio)
        #else
        try? AVAudioSession.sharedInstance().setCategory(category, mode: .moviePlayback, policy: .longFormVideo)
        #endif
        try? AVAudioSession.sharedInstance().setActive(true)
        if let duration = KSOptions.preferredIOBufferDuration {
            try? AVAudioSession.sharedInstance().setPreferredIOBufferDuration(duration)
        }
        #endif
    }

    #if !os(macOS)
    static func isSpatialAudioEnabled(channelCount _: AVAudioChannelCount) -> Bool {
        if #available(tvOS 15.0, iOS 15.0, *) {
            let isSpatialAudioEnabled = AVAudioSession.sharedInstance().currentRoute.outputs.contains { $0.isSpatialAudioEnabled }
            try? AVAudioSession.sharedInstance().setSupportsMultichannelContent(isSpatialAudioEnabled)
            return isSpatialAudioEnabled
        } else {
            return false
        }
    }

    static func outputNumberOfChannels(channelCount: AVAudioChannelCount) -> AVAudioChannelCount {
        let maximumOutputNumberOfChannels = AVAudioChannelCount(AVAudioSession.sharedInstance().maximumOutputNumberOfChannels)
        let preferredOutputNumberOfChannels = AVAudioChannelCount(AVAudioSession.sharedInstance().preferredOutputNumberOfChannels)
        let isSpatialAudioEnabled = isSpatialAudioEnabled(channelCount: channelCount)
        let isUseAudioRenderer = KSOptions.audioPlayerType == AudioRendererPlayer.self
        KSLog("[audio] maximumOutputNumberOfChannels: \(maximumOutputNumberOfChannels), preferredOutputNumberOfChannels: \(preferredOutputNumberOfChannels), isSpatialAudioEnabled: \(isSpatialAudioEnabled), isUseAudioRenderer: \(isUseAudioRenderer) ")
        let maxRouteChannelsCount = AVAudioSession.sharedInstance().currentRoute.outputs.compactMap {
            $0.channels?.count
        }.max() ?? 2
        KSLog("[audio] currentRoute max channels: \(maxRouteChannelsCount)")
        var channelCount = channelCount
        if channelCount > 2 {
            let minChannels = min(maximumOutputNumberOfChannels, channelCount)
            #if os(tvOS) || targetEnvironment(simulator)
            if !(isUseAudioRenderer && isSpatialAudioEnabled) {

                channelCount = minChannels
            }
            #else

            if !isSpatialAudioEnabled {
                channelCount = minChannels
            }
            #endif
        } else {
            channelCount = 2
        }

        KSLog("[audio] outputNumberOfChannels: \(AVAudioSession.sharedInstance().outputNumberOfChannels) output channelCount: \(channelCount)")
        return channelCount
    }
    #endif
}

public enum LogLevel: Int32, CustomStringConvertible {
    case panic = 0
    case fatal = 8
    case error = 16
    case warning = 24
    case info = 32
    case verbose = 40
    case debug = 48
    case trace = 56

    public var description: String {
        switch self {
        case .panic:
            return "panic"
        case .fatal:
            return "fault"
        case .error:
            return "error"
        case .warning:
            return "warning"
        case .info:
            return "info"
        case .verbose:
            return "verbose"
        case .debug:
            return "debug"
        case .trace:
            return "trace"
        }
    }
}

public extension LogLevel {
    var logType: OSLogType {
        switch self {
        case .panic, .fatal:
            return .fault
        case .error:
            return .error
        case .warning:
            return .debug
        case .info, .verbose, .debug:
            return .info
        case .trace:
            return .default
        }
    }
}

public protocol LogHandler {
    @inlinable
    func log(level: LogLevel, message: CustomStringConvertible, file: String, function: String, line: UInt)
}

public class OSLog: LogHandler {
    public let label: String
    public init(lable: String) {
        label = lable
    }

    @inlinable
    public func log(level: LogLevel, message: CustomStringConvertible, file: String, function: String, line: UInt) {
        os_log(level.logType, "%@ %@: %@:%d %@ | %@", level.description, label, file, line, function, message.description)
    }
}

public class FileLog: LogHandler {
    public let fileHandle: FileHandle
    public let formatter = DateFormatter()
    public init(fileHandle: FileHandle) {
        self.fileHandle = fileHandle
        formatter.dateFormat = "MM-dd HH:mm:ss.SSSSSS"
    }

    @inlinable
    public func log(level: LogLevel, message: CustomStringConvertible, file: String, function: String, line: UInt) {
        let string = String(format: "%@ %@ %@:%d %@ | %@\n", formatter.string(from: Date()), level.description, file, line, function, message.description)
        if let data = string.data(using: .utf8) {
            fileHandle.write(data)
        }
    }
}

@inlinable
public func KSLog(_ error: @autoclosure () -> Error, file: String = #file, function: String = #function, line: UInt = #line) {
    KSLog(level: .error, error().localizedDescription, file: file, function: function, line: line)
}

@inlinable
public func KSLog(level: LogLevel = .warning, _ message: @autoclosure () -> CustomStringConvertible, file: String = #file, function: String = #function, line: UInt = #line) {
    if level.rawValue <= KSOptions.logLevel.rawValue {
        let fileName = (file as NSString).lastPathComponent
        KSOptions.logger.log(level: level, message: message(), file: fileName, function: function, line: line)
    }
}

@inlinable
public func KSLog(level: LogLevel = .warning, dso: UnsafeRawPointer = #dsohandle, _ message: StaticString, _ args: CVarArg...) {
    if level.rawValue <= KSOptions.logLevel.rawValue {
        os_log(level.logType, dso: dso, message, args)
    }
}

public extension Array {
    func toDictionary<Key: Hashable>(with selectKey: (Element) -> Key) -> [Key: Element] {
        var dict = [Key: Element]()
        forEach { element in
            dict[selectKey(element)] = element
        }
        return dict
    }
}

public struct KSClock {
    private let lock = NSLock()
    private var lastMediaTimeValue = CACurrentMediaTime()
    private var positionValue = Int64(0)
    private var timeValue = CMTime.zero

    public private(set) var lastMediaTime: TimeInterval {
        get { locked { lastMediaTimeValue } }
        set { locked { lastMediaTimeValue = newValue } }
    }

    public internal(set) var position: Int64 {
        get { locked { positionValue } }
        set { locked { positionValue = newValue } }
    }

    public internal(set) var time: CMTime {
        get { locked { timeValue } }
        set {
            locked {
                timeValue = newValue
                lastMediaTimeValue = CACurrentMediaTime()
            }
        }
    }

    func getTime() -> TimeInterval {
        locked { timeValue.seconds + CACurrentMediaTime() - lastMediaTimeValue }
    }

    /// Consistent point-in-time copy, safe to read on any thread. The audio
    /// clock is written from the audio render thread while video sync reads it
    /// from the read/render threads; reading the fields individually could
    /// otherwise observe a torn update.
    public func snapshot() -> KSClock {
        var copy = KSClock()
        locked {
            copy.lastMediaTimeValue = lastMediaTimeValue
            copy.positionValue = positionValue
            copy.timeValue = timeValue
        }
        return copy
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
