//
//  LoadMediaUseCase.swift
//  KSPlayer
//
//  Created by Architecture Team on 2026/08/28.
//  加载媒体用例
//

import Foundation

/// 加载媒体用例
final class LoadMediaUseCase {
    private let repository: MediaRepositoryProtocol
    private let cacheRepository: CacheRepositoryProtocol
    private let logger: LoggerProtocol

    private let maximumRetryCount = 3
    private let networkTimeout: TimeInterval = 10.0

    init(
        repository: MediaRepositoryProtocol,
        cacheRepository: CacheRepositoryProtocol,
        logger: LoggerProtocol
    ) {
        self.repository = repository
        self.cacheRepository = cacheRepository
        self.logger = logger
    }

    /// 执行加载
    /// - Parameter url: 媒体 URL
    /// - Returns: 媒体项
    /// - Throws: PlayerError
    func execute(url: URL) async throws -> MediaItem {
        let startTime = Date()

        // 1. 验证 URL
        try validate(url: url)

        // 2. 尝试从缓存加载
        if let cached = try? await cacheRepository.getCachedMedia(url: url) {
            let loadTime = Date().timeIntervalSince(startTime)
            logger.info("Loaded from cache in \(String(format: "%.2f", loadTime))s")

            return cached
        }

        // 3. 从网络/文件加载（带重试）
        let item = try await loadWithRetry(url: url)

        // 4. 记录加载性能
        let loadTime = Date().timeIntervalSince(startTime)
        if loadTime > 2.0 {
            logger.warning("Slow load: \(String(format: "%.2f", loadTime))s")
        } else {
            logger.info("Loaded in \(String(format: "%.2f", loadTime))s")
        }

        // 5. 异步缓存（不阻塞返回）
        Task.detached(priority: .utility) {
            try? await self.repository.cacheMedia(item)
        }

        return item
    }

    // MARK: - Private Methods

    /// 验证 URL
    private func validate(url: URL) throws {
        guard url.scheme == "http" || url.scheme == "https" || url.isFileURL else {
            throw PlayerError.invalidUrl
        }
    }

    /// 带重试的加载
    private func loadWithRetry(url: URL) async throws -> MediaItem {
        var lastError: Error?

        for attempt in 1...maximumRetryCount {
            do {
                return try await loadOnce(url: url)
            } catch {
                lastError = error
                logger.warning("Load attempt \(attempt)/\(maximumRetryCount) failed: \(error.localizedDescription)")

                // 如果是最后一次尝试，不等待
                guard attempt < maximumRetryCount else {
                    break
                }

                // 指数退避等待
                let delay = pow(2.0, Double(attempt - 1))
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }

        // 重试失败，尝试返回缓存
        if let cached = try? await cacheRepository.getCachedMedia(url: url) {
            logger.info("Retry failed, returning cached version")
            return cached
        }

        throw lastError ?? PlayerError.loadFailed(reason: "Unknown error")
    }

    /// 单次加载
    private func loadOnce(url: URL) async throws -> MediaItem {
        // 带超时的加载
        return try await withThrowingTaskGroup(of: MediaItem.self) { group in
            group.addTask {
                try await withTimeout(seconds: networkTimeout) {
                    try await self.repository.fetchMedia(url: url)
                }
            }

            let result = try await group.next()

            group.cancelAll()

            return result
        }
    }

    /// 超时包装
    private func withTimeout<T>(
        seconds: TimeInterval,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }

            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw PlayerError.networkFailed
            }

            let result = try await group.next()
            group.cancelAll()
            return result
        }
    }
}

// MARK: - Error Handling

extension LoadMediaUseCase {
    enum LoadError: LocalizedError {
        case invalidURL
        case networkTimeout
        case maxRetryExceeded

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "无效的 URL"
            case .networkTimeout:
                return "网络超时"
            case .maxRetryExceeded:
                return "超过最大重试次数"
            }
        }
    }
}