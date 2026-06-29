import SwiftUI
import AppKit

// MARK: - Key-capture shim (macOS 13 compatible)
// onKeyPress is macOS 14+. We use an NSViewRepresentable overlay that forwards
// raw NSEvents to the SwiftUI layer via a callback.

private struct KeyCaptureView: NSViewRepresentable {
    let onEvent: (NSEvent) -> Bool

    func makeNSView(context: Context) -> _KeyView {
        let v = _KeyView()
        v.onEvent = onEvent
        return v
    }
    func updateNSView(_ nsView: _KeyView, context: Context) {
        nsView.onEvent = onEvent
    }
}

final class _KeyView: NSView {
    var onEvent: ((NSEvent) -> Bool)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if onEvent?(event) != true {
            super.keyDown(with: event)
        }
    }
}

// MARK: - Picker

struct PickerView: View {

    @ObservedObject var monitor: ClipboardMonitor
    let onSelect:  (ClipboardItem) -> Void
    let onDismiss: () -> Void

    @State private var selectedID: UUID?
    @State private var searchText  = ""

    private var filtered: [ClipboardItem] {
        guard !searchText.isEmpty else { return monitor.history }
        return monitor.history.filter {
            switch $0.content {
            case .text(let s, _): return s.localizedCaseInsensitiveContains(searchText)
            case .image:          return "image".contains(searchText.lowercased())
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if filtered.isEmpty {
                emptyState
            } else {
                itemList
            }
        }
        .frame(width: 360, height: 480)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        // Key capture overlay — sits behind the list so it receives events when
        // the text field is not focused.
        .background(
            KeyCaptureView { [self] event in
                handleKey(event)
            }
        )
        .onAppear {
            selectedID = filtered.first?.id
        }
    }

    // MARK: - Keyboard

    private func handleKey(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 53: // Escape
            onDismiss()
            return true
        case 36, 76: // Return / Enter
            commitSelected()
            return true
        case 125: // Down arrow
            moveSelection(by: +1)
            return true
        case 126: // Up arrow
            moveSelection(by: -1)
            return true
        default:
            return false
        }
    }

    // MARK: - Subviews

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "clipboard")
                .foregroundStyle(.secondary)
            TextField("Search clipboard history…", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var itemList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filtered) { item in
                        PickerRow(item: item, isSelected: item.id == selectedID)
                            .id(item.id)
                            .contentShape(Rectangle())
                            .onTapGesture { onSelect(item) }
                    }
                }
            }
            .onChange(of: selectedID) { newID in
                if let id = newID {
                    withAnimation(.none) { proxy.scrollTo(id, anchor: .center) }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(searchText.isEmpty ? "No clipboard history yet" : "No matches")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private func moveSelection(by delta: Int) {
        guard !filtered.isEmpty else { return }
        let ids = filtered.map(\.id)
        if let current = selectedID, let idx = ids.firstIndex(of: current) {
            selectedID = ids[(idx + delta + ids.count) % ids.count]
        } else {
            selectedID = ids.first
        }
    }

    private func commitSelected() {
        guard let id = selectedID,
              let item = filtered.first(where: { $0.id == id }) else { return }
        onSelect(item)
    }
}

// MARK: - Row

struct PickerRow: View {

    let item: ClipboardItem
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            icon
            content
            Spacer()
            timestamp
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
    }

    @ViewBuilder
    private var icon: some View {
        switch item.content {
        case .text:
            Image(systemName: "doc.text")
                .foregroundStyle(.secondary)
                .frame(width: 20)
        case .image:
            Image(systemName: "photo")
                .foregroundStyle(.secondary)
                .frame(width: 20)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch item.content {
        case .text(let s, _):
            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
            Text(trimmed.isEmpty ? "(empty)" : trimmed)
                .lineLimit(2)
                .font(.system(size: 13))
                .frame(maxWidth: .infinity, alignment: .leading)
        case .image(let data):
            HStack(spacing: 8) {
                if let img = NSImage(data: data) {
                    Image(nsImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 48, height: 36)
                        .clipped()
                        .cornerRadius(4)
                }
                Text("Image")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var timestamp: some View {
        Text(item.timestamp, style: .relative)
            .font(.caption2)
            .foregroundStyle(.tertiary)
    }
}
