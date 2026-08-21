//
//  RemoteLog.swift
//  KSPlayer
//
//  Remote HTTP/JSON log transport + crash monitoring.
//
//  Every existing KSLog() call flows through KSOptions.logger, which this
//  library defaults to an HTTPLogHandler (OSLog console + remote upload).
//  Entries are batched and POSTed to RemoteLog.endpoint (/log) as JSON for
//  downstream model-based analysis. A fixed ring buffer of the last N entries
//  is dumped on crash (signal / NSException) to a file in Caches and uploaded
//  on next launch, so a 闪退 leaves a recoverable trace even when the network
//  upload died with the process.
//

import Darwin
import Foundation
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Public configuration

public enum RemoteLog {
    /// Base URL of the log server (e.g. http://192.168.10.15:7777).
    public static var endpoint = URL(string: "http://192.168.10.15:7777")!
    /// Path (relative to endpoint) that receives batched log POSTs.
    public static var logPath = "/log"
    /// Path (relative to endpoint) that receives crash beacons.
    public static var crashPath = "/crash"
    /// Master switch. Disabling clears the pending buffer.
    public static private(set) var enabled = true
    /// Upload cadence while the buffer is non-empty.
    public static var flushInterval: TimeInterval = 2
    /// Batch size that triggers an upload.
    public static var batchSize = 50
    /// Hard cap on buffered entries (oldest dropped beyond this).
    public static var maxBufferedEntries = 5000

    /// Default logger wired into KSOptions: OSLog console + remote upload.
    public static let handler: LogHandler = HTTPLogHandler()

    /// Adjust remote logging. Every parameter is optional; nil keeps the
    /// current value. Also forces early installation of the crash handlers.
    public static func configure(endpoint: URL? = nil, logPath: String? = nil, crashPath: String? = nil, level: LogLevel? = nil, enabled: Bool? = nil) {
        if let endpoint {
            self.endpoint = endpoint
        }
        if let logPath {
            self.logPath = logPath
        }
        if let crashPath {
            self.crashPath = crashPath
        }
        if let level {
            KSOptions.logLevel = level
        }
        if let enabled {
            self.enabled = enabled
            if !enabled {
                engine.reset()
            }
        }
        _ = engine // install crash handlers / lifecycle observers now
    }

    /// Internal engine singleton. Referenced from the @usableFromInline bridge
    /// below, so it stays `internal` (its body is never inlined into clients).
    static let engine = RemoteLogEngine()
}

/// Bridge that lets the @inlinable LogHandler witness reach the internal
/// engine without forcing every engine member to be @usableFromInline.
@usableFromInline
func remoteLogEnqueue(level: LogLevel, message: String, file: String, function: String, line: UInt) {
    RemoteLog.engine.log(level: level, message: message, file: file, function: function, line: line)
}

// MARK: - LogHandler (OSLog + remote)

/// LogHandler that preserves the existing OSLog console output and additionally
/// ships every entry to the remote server.
public class HTTPLogHandler: LogHandler {
    // @usableFromInline (not private) so the @inlinable `log` witness can
    // reference it; private members are not visible to inlined bodies.
    @usableFromInline
    let consoleLog: OSLog

    public init() {
        consoleLog = OSLog(lable: "KSPlayer")
    }

    @inlinable
    public func log(level: LogLevel, message: CustomStringConvertible, file: String, function: String, line: UInt) {
        consoleLog.log(level: level, message: message, file: file, function: function, line: line)
        remoteLogEnqueue(level: level, message: message.description, file: file, function: function, line: line)
    }
}

// MARK: - Wire models

private struct LogEntry: Codable {
    var t: Double
    var seq: UInt64
    var level: String
    var file: String
    var line: UInt
    var thread: String
    var msg: String
    var mem: Int64?
    var disk: Int64?
    var function: String

    enum CodingKeys: String, CodingKey {
        case t, seq, level, file, line, thread, msg, mem, disk
        case function = "func"
    }

    var ringLine: String {
        "\(level) \(file):\(line) \(function) | \(msg)"
    }
}

private struct BatchBody: Codable {
    let type = "batch"
    let app: String
    let bundle: String
    let ver: String
    let dev: String
    let os: String
    let session: String
    let boot: Double
    let entries: [LogEntry]
}

