import Foundation

struct HistoryEntry: Codable, Identifiable, Equatable {
    let url: URL
    let title: String
    let playedAt: Date
    var id: String { url.absoluteString }
}

/// Recently played items, persisted to UserDefaults.
final class HistoryStore: ObservableObject {
    @Published private(set) var entries: [HistoryEntry] = []

    private static let storageKey = "KSPlayerDemoHistory"
    private static let maxEntries = 50

    init() {
        load()
    }

    func add(url: URL, title: String?) {
        let entry = HistoryEntry(url: url, title: title ?? url.lastPathComponent, playedAt: Date())
        entries.removeAll { $0.url == url }
        entries.insert(entry, at: 0)
        if entries.count > Self.maxEntries {
            entries = Array(entries.prefix(Self.maxEntries))
        }
        save()
    }

    func remove(_ entry: HistoryEntry) {
        entries.removeAll { $0 == entry }
        save()
    }

    func clear() {
        entries.removeAll()
        save()
    }

    func moveEntries(from source: IndexSet, to destination: Int) {
        entries.move(fromOffsets: source, toOffset: destination)
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode([HistoryEntry].self, from: data)
        else { return }
        entries = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }
}
