//
//  DependencyContainer.swift
//  KSPlayer
//
//  Created by Architecture Team on 2026/08/28.
//  依赖注入容器 - 管理所有单例和服务实例
//

import Foundation
import Combine

/// 依赖注入容器
@MainActor
final class DependencyContainer {
    // MARK: - Singleton
    static let shared = DependencyContainer()

    // MARK: - Core Services
    private lazy var eventBus = EventBus()
    private lazy var logger = Logger()
    private lazy var networkMonitor = NetworkMonitor()
    private lazy var permissionChecker = PermissionChecker()

    // MARK: - Infrastructure Services
    private var playerService: PlayerServiceProtocol?
    private var renderService: RenderServiceProtocol?
    private var audioService: AudioServiceProtocol?
    private var cacheService: CacheServiceProtocol?

    // MARK: - Repository
    private var mediaRepository: MediaRepositoryProtocol?
    private var cacheRepository: CacheRepositoryProtocol?
    private var subtitleRepository: SubtitleRepositoryProtocol?
    private var historyRepository: HistoryRepositoryProtocol?

    private init() {
        setupServices()
    }

    // MARK: - Service Factory Methods

    /// 创建播放器服务（根据配置选择 AVPlayer 或 FFmpeg）
    func makePlayerService() -> PlayerServiceProtocol {
        if let existing = playerService {
            return existing
        }

        let service: PlayerServiceProtocol
        switch KSOptions.playerType {
        case .avPlayer:
            service = AVPlayerService()
        case .ffmpeg:
            service = FFmpegPlayerService()
        @unknown default:
            service = AVPlayerService()
        }

        playerService = service
        return service
    }

    /// 创建渲染服务
    func makeRenderService() -> RenderServiceProtocol {
        if let existing = renderService {
            return existing
        }

        let service = MetalRenderService(device: MetalRender.device)
        renderService = service
        return service
    }

    /// 创建音频服务
    func makeAudioService() -> AudioServiceProtocol {
        if let existing = audioService {
            return existing
        }

        let service: AudioServiceProtocol
        switch KSOptions.audioPlayerType {
        case is AudioEnginePlayer.self:
            service = AudioEngineService()
        case is AudioRendererPlayer.self:
            service = AudioRendererService()
        case is AudioUnitPlayer.self:
            service = AudioUnitService()
        default:
            service = AudioEngineService()
        }

        audioService = service
        return service
    }

    /// 创建缓存服务
    func makeCacheService() -> CacheServiceProtocol {
        if let existing = cacheService {
            return existing
        }

        let service = HybridCacheService(
            memoryCache: MemoryCacheService(maxItems: 100),
            diskCache: DiskCacheService(maxSize: 2 * 1024 * 1024 * 1024) // 2GB
        )
        cacheService = service
        return service
    }

    // MARK: - Repository Factory Methods

    func makeMediaRepository() -> MediaRepositoryProtocol {
        if let existing = mediaRepository {
            return existing
        }

        let repository = MediaRepository(
            dataSource: FFmpegMediaDataSource(),
            cacheDataSource: makeCacheService()
        )
        mediaRepository = repository
        return repository
    }

    func makeCacheRepository() -> CacheRepositoryProtocol {
        if let existing = cacheRepository {
            return existing
        }

        let repository = CacheRepository(
            cacheService: makeCacheService(),
            networkMonitor: networkMonitor
        )
        cacheRepository = repository
        return repository
    }

    func makeSubtitleRepository() -> SubtitleRepositoryProtocol {
        if let existing = subtitleRepository {
            return existing
        }

        let repository = SubtitleRepository(
            localDataSource: LocalFileDataSource(),
            networkDataSource: NetworkSubtitleDataSource()
        )
        subtitleRepository = repository
        return repository
    }

    func makeHistoryRepository() -> HistoryRepositoryProtocol {
        if let existing = historyRepository {
            return existing
        }

        let repository = HistoryRepository(
            dataSource: UserDefaultsHistoryDataSource()
        )
        historyRepository = repository
        return repository
    }

    // MARK: - Core Services Access

    func makeEventBus() -> EventBus {
        return eventBus
    }

    func makeLogger() -> Logger {
        return logger
    }

    func makeNetworkMonitor() -> NetworkMonitor {
        return networkMonitor
    }

    func makePermissionChecker() -> PermissionChecker {
        return permissionChecker
    }

    // MARK: - Setup

    private func setupServices() {
        // 预加载关键资源
        Task {
            await preloadCriticalResources()
        }
    }

    private func preloadCriticalResources() async {
        // 异步预加载，不阻塞启动
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                self.logger.info("Preloading Metal shaders...")
                // MetalRender.preloadShaders()
            }
            group.addTask {
                self.logger.info("Initializing network monitor...")
                await self.networkMonitor.startMonitoring()
            }
            group.addTask {
                self.logger.info("Checking permissions...")
                await self.permissionChecker.checkAvailability()
            }
        }
    }

    // MARK: - Cleanup

    func cleanup() {
        eventBus.removeAllSubscriptions()
        networkMonitor.stopMonitoring()
        logger.flush()
    }
}