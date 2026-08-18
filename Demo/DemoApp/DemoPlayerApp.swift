import SwiftUI

@main
struct DemoPlayerApp: App {
    @StateObject private var history = HistoryStore()
    @StateObject private var settings = AppSettings()

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(history)
                .environmentObject(settings)
        }
    }
}
