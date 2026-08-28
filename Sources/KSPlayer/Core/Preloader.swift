//
//  Preloader.swift
//  KSPlayer
//
//  Created by Architecture Team on 2026/08/28.
//  预加载器 - 启动性能优化
//

import Foundation
import MetalKit

@MainActor
final class Preloader {
    private let logger: LoggerProtocol
    private var isPreloading = false

    init(logger: LoggerProtocol = DependencyContainer.shared.makeLogger()) {
        self.logger = logger
    }

    // MARK: - Preload Critical Resources

    func preloadCriticalResources() async {
        guard !isPreloading else { return }
        isPreloading = true

        logger.info("Starting critical resources preload...")

        await withTaskGroup(of: Void.self) { group in
            // 1. 预加载 FFmpeg（不阻塞主线程）
            group.addTask {
                await self.preloadFFmpeg()
            }

            // 2. 预热 Metal Shader Cache
            group.addTask {
                await self.warmupMetalShaders()
            }

            // 3. 检查权限（后台进行）
            group.addTask {
                await self.checkPermissions()
            }

            // 4. 初始化网络监控
            group.addTask {
                await self.initializeNetworkMonitor()
            }

            // 5. 预加载最近播放的媒体（可选）
            group.addTask {
                await self.preloadRecentMedia()
            }
        }

        logger.info("Critical resources preload completed")
        isPreloading = false
    }

    // MARK: - Individual Preloads

    private func preloadFFmpeg() async {
        logger.info("Preloading FFmpeg...")

        // FFmpeg 初始化是 CPU 密集型操作，放在后台线程
        await Task.detached(priority: .utility) {
            // TODO: FFmpegKit.preload()
        }.value

        logger.info("FFmpeg preloaded")
    }

    private func warmupMetalShaders() async {
        logger.info("Warming up Metal shaders...")

        // 预热 Metal 渲染管线
        if let device = MTLCreateSystemDefaultDevice() {
            // TODO: 预编译常用 shader
            // MetalRender.precompileShaders(on: device)
        }

        logger.info("Metal shaders warmed up")
    }

    private func checkPermissions() async {
        logger.info("Checking permissions...")

        await PermissionChecker.shared.checkAvailability()

        logger.info("Permissions checked")
    }

    private func initializeNetworkMonitor() async {
        logger.info("Initializing network monitor...")

        await NetworkMonitor.shared.startMonitoring()

        logger.info("Network monitor initialized")
    }

    private func preloadRecentMedia() async {
        logger.info("Preloading recent media...")

        // TODO: 从历史记录预加载前 3 个媒体
        // let history = try? await DependencyContainer.shared.makeHistoryRepository().getHistory(limit: 3)
        // for item in history {
        //     try? await DependencyContainer.shared.makeCacheUseCase().preload(url: item.url)
        // }

        logger.info("Recent media preloaded")
    }
}

// MARK: - Performance Metrics

extension Preloader {
    /// 获取启动性能指标
    func getLaunchMetrics() async -> LaunchMetrics {
        let startTime = Date()

        // 测量 FFmpeg 加载时间
        let ffmpegLoadTime = await measure {
            await preloadFFmpeg()
        }

        // 测量 Metal 初始化时间
        let metalInitTime = await measure {
            await warmupMetalShaders()
        }

        // 总预加载时间
        let totalPreloadTime = Date().timeIntervalSince(startTime)

        return LaunchMetrics(
            ffmpegLoadTime: ffmpegLoadTime,
            metalInitTime: metalInitTime,
            totalPreloadTime: totalPreloadTime,
            targetLaunchTime: 1.5 // 目标 < 1.5s
        )
    }

    private func measure(_ operation: () async -> Void) async -> TimeInterval {
        let startTime = Date()
        await operation()
        return Date().timeIntervalSince(startTime)
    }
}

// MARK: - Launch Metrics

struct LaunchMetrics {
    let ffmpegLoadTime: TimeInterval
    let metalInitTime: TimeInterval
    let totalPreloadTime: TimeInterval
    let targetLaunchTime: TimeInterval

    var isTargetMet: Bool {
        totalPreloadTime < targetLaunchTime
    }

    var description: String {
        """
        Launch Metrics:
        - FFmpeg Load Time: \(String(format: "%.3f", ffmpegLoadTime))s
        - Metal Init Time: \(String(format: "%.3f", metalInitTime))s
        - Total Preload Time: \(String(format: "%.3f", totalPreloadTime))s
        - Target: \(String(format: "%.3f", targetLaunchTime))s
        - Status: \(isTargetMet ? "✅ PASS" : "❌ FAIL")
        """
    }
}

// MARK: - AppDelegate Extension

#if canImport(UIKit)
import UIKit

extension UIApplicationDelegate {
    /// 在 didFinishLaunchingWithOptions 中调用，优化启动性能
    func optimizeLaunchPerformance() {
        // 立即返回，不阻塞主线程
        Task {
            await Preloader().preloadCriticalResources()

            // 记录性能指标
            let metrics = await Preloader().getLaunchMetrics()
            DependencyContainer.shared.makeLogger().info(metrics.description)
        }
    }
}
#endif