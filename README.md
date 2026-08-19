# ClipStory

A native macOS clipboard manager that works like Windows 11's Win+V clipboard history popup — but on macOS.

## Features

- **Global hotkey** `⌘⇧V` opens a floating picker panel above whatever app you're in
- **Text and image capture** — plain text, RTF, PNG/TIFF
- **Rolling history** — configurable limit (default 50), newest first, consecutive duplicates suppressed
- **Instant paste** — selecting an item puts it on the pasteboard and synthesises `⌘V` so it lands in the focused text field immediately
- **Search** — type in the picker to filter history
- **Keyboard navigation** — ↑↓ arrows to move, Return to select, Esc to dismiss
- **Persistence** — history survives app restarts (toggle off for session-only privacy mode)
- **Menu bar only** — no Dock icon (LSUIElement)
- **Launch at login** — via `SMAppService` (macOS 13+)

## Requirements

- macOS 13 (Ventura) or later
- Xcode 15+

## Building

```bash
# Generate the Xcode project (needed after cloning or editing project.yml)
xcodegen generate

# Build from the command line
xcodebuild -scheme ClipStory -configuration Debug build

# Or open in Xcode
open ClipStory.xcodeproj
```

## Release builds & signing

Release builds are configured for **Developer ID** distribution (signed outside the
Mac App Store, ready for notarisation):

| Setting | Value |
|---------|-------|
| `CODE_SIGN_IDENTITY` | `Developer ID Application` |
| `CODE_SIGN_STYLE` | `Manual` |
| `DEVELOPMENT_TEAM` | `D9CX25ADWQ` |
| `ENABLE_HARDENED_RUNTIME` | `YES` |
| `OTHER_CODE_SIGN_FLAGS` | `--timestamp --options runtime` |
| `CODE_SIGN_INJECT_BASE_ENTITLEMENTS` (Release) | `NO` |

The last two matter for notarisation: `--timestamp` embeds a secure timestamp, and
disabling entitlement injection stops Xcode adding `com.apple.security.get-task-allow`
to the Release binary. The entitlements file also pins that key to `false` explicitly.

```bash
xcodebuild -scheme ClipStory -configuration Release build
```

Verify the resulting app before submitting it:

```bash
codesign -dvv --entitlements :- /path/to/ClipStory.app
```

Expect `flags=0x10000(runtime)`, a `Timestamp=` line, the Developer ID authority
chain, and `get-task-allow` set to `<false/>`.

## First-run permissions

On first launch, ClipStory will ask you to grant **Accessibility** permission in **System Settings › Privacy & Security › Accessibility**. This is required for:

1. Synthesising the `⌘V` keystroke that pastes your chosen item into the target app
2. Global hotkey registration via Carbon `RegisterEventHotKey`

Without it, the global hotkey still shows the picker, but the synthetic paste after selection is silently dropped by macOS.

## Project layout

```
ClipStory/
├── project.yml                      # xcodegen spec — edit instead of touching .xcodeproj
├── ClipStory/
│   ├── App/
│   │   ├── ClipStoryApp.swift       # @main entry, NSApplicationDelegateAdaptor
│   │   └── AppDelegate.swift        # Status bar, menu, picker coordination
│   ├── Models/
│   │   └── ClipboardItem.swift      # Codable item model (text + RTF | image)
│   ├── Managers/
│   │   ├── AppSettings.swift        # UserDefaults-backed settings (ObservableObject)
│   │   ├── ClipboardMonitor.swift   # 0.3 s polling loop, history management
│   │   ├── HotkeyManager.swift      # Carbon RegisterEventHotKey — ONE place for the shortcut
│   │   ├── PersistenceManager.swift # JSON history in ~/Library/Application Support/ClipStory
│   │   ├── AccessibilityManager.swift  # AX permission check + Settings deep link
│   │   └── SyntheticPaste.swift     # CGEvent Cmd+V synthesis
│   ├── Views/
│   │   ├── PickerWindowController.swift  # NSPanel (.nonactivatingPanel) management
│   │   ├── PickerView.swift              # SwiftUI picker with search + keyboard nav
│   │   └── PreferencesView.swift         # Settings UI
│   ├── Resources/
│   │   └── Info.plist               # LSUIElement = true, bundle metadata
│   └── ClipStory.entitlements       # No sandbox (required for CGEvent + hotkey)
```

## Changing the hotkey

The shortcut is defined in **exactly one place**: `HotkeyManager.swift`, constants `defaultKeyCode` and `defaultModifiers`.

```swift
private static let defaultKeyCode:   UInt32 = 0x09                     // V
private static let defaultModifiers: UInt32 = UInt32(cmdKey | shiftKey) // ⌘⇧
```

Change those two values and rebuild.

## Entitlements & Info.plist notes

| Key | Value | Why |
|-----|-------|-----|
| `LSUIElement` | `true` | Hides Dock icon and app switcher |
| `com.apple.security.app-sandbox` | `false` | Required — sandbox blocks CGEvent synthesis and global hotkeys |
| `com.apple.security.get-task-allow` | `false` | Debugger-attach entitlement. Xcode injects it in dev builds; notarisation rejects any binary that has it |
| `ENABLE_HARDENED_RUNTIME` | `YES` | Required for Developer ID signing and notarisation |

## Architecture notes

### Pasteboard polling
macOS provides no `NSPasteboardDidChangeNotification`. The canonical solution is polling `NSPasteboard.general.changeCount` — this is what every clipboard manager does. At 0.3 s intervals the CPU impact is unmeasurable.

### Global hotkey
Uses Carbon `RegisterEventHotKey` / `InstallEventHandler`. This is the same API used by apps like Alfred and Raycast. It does **not** require Accessibility permission (unlike a full `CGEventTap`).

### Synthetic paste
`CGEvent(keyboardEventSource:virtualKey:keyDown:)` posted to `.cghidEventTap`. A 50 ms delay ensures the picker panel dismisses and the target app regains focus before the event fires.

### Non-activating panel
`NSPanel` with `.nonactivatingPanel` style mask appears in front of all windows without stealing focus from the text field the user was editing — exactly the Win+V behaviour.
