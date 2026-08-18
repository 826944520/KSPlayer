import KSPlayer
import SwiftUI

/// Minimal KSPlayer demo: one player, full-screen, auto-plays on appear.
/// KSPlayerLayer calls prepareToPlay() during init, so no explicit play() is needed.
struct ContentView: View {
    // Coordinator is an ObservableObject held by the representable; keep one stable
    // instance so the player layer survives SwiftUI body re-evaluations.
    private let coordinator = KSVideoPlayer.Coordinator()
    private let url = URL(string: "https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_fmp4/master.m3u8")!

    var body: some View {
        KSVideoPlayer(coordinator: coordinator, url: url, options: KSOptions())
            .ignoresSafeArea()
    }
}
