//
//  FeaturePlayerView.swift
//  KSPlayer
//
//  Created by Architecture Team on 2026/08/28.
//  播放器视图 - SwiftUI 实现
//

import SwiftUI

struct FeaturePlayerView: View {
    @StateObject private var viewModel: PlayerViewModel

    init(viewModel: PlayerViewModel) {
        self._viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        ZStack {
            switch viewModel.state {
            case .idle:
                IdleView(onLoad: { url in
                    viewModel.loadAndPlay(url: url)
                })
            case .loading(let progress):
                LoadingView(progress: progress)
            case .ready, .playing, .paused:
                VideoContentView(viewModel: viewModel)
            case .seeking:
                SeekingView(viewModel: viewModel)
            case .finished:
                VideoContentView(viewModel: viewModel)
            case .error:
                ErrorPlaceholderView(
                    message: viewModel.errorMessage ?? "加载失败",
                    onRetry: { viewModel.retry() }
                )
            }

            if !viewModel.isLoading {
                ControlsOverlayView(viewModel: viewModel)
            }
        }
        .background(Color.black)
        .onAppear {
            // TODO: 恢复播放状态
        }
    }
}

// MARK: - Subviews

private struct IdleView: View {
    let onLoad: (URL) -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "play.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.white)

            Text("选择视频")
                .font(.title2)
                .foregroundColor(.white)

            Button(action: {
                // TODO: 打开文件选择器
            }) {
                Text("选择文件")
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
        }
    }
}

private struct LoadingView: View {
    let progress: Double

    var body: some View {
        VStack(spacing: 16) {
            ProgressView(value: progress)
                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                .scaleEffect(1.5)

            Text("加载中...")
                .foregroundColor(.white)
        }
    }
}

private struct VideoContentView: View {
    @ObservedObject var viewModel: PlayerViewModel
    @State private var sliderValue: Double = 0

    var body: some View {
        GeometryReader { _ in
            Color.black
                .overlay(
                    VStack {
                        Spacer()

                        VStack(spacing: 4) {
                            Slider(
                                value: $sliderValue,
                                in: 0...max(viewModel.duration, 1),
                                step: 0.01
                            ) { editing in
                                if !editing {
                                    viewModel.seek(to: sliderValue)
                                }
                            }

                            HStack {
                                Text(viewModel.formattedCurrentTime)
                                    .foregroundColor(.white)

                                Spacer()

                                Text(viewModel.formattedDuration)
                                    .foregroundColor(.white)
                            }
                            .font(.caption)
                        }
                        .padding()
                    }
                )
        }
    }
}

private struct ControlsOverlayView: View {
    @ObservedObject var viewModel: PlayerViewModel

    var body: some View {
        VStack {
            Spacer()

            HStack(spacing: 32) {
                Button(action: {
                    viewModel.seek(to: viewModel.currentTime - 10)
                }) {
                    Image(systemName: "gobackward.10")
                        .font(.title2)
                        .foregroundColor(.white)
                }
                .buttonStyle(RippleButtonStyle())

                Button(action: {
                    if viewModel.isPlaying {
                        viewModel.pause()
                    } else {
                        viewModel.play()
                    }
                }) {
                    Image(systemName: viewModel.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.white)
                }
                .buttonStyle(RippleButtonStyle())

                Button(action: {
                    viewModel.seek(to: viewModel.currentTime + 10)
                }) {
                    Image(systemName: "goforward.10")
                        .font(.title2)
                        .foregroundColor(.white)
                }
                .buttonStyle(RippleButtonStyle())
            }
            .padding(.bottom, 50)
        }
    }
}

private struct SeekingView: View {
    @ObservedObject var viewModel: PlayerViewModel

    var body: some View {
        ZStack {
            Color.black.opacity(0.5)

            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .white))
        }
    }
}

private struct ErrorPlaceholderView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundColor(.orange)

            Text(message)
                .multilineTextAlignment(.center)
                .foregroundColor(.white)
                .font(.body)

            Button(action: onRetry) {
                Text("重试")
                    .font(.headline)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 12)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
        }
        .padding()
    }
}

// MARK: - Button Style

struct RippleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(8)
            .background(
                Circle()
                    .fill(Color.white.opacity(configuration.isPressed ? 0.3 : 0.1))
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}