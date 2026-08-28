//
//  PlayerViewModel.swift
//  KSPlayer
//
//  Created by Architecture Team on 2026/08/28.
//  播放器视图模型 - 纯 UI 逻辑，无业务逻辑
//

import Foundation
import Combine
import AVFoundation

@MainActor
final class PlayerViewModel: ObservableObject {
    // MARK: - Published State

    @Published private(set) var state: PlayerState = .idle
    @Published private(set) var title: String = ""
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var bufferProgress: Double = 0
    @Published private(set) var isMuted: Bool = false
    @Published private(set) var volume: Float = 1.0
    @Published private(set) var playbackRate: Float = 1.0
    @Published private(set) var errorMessage: String?

    // MARK: - Use Cases

    private let loadUseCase: LoadMediaUseCase
    private let playUseCase: PlayUseCase
    private let cacheUseCase: CacheUseCase
    private let seekUseCase: SeekUseCase

    // MARK: - Subscriptions

    private var cancellables = Set<AnyCancellable>()
    private let router: KSRouterProtocol
    private let logger: LoggerProtocol

    // MARK: - Initialization

    init(
        loadUseCase: LoadMediaUseCase,
        playUseCase: PlayUseCase,
        cacheUseCase: CacheUseCase,
        seekUseCase: SeekUseCase
    ) {
        self.loadUseCase = loadUseCase
        self.playUseCase = playUseCase
        self.cacheUseCase = cacheUseCase
        self.seekUseCase = seekUseCase
        self.router = DependencyContainer.shared.makeRouter()
        self.logger = DependencyContainer.shared.makeLogger()

        setupBindings()
    }

    // MARK: - Public Methods

    /// 加载并播放
    func loadAndPlay(url: URL) {
        Task {
            await doLoadAndPlay(url: url)
        }
    }

    /// 播放
    func play() {
        playUseCase.resume()
        state = .playing
    }

    /// 暂停
    func pause() {
        playUseCase.pause()
        state = .paused
    }

    /// Stop
    func stop() {
        playUseCase.stop()
        state = .idle
    }

    /// Seek
    func seek(to time: TimeInterval) {
        Task {
            await doSeek(to: time)
        }
    }

    /// 设置音量
    func setVolume(_ volume: Float) {
        self.volume = volume
        playUseCase.setVolume(volume)
    }

    /// 设置静音
    func setMuted(_ muted: Bool) {
        self.isMuted = muted
        playUseCase.setMuted(muted)
    }

    /// 设置播放速率
    func setPlaybackRate(_ rate: Float) {
        self.playbackRate = rate
        playUseCase.setPlaybackRate(rate)
    }

    /// 重试错误
    func retry() {
        guard let currentUrl = currentUrl else { return }
        loadAndPlay(url: currentUrl)
    }

    // MARK: - Private Methods

    private func doLoadAndPlay(url: URL) async {
        state = .loading(progress: 0)
        errorMessage = nil

        do {
            try await playUseCase.execute(url: url)
            currentUrl = url
            state = .playing
        } catch {
            state = .error(error as? PlayerError ?? .loadFailed(reason: error.localizedDescription))
            errorMessage = (error as? PlayerError)?.message ?? error.localizedDescription
            logger.error("Failed to load: \(error.localizedDescription)")
        }
    }

    private func doSeek(to time: TimeInterval) async {
        state = .seeking

        do {
            try await playUseCase.seek(to: time)
            state = .playing
        } catch {
            state = .error(error as? PlayerError ?? .loadFailed(reason: error.localizedDescription))
            errorMessage = (error as? PlayerError)?.message ?? error.localizedDescription
        }
    }

    private func setupBindings() {
        // 订阅路由事件
        router.addSubscription(to: KSRouterEvent.self) { [weak self] event in
            self?.handleRouterEvent(event)
        }
    }

    private func handleRouterEvent(_ event: KSRouterEvent) {
        switch event {
        case .playMedia(let url):
            loadAndPlay(url: url)
        case .pausePlayback:
            pause()
        case .seekTo(let time):
            seek(to: time)
        case .openSettings:
            // TODO: 打开设置
            break
        default:
            break
        }
    }

    // MARK: - Computed Properties

    private var currentUrl: URL?

    var formattedCurrentTime: String {
        formatTime(currentTime)
    }

    var formattedDuration: String {
        formatTime(duration)
    }

    var progressPercentage: Double {
        guard duration > 0 else { return 0 }
        return currentTime / duration
    }

    var isLoading: Bool {
        if case .loading = state { return true }
        return false
    }

    var isPlaying: Bool {
        if case .playing = state { return true }
        return false
    }

    var isPaused: Bool {
        if case .paused = state { return true }
        return false
    }

    var isError: Bool {
        if case .error = state { return true }
        return false
    }

    // MARK: - Utility Methods

    private func formatTime(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = Int(seconds) % 3600 / 60
        let secs = Int(seconds) % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%d:%02d", minutes, secs)
        }
    }
}

// MARK: - Cache Use Case (Placeholder)

final class CacheUseCase {
    private let cacheRepository: CacheRepositoryProtocol

    init(cacheRepository: CacheRepositoryProtocol) {
        self.cacheRepository = cacheRepository
    }

    func preload(url: URL) async throws {
        // TODO: 实现预加载逻辑
    }
}

// MARK: - Seek Use Case (Placeholder)

final class SeekUseCase {
    private let playerService: PlayerServiceProtocol

    init(playerService: PlayerServiceProtocol) {
        self.playerService = playerService
    }

    func seekToPercentage(_ percentage: Double) async throws {
        // TODO: 实现百分比 seek
    }
}