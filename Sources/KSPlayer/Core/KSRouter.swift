//
//  KSRouter.swift
//  KSPlayer
//
//  Created by Architecture Team on 2026/08/28.
//  路由系统 - 模块间通信机制（替代直接类引用）
//

import Foundation
import Combine

/// 路由事件
enum KSRouterEvent {
    case playMedia(url: URL)
    case pausePlayback
    case seekTo(time: TimeInterval)
    case changeSubtitle(url: URL?)
    case openSettings
    case showHistory
    case clearCache
    case download(url: URL)
}

/// 路由接口 - 模块间通过此接口通信
protocol KSRouterProtocol {
    /// 发布路由事件
    func route(_ event: KSRouterEvent)

    /// 订阅路由事件
    func subscribe(to eventType: KSRouterEvent.Type) -> AnyPublisher<KSRouterEvent, Never>
}

/// 路由实现 - 使用事件总线
final class KSRouter: KSRouterProtocol {
    private let eventBus: EventBus
    private var subscriptions: [ObjectIdentifier: AnyCancellable] = [:]

    init(eventBus: EventBus = .shared) {
        self.eventBus = eventBus
    }

    func route(_ event: KSRouterEvent) {
        eventBus.send(event: RouterEvent.wrapped(event))
    }

    func subscribe(to eventType: KSRouterEvent.Type) -> AnyPublisher<KSRouterEvent, Never> {
        eventBus
            .events(ofType: RouterEvent.self)
            .compactMap { $0.unwrap() }
            .eraseToAnyPublisher()
    }

    /// 添加订阅（返回可取消对象）
    @discardableResult
    func addSubscription(to eventType: KSRouterEvent.Type, handler: @escaping (KSRouterEvent) -> Void) -> AnyCancellable {
        subscribe(to: eventType)
            .sink(receiveValue: handler)
    }
}

// MARK: - Router Event Wrapper

private enum RouterEvent {
    case wrapped(KSRouterEvent)

    func unwrap() -> KSRouterEvent? {
        switch self {
        case .wrapped(let event):
            return event
        }
    }
}

// MARK: - EventBus Extension

extension EventBus {
    /// 发送路由事件
    func route(_ event: KSRouterEvent) {
        send(RouterEvent.wrapped(event))
    }

    /// 订阅路由事件
    func subscribe(to eventType: KSRouterEvent.Type) -> AnyPublisher<KSRouterEvent, Never> {
        events(ofType: RouterEvent.self)
            .compactMap { $0.unwrap() }
            .eraseToAnyPublisher()
    }
}