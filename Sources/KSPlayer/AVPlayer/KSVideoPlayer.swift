


import Foundation
import SwiftUI

#if canImport(UIKit)
import UIKit
#else
import AppKit

public typealias UIViewRepresentable = NSViewRepresentable
#endif

public struct KSVideoPlayer {
    public private(set) var coordinator: Coordinator
    public let url: URL
    public let options: KSOptions
    public init(coordinator: Coordinator, url: URL, options: KSOptions) {
        self.coordinator = coordinator
        self.url = url
        self.options = options
    }
}

extension KSVideoPlayer: UIViewRepresentable {
    public func makeCoordinator() -> Coordinator {
        coordinator
    }

    #if canImport(UIKit)
    public typealias UIViewType = UIView
    public func makeUIView(context: Context) -> UIViewType {
        context.coordinator.makeView(url: url, options: options)
    }

    public func updateUIView(_ view: UIViewType, context: Context) {
        updateView(view, context: context)
    }


    public static func dismantleUIView(_: UIViewType, coordinator: Coordinator) {
        coordinator.resetPlayer()
    }
    #else
    public typealias NSViewType = UIView
    public func makeNSView(context: Context) -> NSViewType {
        context.coordinator.makeView(url: url, options: options)
    }

    public func updateNSView(_ view: NSViewType, context: Context) {
        updateView(view, context: context)
    }


    public static func dismantleNSView(_ view: NSViewType, coordinator: Coordinator) {
        coordinator.resetPlayer()
        view.window?.aspectRatio = CGSize(width: 16, height: 9)
    }
    #endif

    @MainActor
    private func updateView(_: UIView, context: Context) {
        if context.coordinator.playerLayer?.url != url {
            _ = context.coordinator.makeView(url: url, options: options)
        }
    }

    @MainActor
    public final class Coordinator: ObservableObject {
        public var state: KSPlayerState {
            playerLayer?.state ?? .initialized
        }

        @Published
        public var isMuted: Bool = false {
            didSet {
                playerLayer?.player.isMuted = isMuted
            }
        }

        @Published
        public var playbackVolume: Float = 1.0 {
            didSet {
                playerLayer?.player.playbackVolume = playbackVolume
            }
        }

        @Published
        public var isScaleAspectFill = false {
            didSet {
                playerLayer?.player.contentMode = isScaleAspectFill ? .scaleAspectFill : .scaleAspectFit
            }
        }

        @Published
        public var playbackRate: Float = 1.0 {
            didSet {
                playerLayer?.player.playbackRate = playbackRate
            }
        }

        @Published
        @MainActor
        public var isMaskShow = true {
            didSet {
                if isMaskShow != oldValue {
                    mask(show: isMaskShow)
                }
            }
        }

        public var subtitleModel = SubtitleModel()
        public var timemodel = ControllerTimeModel()

        public var playerLayer: KSPlayerLayer? {
            didSet {
                oldValue?.delegate = nil
                oldValue?.pause()
            }
        }

        private var delayHide: DispatchWorkItem?
        public var onPlay: ((TimeInterval, TimeInterval) -> Void)?
        public var onFinish: ((KSPlayerLayer, Error?) -> Void)?
        public var onStateChanged: ((KSPlayerLayer, KSPlayerState) -> Void)?
        public var onBufferChanged: ((Int, TimeInterval) -> Void)?
        #if canImport(UIKit)
        fileprivate var onSwipe: ((UISwipeGestureRecognizer.Direction) -> Void)?
        @objc fileprivate func swipeGestureAction(_ recognizer: UISwipeGestureRecognizer) {
            onSwipe?(recognizer.direction)
        }
        #endif

        public init() {}

        public func makeView(url: URL, options: KSOptions) -> UIView {
            defer {
                DispatchQueue.main.async { [weak self] in
                    self?.subtitleModel.url = url
                }
            }
            if let playerLayer {
                if playerLayer.url == url {
                    return playerLayer.player.view ?? UIView()
                }
                playerLayer.delegate = nil
                playerLayer.set(url: url, options: options)
                playerLayer.delegate = self
                return playerLayer.player.view ?? UIView()
            } else {
                let playerLayer = KSPlayerLayer(url: url, options: options, delegate: self)
                self.playerLayer = playerLayer
                return playerLayer.player.view ?? UIView()
            }
        }

        public func resetPlayer() {
            onStateChanged = nil
            onPlay = nil
            onFinish = nil
            onBufferChanged = nil
            #if canImport(UIKit)
            onSwipe = nil
            #endif
            playerLayer = nil
            delayHide?.cancel()
            delayHide = nil
            subtitleModel.selectedSubtitleInfo?.isEnabled = false
        }

        public func skip(interval: Int) {
            if let playerLayer {
                seek(time: playerLayer.player.currentPlaybackTime + TimeInterval(interval))
            }
        }

        public func seek(time: TimeInterval) {
            playerLayer?.seek(time: TimeInterval(time))
        }