private struct CrashBody: Codable {
    let type = "crash"
    let app: String
    let bundle: String
    let ver: String
    let dev: String
    let os: String
    let session: String
    let t: Double
    let reason: String
    let signal: Int32
    let thread: String
    let backtrace: [String]
    let lastLogs: [String]
}

// MARK: - Device / app info

private struct AppInfo {
    let appName: String
    let bundleID: String
    let version: String
    let build: String
    let deviceModel: String
    let osVersion: String

    init() {
        let bundle = Bundle.main
        appName = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "unknown"
        bundleID = bundle.bundleIdentifier ?? "unknown"
        version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        deviceModel = Self.hwMachine() ?? "unknown"
        #if canImport(UIKit)
        osVersion = "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)"
        #else
        osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        #endif
    }

    private static func hwMachine() -> String? {
        var size = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        guard size > 0 else { return nil }
        var machine = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.machine", &machine, &size, nil, 0)
        return String(cString: machine)
    }
}

// MARK: - Crash ring buffer
//
// Pre-allocated fixed storage so the crash dump can run async-signal-safe:
// `dump(to:)` performs no allocation and takes no lock (the writer may be
// mid-append; a torn line is acceptable for diagnostics).

private final class CrashRingBuffer {
    static let lineCapacity = 512
    static let lineCount = 150

    private let storage: UnsafeMutableRawPointer
    private let lengths: UnsafeMutablePointer<UInt16>
    private let head: UnsafeMutablePointer<Int32>
    private let count: UnsafeMutablePointer<Int32>
    private var lock = os_unfair_lock_s()

    init() {
        storage = calloc(CrashRingBuffer.lineCount, CrashRingBuffer.lineCapacity)!
        lengths = .allocate(capacity: CrashRingBuffer.lineCount)
        lengths.initialize(repeating: 0, count: CrashRingBuffer.lineCount)
        head = .allocate(capacity: 1)
        head.initialize(to: 0)
        count = .allocate(capacity: 1)
        count.initialize(to: 0)
    }

    deinit {
        free(storage)
        lengths.deallocate()
        head.deallocate()
        count.deallocate()
    }

    func append(_ text: String) {
        var bytes = Array(text.utf8)
        let maxLen = CrashRingBuffer.lineCapacity - 1
        if bytes.count > maxLen {
            bytes = Array(bytes[(bytes.count - maxLen)...])
        }
        os_unfair_lock_lock(&lock)
        let idx = Int(head.pointee % Int32(CrashRingBuffer.lineCount))
        bytes.withUnsafeBytes { raw in
            memcpy(storage.advanced(by: idx * CrashRingBuffer.lineCapacity), raw.baseAddress, raw.count)
        }
        lengths[idx] = UInt16(bytes.count)
        head.pointee += 1
        if count.pointee < Int32(CrashRingBuffer.lineCount) {
            count.pointee += 1
        }
        os_unfair_lock_unlock(&lock)
    }

    /// Safe on any thread (allocates); used by the NSException path.
    func readLines() -> [String] {
        var out: [String] = []
        let n = Int(count.pointee)
        let start = (Int(head.pointee) - n + CrashRingBuffer.lineCount) % CrashRingBuffer.lineCount
        for k in 0 ..< n {
            let idx = (start + k) % CrashRingBuffer.lineCount
            let len = Int(lengths[idx])
            guard len > 0 else { continue }
            let ptr = storage.advanced(by: idx * CrashRingBuffer.lineCapacity).assumingMemoryBound(to: UInt8.self)
            out.append(String(bytes: UnsafeBufferPointer(start: ptr, count: len), encoding: .utf8) ?? "")
        }
        return out
    }

    /// Async-signal-safe: no allocation, no locking.
    func dump(to fd: Int32) {
        let n = Int(count.pointee)
        let start = (Int(head.pointee) - n + CrashRingBuffer.lineCount) % CrashRingBuffer.lineCount
        for k in 0 ..< n {
            let idx = (start + k) % CrashRingBuffer.lineCount
            let len = Int(lengths[idx])
            guard len > 0 else { continue }
            write(fd, storage.advanced(by: idx * CrashRingBuffer.lineCapacity), len)
            write(fd, "\n", 1)
        }
    }
}

// MARK: - Engine

