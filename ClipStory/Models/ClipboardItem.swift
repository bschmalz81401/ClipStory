import AppKit
import Foundation

// MARK: - Content

enum ClipboardContent: Codable {
    case text(String, rtf: Data?)
    case image(Data) // PNG representation

    private enum CodingKeys: String, CodingKey { case type, text, rtf, imageData }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let s, let rtf):
            try c.encode("text", forKey: .type)
            try c.encode(s, forKey: .text)
            try c.encodeIfPresent(rtf, forKey: .rtf)
        case .image(let d):
            try c.encode("image", forKey: .type)
            try c.encode(d, forKey: .imageData)
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "text":
            let s   = try c.decode(String.self, forKey: .text)
            let rtf = try c.decodeIfPresent(Data.self, forKey: .rtf)
            self = .text(s, rtf: rtf)
        case "image":
            let d = try c.decode(Data.self, forKey: .imageData)
            self = .image(d)
        default:
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Unknown type"))
        }
    }
}

// MARK: - Item

struct ClipboardItem: Identifiable, Codable, Equatable {
    let id: UUID
    let content: ClipboardContent
    let timestamp: Date

    init(content: ClipboardContent) {
        self.id        = UUID()
        self.content   = content
        self.timestamp = Date()
    }

    // Plain-text snippet for display.
    var displayText: String {
        switch content {
        case .text(let s, _):
            let cleaned = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return String(cleaned.prefix(200))
        case .image:
            return ""
        }
    }

    // Thumbnail for image items; nil for text items.
    var thumbnail: NSImage? {
        guard case .image(let data) = content else { return nil }
        return NSImage(data: data)
    }

    static func == (lhs: ClipboardItem, rhs: ClipboardItem) -> Bool {
        lhs.id == rhs.id
    }

    // Used for deduplication — same content, different IDs.
    func hasSameContent(as other: ClipboardItem) -> Bool {
        switch (content, other.content) {
        case (.text(let a, _), .text(let b, _)): return a == b
        case (.image(let a), .image(let b)):      return a == b
        default: return false
        }
    }
}