        @MainActor
        public func mask(show: Bool, autoHide: Bool = true) {
            isMaskShow = show
            if show {
                delayHide?.cancel()

                guard state == .bufferFinished else { return }
                if autoHide {
                    delayHide = DispatchWorkItem { [weak self] in
                        guard let self else { return }
                        if self.state == .bufferFinished {
                            self.isMaskShow = false
                        }
                    }
                    DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + KSOptions.animateDelayTimeInterval,
                                                  execute: delayHide!)
                }
            }
            #if os(macOS)
            show ? NSCursor.unhide() : NSCursor.setHiddenUntilMouseMoves(true)
            if let window = playerLayer?.player.view?.window {
                if !window.styleMask.contains(.fullScreen) {
                    window.standardWindowButton(.closeButton)?.superview?.superview?.isHidden = !show

                }
            }
            #endif
        }
    }
}

extension KSVideoPlayer.Coordinator: KSPlayerLayerDelegate {
    public func player(layer: KSPlayerLayer, state: KSPlayerState) {
        onStateChanged?(layer, state)
        if state == .readyToPlay {
            playbackRate = layer.player.playbackRate
            if let subtitleDataSouce = layer.player.subtitleDataSouce {

                DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 1) { [weak self] in
                    guard let self else { return }
                    self.subtitleModel.addSubtitle(dataSouce: subtitleDataSouce)
                    if self.subtitleModel.selectedSubtitleInfo == nil, layer.options.autoSelectEmbedSubtitle {
                        self.subtitleModel.selectedSubtitleInfo = subtitleDataSouce.infos.first { $0.isEnabled }
                    }
                }
            }
        } else if state == .bufferFinished {
            isMaskShow = false
        } else {
            isMaskShow = true
            #if canImport(UIKit)
            if state == .preparing, let view = layer.player.view {
                let swipeDown = UISwipeGestureRecognizer(target: self, action: #selector(swipeGestureAction(_:)))
                swipeDown.direction = .down
                view.addGestureRecognizer(swipeDown)
                let swipeLeft = UISwipeGestureRecognizer(target: self, action: #selector(swipeGestureAction(_:)))
                swipeLeft.direction = .left
                view.addGestureRecognizer(swipeLeft)
                let swipeRight = UISwipeGestureRecognizer(target: self, action: #selector(swipeGestureAction(_:)))
                swipeRight.direction = .right
                view.addGestureRecognizer(swipeRight)
                let swipeUp = UISwipeGestureRecognizer(target: self, action: #selector(swipeGestureAction(_:)))
                swipeUp.direction = .up
                view.addGestureRecognizer(swipeUp)
            }
            #endif
        }
    }

    public func player(layer _: KSPlayerLayer, currentTime: TimeInterval, totalTime: TimeInterval) {
        onPlay?(currentTime, totalTime)
        if currentTime >= Double(Int.max) || currentTime <= Double(Int.min) || totalTime >= Double(Int.max) || totalTime <= Double(Int.min) {
            return
        }
        let current = Int(currentTime)
        let total = Int(max(0, totalTime))
        if timemodel.currentTime != current {
            timemodel.currentTime = current
        }
        if timemodel.totalTime != total {
            timemodel.totalTime = total
        }
        _ = subtitleModel.subtitle(currentTime: currentTime)
    }

    public func player(layer: KSPlayerLayer, finish error: Error?) {
        onFinish?(layer, error)
    }

    public func player(layer _: KSPlayerLayer, bufferedCount: Int, consumeTime: TimeInterval) {
        onBufferChanged?(bufferedCount, consumeTime)
    }
}

extension KSVideoPlayer: Equatable {
    public static func == (lhs: KSVideoPlayer, rhs: KSVideoPlayer) -> Bool {
        lhs.url == rhs.url
    }
}

@MainActor
public extension KSVideoPlayer {
    func onBufferChanged(_ handler: @escaping (Int, TimeInterval) -> Void) -> Self {
        coordinator.onBufferChanged = handler
        return self
    }


    func onFinish(_ handler: @escaping (KSPlayerLayer, Error?) -> Void) -> Self {
        coordinator.onFinish = handler
        return self
    }

    func onPlay(_ handler: @escaping (TimeInterval, TimeInterval) -> Void) -> Self {
        coordinator.onPlay = handler
        return self
    }


    func onStateChanged(_ handler: @escaping (KSPlayerLayer, KSPlayerState) -> Void) -> Self {
        coordinator.onStateChanged = handler
        return self
    }

    #if canImport(UIKit)
    func onSwipe(_ handler: @escaping (UISwipeGestureRecognizer.Direction) -> Void) -> Self {
        coordinator.onSwipe = handler
        return self
    }
    #endif
}

extension View {
    func then(_ body: (inout Self) -> Void) -> Self {
        var result = self
        body(&result)
        return result
    }
}


public class ControllerTimeModel: ObservableObject {

    @Published
    public var currentTime = 0
    @Published
    public var totalTime = 1
}
