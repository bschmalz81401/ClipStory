import AppKit
import Combine

// Polls NSPasteboard.general every 0.3 s by comparing changeCount.
// macOS does not expose a clipboard-change notification, so polling is the
// standard approach used by all clipboard managers on the platform.

final class ClipboardMonitor: ObservableObject {

    static let shared = ClipboardMonitor()

    @Published private(set) var history: [ClipboardItem] = []

    private let settings    = AppSettings.shared
    private let persistence = PersistenceManager.shared
    private var timer: Timer?
    // The changeCount value seen on the previous poll cycle.
    private var lastChangeCount: Int = -1

    // MARK: - Lifecycle

    private init() {
        if settings.persistHistory {
            history = persistence.load()
        }
    }

    func start() {
        // Snapshot the current pasteboard changeCount so we don't re-capture
        // whatever was on the board before the app launched.
        lastChangeCount = NSPasteboard.general.changeCount

        // 0.3 s is responsive enough to feel instant while keeping CPU negligible.
        timer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            self?.poll()
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Polling

    private func poll() {
        let pb = NSPasteboard.general
        let current = pb.changeCount

        // changeCount increments each time the pasteboard contents change.
        guard current != lastChangeCount else { return }
        lastChangeCount = current

        guard let item = readPasteboard(pb) else { return }

        // Skip consecutive duplicates (e.g. the app wrote the same text back
        // to the pasteboard when the user picked from the history).
        if let latest = history.first, latest.hasSameContent(as: item) { return }

        addItem(item)
    }

    // Reads the highest-fidelity content available on the pasteboard.
    private func readPasteboard(_ pb: NSPasteboard) -> ClipboardItem? {
        // Images take priority over text so a copied image is stored correctly.
        if pb.canReadItem(withDataConformingToTypes: [NSPasteboard.PasteboardType.tiff.rawValue,
                                                      NSPasteboard.PasteboardType.png.rawValue]) {
            if let image = NSImage(pasteboard: pb),
               let tiffData = image.tiffRepresentation,
               let bitmapRep = NSBitmapImageRep(data: tiffData),
               let pngData   = bitmapRep.representation(using: .png, properties: [:]) {
                return ClipboardItem(content: .image(pngData))
            }
        }

        // Try rich text (RTF) first, fall back to plain text.
        if let rtfData = pb.data(forType: .rtf),
           let attrStr = NSAttributedString(rtf: rtfData, documentAttributes: nil) {
            let plain = attrStr.string
            guard !plain.isEmpty else { return nil }
            return ClipboardItem(content: .text(plain, rtf: rtfData))
        }

        if let text = pb.string(forType: .string), !text.isEmpty {
            return ClipboardItem(content: .text(text, rtf: nil))
        }

        return nil
    }

    // MARK: - History management

    private func addItem(_ item: ClipboardItem) {
        var updated = history
        updated.insert(item, at: 0)
        // Enforce the rolling limit.
        if updated.count > settings.historyLimit {
            updated = Array(updated.prefix(settings.historyLimit))
        }
        history = updated
        if settings.persistHistory {
            persistence.save(history)
        }
    }

    // Places an item back on the pasteboard for pasting into the target app.
    func putOnPasteboard(_ item: ClipboardItem) {
        let pb = NSPasteboard.general
        pb.clearContents()
        switch item.content {
        case .text(let str, let rtf):
            if let rtf = rtf {
                pb.setData(rtf, forType: .rtf)
            }
            pb.setString(str, forType: .string)
        case .image(let data):
            pb.setData(data, forType: .png)
        }
        // Snapshot the new changeCount so the polling loop does not add this
        // write back to the history as a new entry.
        lastChangeCount = pb.changeCount
    }

    func clearHistory() {
        history = []
        persistence.clear()
    }
}
