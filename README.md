# Word Blocker for macOS 🛡️

<p align="center">
  <a href="https://github.com/tenebrsx/word-blocker/releases/latest/download/WordBlocker.dmg"><img src="https://img.shields.io/badge/Download-WordBlocker.dmg-0A84FF?style=for-the-badge&logo=apple&logoColor=white" alt="Download WordBlocker.dmg"></a>
</p>
<p align="center">
  <img src="https://img.shields.io/badge/macOS-14%2B-black?logo=apple" alt="macOS 14+">
  <img src="https://img.shields.io/badge/Apple%20Silicon-arm64-555" alt="Apple Silicon">
  <img src="https://img.shields.io/badge/Swift-native-F05138?logo=swift&logoColor=white" alt="Swift">
</p>
<p align="center"><b>On Linux?</b> See <a href="linux/">WordBlocker for Linux</a>.</p>

A native, high-performance background utility written in Swift for macOS that prevents forbidden words from being typed system-wide by automatically erasing them via synthetic backspaces upon detection.

---

## Features

- **System-Wide Protection:** Intercepts keystrokes across all macOS applications (browsers, editors, chat apps, terminals) using a low-level Quartz Event Tap (`CGEventTap`).
- **Auto-Delete Enforcement:** Once a blocked word is completed, the app immediately erases the characters using synthesized hardware-level Backspace events.
- **Obfuscation & Evasion Resilient:** Catches leetspeak (`b4d`, `w0rd`), repeated character elongations (`b444aad`, `w0000000rrrrrd`), punctuation noise (`b.a.d`, `b_4_d`), Cyrillic homoglyphs (`bаd`), and transpositions/typos (`sceret` -> `secret`).
- **Exact Origin Span Tracking:** Maintains raw physical index traces so the exact count of typed characters (e.g. 7 backspaces for `b444aad`) is deleted without leaving leftover fragments.
- **Recursive Loop Prevention:** Tags synthetic backspaces with a distinct signature (`0x57424C4B`) so the interceptor never re-processes its own actions.
- **Context-Aware Sliding Buffer:** Correctly synchronizes buffer state across manual backspaces, punctuation, Return/Enter, navigation arrow keys, and keyboard shortcuts (`Cmd+C`, `Cmd+V`, `Cmd+A`).
- **Custom Pop-Up Notes:** Assign custom written reminder notes to specific blocked words (e.g. *"Stay focused on your goals!"*). When a banned word is typed, the word is auto-deleted and a floating HUD pop-up note smoothly appears at the top-right of your screen.
- **Custom Intervention Messages:** Personalize the intervention message displayed whenever you attempt to **disable protection**, and customize the intervention alert displayed whenever you attempt to **quit** the application. Enabling protection remains completely silent without pop-ups.
- **Exceptions Allowlist (False-Positive Guard):** Dedicated **Exceptions** tab allows specifying allowed words (e.g. `badger`, `badge`, `password`, `compass`). If a blocked word is a prefix of an exception, deletion is intelligently deferred so you can finish typing without premature interruption.
- **Menu Bar Agent (`LSUIElement`):** Runs quietly in the macOS menu bar with zero Dock clutter.
- **Interactive Preferences Window:** Manage Blocked Words, Exceptions, and Custom Prompts with a built-in live test area.
- **Automatic Permission Recovery:** Detects when Accessibility permission is granted in macOS System Settings and automatically engages the event tap.

---

## System Requirements

- **Operating System:** macOS 14.0 (Sonoma) or newer.
- **Architecture:** Apple Silicon (arm64).
- **Permissions:** macOS Accessibility (TCC) trust under `System Settings > Privacy & Security > Accessibility`.

---

## Install (no coding needed)

1. **[Download WordBlocker.dmg](https://github.com/tenebrsx/word-blocker/releases/latest/download/WordBlocker.dmg)**
2. Open the DMG and drag **WordBlocker** into **Applications**.
3. First launch: the app isn't notarized by Apple yet, so **right-click WordBlocker → Open → Open**. If macOS still blocks it, go to **System Settings → Privacy & Security** and click **Open Anyway**.
4. Grant **Accessibility** permission when asked (see below). The 🛡️ icon appears in your menu bar.

> Requires macOS 14 Sonoma or newer on an Apple Silicon Mac (M1 or later).

---

## Build from Source

### 1. Build the App Bundle
```bash
make build
```
This compiles the Swift sources and produces `build/WordBlocker.app` signed with an ad-hoc identity.

### 2. Run the App
```bash
make run
```
Or open the built app bundle directly:
```bash
open build/WordBlocker.app
```

### 3. Run Automated Engine Tests
```bash
make test
```

---

## Granting Accessibility Permissions

Because Word Blocker monitors system-wide keystrokes to detect blocked words:

1. On first launch, the app will show the **Preferences** window highlighting `⚠️ Accessibility Permission Missing`.
2. Click **Grant Permission** (or navigate to `System Settings > Privacy & Security > Accessibility`).
3. Toggle the switch for **Word Blocker** to ON.
4. Word Blocker will automatically detect the permission grant in real time and activate protection (the menu bar icon turns to 🛡️).

---

## Project Structure

```
word-blocker/
├── Makefile                          # Build, run, and test shortcuts
├── build.sh                          # App compilation and bundle creation script
├── vfs.yaml                          # VFS overlay to prevent SDK modulemap collisions
├── Resources/
│   └── Info.plist                    # Bundle metadata (LSUIElement = true)
├── Sources/
│   ├── Main.swift                    # App entry point and lifecycle (@main)
│   ├── Core/
│   │   ├── PermissionsManager.swift  # TCC Accessibility verification and polling
│   │   ├── EventTapManager.swift     # Quartz CGEventTap listener and dispatcher
│   │   ├── WordBufferEngine.swift    # Sliding window buffer and suffix matcher
│   │   └── ActionDispatcher.swift    # Synthetic backspace injector
│   ├── Storage/
│   │   └── WordStore.swift           # UserDefaults persistence for blocked words
│   └── UI/
│       ├── MenuBarController.swift   # NSStatusItem and menu bar dropdown
│       └── SettingsWindowController.swift # Native AppKit preferences interface
└── Tests/
    └── EngineTests.swift             # Automated unit and integration tests
```

---

## How It Works Under the Hood

```
[Hardware Keystroke]
         │
         ▼
[macOS WindowServer]
         │
         ▼
[EventTapManager (CGEventTap)]
         │
         ├─► Synthetic Event? ──► [Pass through without processing]
         ├─► Command/Control? ──► [Reset Buffer & Pass through]
         ├─► Backspace?       ──► [Pop last character from Buffer]
         └─► Printable Key?   ──► [Append Unicode character to Buffer]
                                              │
                                              ▼
                                 [WordBufferEngine (Matcher)]
                                              │
                       ┌──────────────────────┴──────────────────────┐
                       │                                             │
                  [No Match]                                   [Match Found]
                       │                                             │
                       ▼                                             ▼
               [Pass Event along]                        [ActionDispatcher]
                                                         • Optional beep (NSSound.beep())
                                                         • Post N synthetic Backspaces
                                                         • Reset Buffer
```
