//
//  Logger.swift
//  KSPlayer
//
//  Created by Architecture Team on 2026/08/28.
//  日志系统 - 结构化日�?//

import Foundation
import os.log

/// 日志级别
enum LoggerLevel: Int, CaseIterable {
    case verbose = 0
    case debug = 1
    case info = 2
    case warning = 3
    case error = 4

    var osLogType: OSLogType {
        switch self {
        case .verbose, .debug:
            return .debug
        case .info:
            return .info
        case .warning:
            return .default
        case .error:
            return .error
        }
    }

    var prefix: String {
        switch self {
        case .verbose:
            return "[V]"
        case .debug:
            return "[D]"
        case .info:
            return "[I]"
        case .warning:
            return "[W]"
        case .error:
            return "[E]"
        }
    }
}

/// 日志协议
protocol LoggerProtocol {
    func verbose(_ message: String, file: String, function: String, line: Int)
    func debug(_ message: String, file: String, function: String, line: Int)
    func info(_ message: String, file: String, function: String, line: Int)
    func warning(_ message: String, file: String, function: String, line: Int)
    func error(_ message: String, file: String, function: String, line: Int)
    func flush()
}

/// 日志实现
final class Logger: LoggerProtocol {
    private let osLog: OSLog
    private let consoleLogEnabled: Bool
    private let minLevel: LogLevel
    private var buffer: [String] = []
    private let maxBufferSize = 1000

    init(
        subsystem: String = "com.kingslay.KSPlayer",
        category: String = "Player",
        consoleLogEnabled: Bool = true,
        minLevel: LogLevel = .debug
    ) {
        self.osLog = OSLog(subsystem: subsystem, category: category)
        self.consoleLogEnabled = consoleLogEnabled
        self.minLevel = minLevel
    }

    func verbose(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(.verbose, message, file: file, function: function, line: line)
    }

    func debug(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(.debug, message, file: file, function: function, line: line)
    }

    func info(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(.info, message, file: file, function: function, line: line)
    }

    func warning(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(.warning, message, file: file, function: function, line: line)
    }

    func error(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(.error, message, file: file, function: function, line: line)
    }

    func flush() {
        // 上传日志到远程服务器
        uploadLogs()
        buffer.removeAll()
    }

    // MARK: - Private Methods

    private func log(_ level: LogLevel, _ message: String, file: String, function: String, line: Int) {
        guard level.rawValue >= minLevel.rawValue else {
            return
        }

        let fileName = (file as NSString).lastPathComponent
        let logMessage = "\(level.prefix) \(fileName):\(line) [\(function)] \(message)"

        // OS Log
        osLog("%{public}@", level: level.osLogType, logMessage)

        // Console Log
        if consoleLogEnabled {
            print(logMessage)
        }

        // Buffer for upload
        buffer.append(logMessage)
        if buffer.count > maxBufferSize {
            buffer.removeFirst(buffer.count - maxBufferSize)
        }
    }

    private func uploadLogs() {
        guard !buffer.isEmpty else { return }

        // TODO: 上传到远程日志服务器
        // RemoteLogService.upload(buffer)
    }
}

// MARK: - Convenience Extensions

extension LoggerProtocol {
    func info<T>(_ message: T, file: String = #file, function: String = #function, line: Int = #line) {
        info("\(message)", file: file, function: function, line: line)
    }

    func warning<T>(_ message: T, file: String = #file, function: String = #function, line: Int = #line) {
        warning("\(message)", file: file, function: function, line: line)
    }

    func error<T>(_ message: T, file: String = #file, function: String = #function, line: Int = #line) {
        error("\(message)", file: file, function: function, line: line)
    }
}
