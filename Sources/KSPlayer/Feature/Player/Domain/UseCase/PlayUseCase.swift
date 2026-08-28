//
//  PlayUseCase.swift
//  KSPlayer
//
//  Created by Architecture Team on 2026/08/28.
//  播放用例
//

import Foundation

/// 播放用例
@MainActor
final class PlayUseCase {
    private let playerService: PlayerServiceProtocol
    private let historyRepository: HistoryRepositoryProtocol
    private let logger: LoggerProtocol

    init(
        playerService: PlayerServiceProtocol,
        historyRepository: HistoryRepositoryProtocol,
        logger: LoggerProtocol
    ) {
        self.playerService = playerService
        self.historyRepository = historyRepository
        self.logger = logger
    }

    /// 执行播放
    /// - Parameter url: 媒体 URL
    func execute(url: URL) async throws {
        // 1. 加载媒体
        let item = try await LoadMediaUseCase(
            repository: DependencyContainer.shared.makeMediaRepository(),
            cacheRepository: DependencyContainer.shared.makeCacheRepository(),
            logger: DependencyContainer.shared.makeLogger()
        ).execute(url: url)

        // 2. 准备播放器
        try await playerService.load(url: url)

        // 3. 记录到历史（异步，不阻塞）
        let repository = historyRepository
        Task.detached(priority: .utility) {
            try? await repository.addHistory(item, progress: 0)
        }

        // 4. 开始播放
        playerService.play()

        logger.info("Started playing: \(item.title ?? url.lastPathComponent)")
    }

    /// 暂停播放
    func pause() {
        guard playerService.state == .playing else { return }
        playerService.pause()
        logger.info("Paused playback")
    }

    /// 恢复播放
    func resume() {
        guard playerService.state == .paused else { return }
        playerService.play()
        logger.info("Resumed playback")
    }

    /// Seek
    /// - Parameter time: 目标时间（秒）
    func seek(to time: TimeInterval) async throws {
        guard playerService.state != .idle else {
            throw PlayerError.loadFailed(reason: "No media loaded")
        }

        try await playerService.seek(to: time)
        logger.info("Seeked to \(String(format: "%.2f", time))s")
    }

    /// 停止播放
    func stop() {
        playerService.stop()
        logger.info("Stopped playback")
    }

    /// 设置播放速率
    /// - Parameter rate: 播放速率（0.5 - 2.0）
    func setPlaybackRate(_ rate: Float) {
        let clampedRate = max(0.5, min(2.0, rate))
        playerService.setPlaybackRate(clampedRate)
        logger.info("Playback rate: \(String(format: "%.1fx", clampedRate))")
    }

    /// 设置音量
    /// - Parameter volume: 音量（0.0 - 1.0）
    func setVolume(_ volume: Float) {
        let clampedVolume = max(0.0, min(1.0, volume))
        playerService.setVolume(clampedVolume)
    }

    /// 设置静音
    /// - Parameter muted: 是否静音
    func setMuted(_ muted: Bool) {
        playerService.setMuted(muted)
        logger.info("Muted: \(muted)")
    }
}