final class RemoteLogEngine {
    private let queue = DispatchQueue(label: "ks.remotelog.queue")
    private let lock = NSLock()
    private var pending: [LogEntry] = []
    private var seq: UInt64 = 0
    private var sampler = 0
    private var memSample: Int64 = 0
    private var diskSample: Int64 = 0

    private let appInfo = AppInfo()
    private let sessionID = UUID().uuidString
    private let bootTime = Date().timeIntervalSince1970 - ProcessInfo.processInfo.systemUptime

    private lazy var session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 5
        cfg.timeoutIntervalForResource = 15
        cfg.waitsForConnectivity = false
        return URLSession(configuration: cfg)
    }()

    private let ring = CrashRingBuffer()
    private let crashHeaderBuf: UnsafeMutableRawPointer? = calloc(512, 1)
    private var crashFd: Int32 = -1
    private var crashDirPath: String?
    private var timer: DispatchSourceTimer?
    private var observers: [NSObjectProtocol] = []

    init() {
        install()
        startTimer()
        log(level: .info, message: "[remoteLog] session \(sessionID) server \(RemoteLog.endpoint)", file: "RemoteLog.swift", function: "init()", line: 0)
    }

    // MARK: Enqueue

    func log(level: LogLevel, message: String, file: String, function: String, line: UInt) {
        guard RemoteLog.enabled else { return }
        let entry = makeEntry(level: level, message: message, file: file, function: function, line: line)
        lock.lock()
        pending.append(entry)
        if pending.count > RemoteLog.maxBufferedEntries {
            pending.removeFirst(pending.count - RemoteLog.maxBufferedEntries)
        }
        let overBatch = pending.count >= RemoteLog.batchSize
        lock.unlock()
        ring.append(entry.ringLine)
        if overBatch {
            queue.async { [weak self] in
                self?.flush()
            }
        }
    }

    func reset() {
        lock.lock()
        pending.removeAll()
        lock.unlock()
    }

    private func makeEntry(level: LogLevel, message: String, file: String, function: String, line: UInt) -> LogEntry {
        sampler += 1
        if sampler % 10 == 0 {
            memSample = Self.processMemoryBytes()
            diskSample = Self.freeDiskBytes()
        }
        lock.lock()
        seq += 1
        let s = seq
        lock.unlock()
        return LogEntry(
            t: Date().timeIntervalSince1970,
            seq: s,
            level: level.description,
            file: (file as NSString).lastPathComponent,
            line: line,
            thread: Self.threadName(),
            msg: message,
            mem: memSample > 0 ? memSample : nil,
            disk: diskSample > 0 ? diskSample : nil,
            function: function
        )
    }

    private static func threadName() -> String {
        if Thread.isMainThread { return "main" }
        if let name = Thread.current.name, !name.isEmpty { return name }
        var buf = [CChar](repeating: 0, count: 64)
        pthread_getname_np(pthread_self(), &buf, buf.count)
        let name = String(cString: buf)
        return name.isEmpty ? "tid:\(pthread_mach_thread_np(pthread_self()))" : name
    }

    // MARK: Upload

    private func startTimer() {
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + RemoteLog.flushInterval, repeating: RemoteLog.flushInterval)
        t.setEventHandler { [weak self] in
            self?.flush()
        }
        t.resume()
        timer = t
    }

    private func flush() {
        let batch = takePending()
        guard !batch.isEmpty else { return }
        upload(batch)
    }

    private func takePending() -> [LogEntry] {
        lock.lock()
        let batch = pending
        pending.removeAll(keepingCapacity: true)
        lock.unlock()
        return batch
    }

    private func upload(_ entries: [LogEntry]) {
        guard RemoteLog.enabled else { return }
        guard let data = encodeBatch(entries) else { return }
        var request = URLRequest(url: URL(string: RemoteLog.logPath, relativeTo: RemoteLog.endpoint)!, timeoutInterval: 5)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        session.dataTask(with: request) { [weak self] _, response, error in
            guard let self else { return }
            let ok = error == nil && (response as? HTTPURLResponse).map { (200 ..< 300).contains($0.statusCode) } == true
            if !ok {
                self.queue.async { self.reQueue(entries) }
            }
        }.resume()
    }

    private func uploadSync(_ entries: [LogEntry]) {
        guard RemoteLog.enabled else { return }
        guard let data = encodeBatch(entries) else { return }
        var request = URLRequest(url: URL(string: RemoteLog.logPath, relativeTo: RemoteLog.endpoint)!, timeoutInterval: 2)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        let sem = DispatchSemaphore(value: 0)
        session.dataTask(with: request) { _, _, _ in sem.signal() }.resume()
        _ = sem.wait(timeout: .now() + 2)
    }

    private func reQueue(_ entries: [LogEntry]) {
        lock.lock()
        pending.insert(contentsOf: entries, at: 0)
        if pending.count > RemoteLog.maxBufferedEntries {
            pending.removeLast(pending.count - RemoteLog.maxBufferedEntries)
        }
        lock.unlock()
    }

    private func encodeBatch(_ entries: [LogEntry]) -> Data? {
        let body = BatchBody(
            app: appInfo.appName, bundle: appInfo.bundleID, ver: appInfo.version,
            dev: appInfo.deviceModel, os: appInfo.osVersion,
            session: sessionID, boot: bootTime, entries: entries
        )
        return try? JSONEncoder().encode(body)
    }

    // MARK: Crash handling

    private func install() {
        installExceptionHandler()
        installSignalHandlers()
        setupCrashFile()
        observeLifecycle()
        uploadPendingCrashFiles()
    }

    private func installExceptionHandler() {
        NSSetUncaughtExceptionHandler { exception in
            let reason = "NSException \(exception.name.rawValue): \(exception.reason ?? "nil")"
            RemoteLog.engine.handleException(reason: reason, backtrace: exception.callStackSymbols)
        }
    }

    private func installSignalHandlers() {
        var action = sigaction()
        // `sa_sigaction` is only exposed on macOS; iOS/tvOS/xrOS expose the
        // underlying `__sigaction_u.__sa_sigaction` union member instead.
        #if os(macOS)
        action.sa_sigaction = { sig, info, _ in
            RemoteLog.engine.handleSignal(sig, info)
        }
        #else
        action.__sigaction_u.__sa_sigaction = { sig, info, _ in
            RemoteLog.engine.handleSignal(sig, info)
        }
        #endif
        action.sa_flags = SA_SIGINFO | SA_RESETHAND
        sigemptyset(&action.sa_mask)
        for sig in [SIGABRT, SIGSEGV, SIGBUS, SIGILL, SIGFPE, SIGTRAP, SIGSYS] {
            sigaction(sig, &action, nil)
        }
    }

    private func setupCrashFile() {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return }
        let dir = caches.appendingPathComponent("KSRemoteLog", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        crashDirPath = dir.path
        let path = dir.appendingPathComponent("crash.log").path
        crashFd = open(path, O_WRONLY | O_CREAT | O_APPEND, 0o644)
    }

    private func observeLifecycle() {
        #if canImport(UIKit)
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main) { [weak self] _ in
            KSLog(level: .error, "[remoteLog] didReceiveMemoryWarning")
            self?.flush()
        })
        observers.append(nc.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            KSLog(level: .info, "[remoteLog] didEnterBackground, flushing")
            self?.uploadSync(self?.takePending() ?? [])
        })
        observers.append(nc.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
            KSLog(level: .info, "[remoteLog] willEnterForeground")
            self?.uploadPendingCrashFiles()
        })
        #endif
    }

    /// NSException path: runtime is still functional, so we can allocate,
    /// gather a backtrace, write the dump file and attempt a live beacon.
    func handleException(reason: String, backtrace: [String]) {
        let thread = Self.threadName()
        writeCrashFile(reason: reason, signal: 0, thread: thread, backtrace: backtrace)
        sendCrash(reason: reason, signal: 0, thread: thread, backtrace: backtrace, lastLogs: ring.readLines(), sync: true)
    }

    /// Signal path: only async-signal-safe operations. Writes the ring buffer
    /// to the pre-opened fd, then re-raises with the default disposition so the
    /// system produces the canonical crash report.
    func handleSignal(_ sig: Int32, _ info: UnsafeMutablePointer<siginfo_t>?) {
        guard crashFd >= 0, let crashHeaderBuf else {
            signal(sig, SIG_DFL)
            raise(sig)
            return
        }
        let addr = info.map { UInt64(UInt(bitPattern: $0.pointee.si_addr)) } ?? 0
        let header = crashHeaderBuf.assumingMemoryBound(to: CChar.self)
        _ = snprintf(header, 512, "\n=== KSPlayer CRASH === %s (%d) at 0x%llx\n", Self.signalName(sig).utf8Start, sig, addr)
        write(crashFd, header, Int(strlen(header)))
        write(crashFd, "--- recent logs ---\n", 21)
        ring.dump(to: crashFd)
        write(crashFd, "--- end ---\n", 12)
        signal(sig, SIG_DFL)
        raise(sig)
    }

    private func writeCrashFile(reason: String, signal: Int32, thread: String, backtrace: [String]?) {
        guard crashFd >= 0 else { return }
        var lines: [String] = [
            "=== KSPlayer CRASH ===",
            "time: \(Date())",
            "reason: \(reason)",
            "thread: \(thread)",
        ]
        if let backtrace, !backtrace.isEmpty {
            lines.append("backtrace:")
            lines.append(contentsOf: backtrace.prefix(40))
        }
        lines.append("--- recent logs (last \(CrashRingBuffer.lineCount)) ---")
        lines.append(contentsOf: ring.readLines())
        lines.append("--- end ---")
        let text = lines.joined(separator: "\n") + "\n"
        guard let data = text.data(using: .utf8) else { return }
        data.withUnsafeBytes { raw in
            _ = write(crashFd, raw.baseAddress, raw.count)
        }
    }

    private func sendCrash(reason: String, signal: Int32, thread: String, backtrace: [String], lastLogs: [String], sync: Bool) {
        guard RemoteLog.enabled else { return }
        let body = CrashBody(
            app: appInfo.appName, bundle: appInfo.bundleID, ver: appInfo.version,
            dev: appInfo.deviceModel, os: appInfo.osVersion,
            session: sessionID, t: Date().timeIntervalSince1970,
            reason: reason, signal: signal, thread: thread,
            backtrace: backtrace, lastLogs: Array(lastLogs.suffix(200))
        )
        guard let data = try? JSONEncoder().encode(body),
              let url = URL(string: RemoteLog.crashPath, relativeTo: RemoteLog.endpoint) else { return }
        var request = URLRequest(url: url, timeoutInterval: 2)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        if sync {
            let sem = DispatchSemaphore(value: 0)
            session.dataTask(with: request) { _, _, _ in sem.signal() }.resume()
            _ = sem.wait(timeout: .now() + 2)
        } else {
            session.dataTask(with: request).resume()
        }
    }

    /// Upload any crash dump left by a previous run, then clear it.
    private func uploadPendingCrashFiles() {
        guard let crashDirPath else { return }
        queue.async { [weak self] in
            guard let self else { return }
            let fm = FileManager.default
            let path = (crashDirPath as NSString).appendingPathComponent("crash.log")
            guard fm.fileExists(atPath: path),
                  let content = try? String(contentsOfFile: path, encoding: .utf8),
                  !content.isEmpty
            else {
                if fm.fileExists(atPath: path) {
                    try? fm.removeItem(atPath: path)
                }
                return
            }
            var lines = content.components(separatedBy: "\n").filter { !$0.isEmpty }
            if let idx = lines.lastIndex(where: { $0.contains("KSPlayer CRASH") }) {
                lines = Array(lines[idx...])
            }
            self.sendCrash(reason: "recovered crash log", signal: 0, thread: "?", backtrace: [], lastLogs: lines, sync: true)
            try? fm.removeItem(atPath: path)
            self.log(level: .info, message: "[remoteLog] recovered previous crash (\(lines.count) lines)", file: "RemoteLog.swift", function: "uploadPendingCrashFiles", line: 0)
        }
    }

    // MARK: System sampling

    private static func processMemoryBytes() -> Int64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: 1) { reb in
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), reb, &count)
            }
        }
        return kr == KERN_SUCCESS ? Int64(info.resident_size) : -1
    }

    private static func freeDiskBytes() -> Int64 {
        guard let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return -1 }
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return Int64(values?.volumeAvailableCapacityForImportantUsage ?? -1)
    }

    private static func signalName(_ sig: Int32) -> StaticString {
        switch sig {
        case SIGABRT: return "SIGABRT"
        case SIGSEGV: return "SIGSEGV"
        case SIGBUS: return "SIGBUS"
        case SIGILL: return "SIGILL"
        case SIGFPE: return "SIGFPE"
        case SIGTRAP: return "SIGTRAP"
        case SIGSYS: return "SIGSYS"
        default: return "SIGNAL"
        }
    }
}
