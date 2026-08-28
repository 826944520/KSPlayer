//
//  EventBus.swift
//  KSPlayer
//
//  Created by Architecture Team on 2026/08/28.
//  事件总线 - 解耦模块间通信
//

import Foundation
import Combine

/// 事件总线 - 发布/订阅模式
final class EventBus {
    static let shared = EventBus()

    private let subject = PassthroughSubject<Any, Never>()
    private var subscriptions: Set<AnyCancellable> = []

    init() {}

    /// 发送事件
    func send<T>(_ event: T) {
        subject.send(event)
    }

    /// 订阅特定类型的事件
    func events<T>(ofType type: T.Type) -> AnyPublisher<T, Never> where T: Any {
        subject
            .compactMap { $0 as? T }
            .eraseToAnyPublisher()
    }

    /// 添加订阅（自动管理生命周期）
    @discardableResult
    func subscribe<T>(_ subscriber: AnyObject, to eventType: T.Type, handler: @escaping (T) -> Void) -> AnyCancellable where T: Any {
        let cancellable = events(ofType: eventType)
            .sink { [weak subscriber] value in
                handler(value)
            }

        subscriptions.insert(cancellable)
        return cancellable
    }

    /// 移除所有订阅
    func removeAllSubscriptions() {
        subscriptions.removeAll()
    }

    /// 添加手动管理的订阅
    func addSubscription(_ cancellable: AnyCancellable) {
        subscriptions.insert(cancellable)
    }
}

// MARK: - 触感反馈

#if canImport(UIKit)
import UIKit

extension UIView {
    /// 触感反馈（UIImpactFeedbackGenerator）
    func triggerImpact(style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.impactOccurred()
    }

    /// 选择反馈（UISelectionFeedbackGenerator）
    func triggerSelection() {
        let generator = UISelectionFeedbackGenerator()
        generator.selectionChanged()
    }

    /// 通知反馈（UINotificationFeedbackGenerator）
    func triggerNotification(_ type: UINotificationFeedbackGenerator.FeedbackType = .success) {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(type)
    }
}
#endif