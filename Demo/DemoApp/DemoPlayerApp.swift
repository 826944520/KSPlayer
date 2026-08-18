import SwiftUI
import KSPlayer

@main
struct DemoPlayerApp: App {
    @StateObject private var history = HistoryStore()
    @StateObject private var settings = AppSettings()

    init() {
        // Remote HTTP/JSON logging to http://192.168.10.15:7777 (batch POST /log,
        // crash beacon POST /crash). .verbose captures lifecycle + decode +
        // FFmpeg warnings; .debug/.trace are filtered out at this density.
        RemoteLog.configure(level: .verbose)
        KSLog(level: .info, "[app] DemoPlayerApp launched")
    }

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(history)
                .environmentObject(settings)
        }
    }
}
