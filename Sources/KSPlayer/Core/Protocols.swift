//
//  PlayerServiceProtocol.swift
//  KSPlayer
//
//  Created by Architecture Team on 2026/08/28.
//  播放器服务协议 - 依赖倒置
//

import Foundation
import Combine
import AVFoundation

// MARK: - Domain Entities

/// 媒体项
struct MediaItem: Identifiable, Equatable {
    let id: String
    let url: URL
    let duration: TimeInterval
    let title: String?
    let thumbnail: URL?
}

/// 历史项
struct HistoryItem: Identifiable, Equatable {
    let id: String
    let mediaItem: MediaItem
    let progress: TimeInterval
    let lastPlayed: Date
}

/// 字幕项
struct SubtitleItem: Identifiable, Equatable {
    let id: String
    let url: URL
    let language: String?
    let title: String?
}

/// 字幕 URL
struct SubtitleURL: Identifiable {
    let id: String
    let url: URL
    let language: String?
    let source: String
}

/// 媒体项视图模型
struct MediaItemViewModel: Identifiable, Equatable {
    let id: String
    let title: String
    let duration: String
}

// MARK: - Player Protocols

/// 播放器状态
enum PlayerState: Equatable {
    case idle
    case loading(progress: Double)
    case ready
    case playing
    case paused
    case seeking
    case finished
    case error(PlayerError)
}

/// 播放器错误
enum PlayerError: Error, Equatable {
    case loadFailed(reason: String)
    case networkFailed
    case decodeFailed
    case renderFailed
    case invalidUrl
    case permissionDenied
    case cacheMiss

    var message: String {
        switch self {
        case .loadFailed(let reason):
            return "加载失败：\(reason)"
        case .networkFailed:
            return "网络连接失败，请检查网络设置"
        case .decodeFailed:
            return "解码失败，格式不支持"
        case .renderFailed:
            return "渲染失败"
        case .invalidUrl:
            return "无效的视频地址"
        case .permissionDenied:
            return "权限被拒绝，请在设置中允许"
        case .cacheMiss:
            return "缓存未命中"
        }
    }
}

/// 播放进度
struct PlaybackProgress: Equatable {
    let currentTime: TimeInterval
    let duration: TimeInterval
    let bufferProgress: Double

    var isBuffered: Bool {
        bufferProgress >= 1.0
    }
}

/// 播放器事件
enum PlayerEvent {
    case stateChanged(PlayerState)
    case progressUpdated(PlaybackProgress)
    case errorOccurred(PlayerError)
}

/// 播放器服务协议
@MainActor
protocol PlayerServiceProtocol {
    /// 当前状态
    var state: PlayerState { get }

    /// 当前进度
    var progress: PlaybackProgress? { get }

    /// 事件流
    var events: AnyPublisher<PlayerEvent, Never> { get }

    /// 加载媒体
    func load(url: URL) async throws

    /// 播放
    func play()

    /// 暂停
    func pause()

    /// 停止
    func stop()

    /// Seek
    func seek(to time: TimeInterval) async throws

    /// 设置播放速率
    func setPlaybackRate(_ rate: Float)

    /// 设置音量
    func setVolume(_ volume: Float)

    /// 设置静音
    func setMuted(_ muted: Bool)

    /// 释放资源
    func cleanup()
}

/// 渲染服务协议
protocol RenderServiceProtocol {
    /// 渲染帧
    func render(frame: VideoFrame) throws

    /// 清空
    func flush()

    /// 设置渲染视图
    func setRenderView(_ view: VideoRenderViewProtocol)
}

/// 音频服务协议
@MainActor
protocol AudioServiceProtocol {
    /// 播放音频
    func play(buffer: AudioBuffer) throws

    /// 暂停
    func pause()

    /// 停止
    func stop()

    /// 设置音量
    func setVolume(_ volume: Float)
}

/// 缓存服务协议
protocol CacheServiceProtocol {
    /// 获取缓存
    func get(key: String) async throws -> Data?

    /// 设置缓存
    func set(_ data: Data, for key: String) async throws

    /// 删除缓存
    func remove(key: String) async throws

    /// 清空所有缓存
    func clearAll() async throws

    /// 获取缓存大小
    func getSize() async throws -> Int64
}

/// 媒体仓库协议
protocol MediaRepositoryProtocol {
    /// 获取媒体信息
    func fetchMedia(url: URL) async throws -> MediaItem

    /// 缓存媒体
    func cacheMedia(_ item: MediaItem) async throws

    /// 获取缓存媒体
    func getCachedMedia(url: URL) async -> MediaItem?

    /// 获取最近播放
    func getRecentMedia(limit: Int) async throws -> [MediaItem]
}

/// 字幕仓库协议
protocol SubtitleRepositoryProtocol {
    /// 加载字幕
    func loadSubtitle(url: URL) async throws -> [SubtitleItem]

    /// 搜索字幕
    func searchSubtitles(for url: URL) async throws -> [SubtitleURL]

    /// 切换字幕
    func switchSubtitle(to url: URL?) async throws
}

/// 历史仓库协议
protocol HistoryRepositoryProtocol {
    /// 添加播放记录
    func addHistory(_ item: MediaItem, progress: TimeInterval) async throws

    /// 获取历史记录
    func getHistory(limit: Int) async throws -> [HistoryItem]

    /// 清空历史
    func clearHistory() async throws
}

/// 视频帧协议
protocol VideoFrame {
    var timestamp: CMTime { get }
    var pixelBuffer: CVPixelBuffer? { get }
    var duration: CMTime { get }
}

/// 音频缓冲协议
protocol AudioBuffer {
    var data: UnsafeRawPointer { get }
    var frameCount: UInt32 { get }
    var format: AVAudioFormat { get }
}

/// 视频渲染视图协议
protocol VideoRenderViewProtocol: AnyObject {
    var size: CGSize { get set }
    func display(_ frame: VideoFrame)
    func clear()
}

/// 缓存仓库协议
protocol CacheRepositoryProtocol {
    /// 获取缓存媒体
    func getCachedMedia(url: URL) async -> MediaItem?

    /// 获取缓存大小
    func getCacheSize() async throws -> Int64

    /// 清空缓存
    func clearCache() async throws

    /// 预加载媒体
    func preloadMedia(url: URL) async throws
}