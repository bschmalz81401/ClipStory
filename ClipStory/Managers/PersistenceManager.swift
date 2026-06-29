import Foundation

// Saves and loads clipboard history to ~/Library/Application Support/ClipStory/.
// Images can be large; JSON with base64 image data works fine up to a few hundred
// items, but could be swapped for a SQLite/Core Data store for scale.

final class PersistenceManager {

    static let shared = PersistenceManager()

    private let fileURL: URL

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = support.appendingPathComponent("ClipStory", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("history.json")
    }

    func save(_ items: [ClipboardItem]) {
        do {
            let data = try JSONEncoder().encode(items)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("ClipStory: failed to save history — \(error)")
        }
    }

    func load() -> [ClipboardItem] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        do {
            return try JSONDecoder().decode([ClipboardItem].self, from: data)
        } catch {
            print("ClipStory: failed to load history — \(error)")
            return []
        }
    }

    func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
