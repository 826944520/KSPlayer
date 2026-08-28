//
//  NetworkMonitor.swift
//  KSPlayer
//
//  Created by Architecture Team on 2026/08/28.
//  网络监控器 - 弱网容错支持
//

import Foundation
import Network
import Combine

@MainActor
final class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()

    @Published private(set) var isConnected: Bool = true
    @Published private(set) var connectionType: ConnectionType = .wifi
    @Published private(set) var isExpensive: Bool = false
    @Published private(set) var isConstrained: Bool = false

    private let monitor: NWPathMonitor
    private let queue = DispatchQueue(label: "com.ksplayer.network")
    private var subscriptions = Set<AnyCancellable>()

    init() {
        self.monitor = NWPathMonitor()
    }

    // MARK: - Lifecycle

    func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            self?.updatePath(path)
        }
        monitor.start(queue: queue)

        // 检查初始状态
        checkInitialPath()
    }

    func stopMonitoring() {
        monitor.cancel()
        subscriptions.removeAll()
    }

    // MARK: - Private Methods

    private func updatePath(_ path: NWPath) {
        Task { @MainActor in
            isConnected = path.status == .satisfied

            switch path.status {
            case .satisfied:
                connectionType = determineConnectionType(from: path)
            case .unsatisfied:
                connectionType = .none
            case .requiresConnection:
                connectionType = .none
            @unknown default:
                connectionType = .none
            }

            isExpensive = path.isExpensive
            isConstrained = path.isConstrained

            // 弱网警告
            if isExpensive || isConstrained {
                DependencyContainer.shared.makeLogger().warning("Network constraint detected: expensive=\(isExpensive), constrained=\(isConstrained)")
            }
        }
    }

    private func checkInitialPath() {
        Task { @MainActor in
            await withCheckedContinuation { continuation in
                monitor.pathUpdateHandler = { [weak self] path in
                    self?.updatePath(path)
                    continuation.resume()
                }
                monitor.start(queue: queue)
            }
        }
    }

    private func determineConnectionType(from path: NWPath) -> ConnectionType {
        if path.usesInterfaceType(.wifi) {
            return .wifi
        } else if path.usesInterfaceType(.cellular) {
            return .cellular
        } else if path.usesInterfaceType(.wiredEthernet) {
            return .ethernet
        } else if path.usesInterfaceType(.other) {
            return .other
        } else {
            return .none
        }
    }
}

// MARK: - Connection Type

enum ConnectionType {
    case wifi
    case cellular
    case ethernet
    case other
    case none

    var isCellular: Bool {
        if case .cellular = self { return true }
        return false
    }

    var isGoodConnection: Bool {
        switch self {
        case .wifi, .ethernet:
            return true
        case .cellular, .other, .none:
            return false
        }
    }
}

// MARK: - Weak Network Detection

extension NetworkMonitor {
    /// 是否为弱网环境
    var isWeakNetwork: Bool {
        !isGoodConnection || isExpensive || isConstrained
    }

    /// 获取建议的预加载大小（字节）
    var suggestedPreloadSize: Int {
        if isWeakNetwork {
            return 5 * 1024 * 1024 // 5MB - 弱网时减少预加载
        } else {
            return 50 * 1024 * 1024 // 50MB - 良好网络时增加预加载
        }
    }

    /// 获取建议的超时时间（秒）
    var suggestedTimeout: TimeInterval {
        if isWeakNetwork {
            return 30.0 // 弱网时增加超时
        } else {
            return 10.0 // 良好网络时减少超时
        }
    }
}

// MARK: - Connectivity Checker

extension NetworkMonitor {
    /// 检查网络连接
    func checkConnectivity() async -> Bool {
        // Ping 一个可靠的地址
        let endpoint = URL(string: "https://www.apple.com/library/test/success.html")!

        do {
            let (_, response) = try await URLSession.shared.data(from: endpoint)

            if let httpResponse = response as? HTTPURLResponse {
                return httpResponse.statusCode == 200
            }
        } catch {
            DependencyContainer.shared.makeLogger().error("Network check failed: \(error.localizedDescription)")
        }

        return false
    }
}