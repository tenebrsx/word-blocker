# WordBlocker for Linux 🐧🛡️

The Linux version of WordBlocker. It runs in the background and erases blocked words the moment you type them, in any app.

It reads the keyboard directly (evdev) and sends backspaces through a virtual keyboard (uinput), so it works on **both X11 and Wayland** (GNOME, KDE, Sway, Hyprland…).

**[Download WordBlocker-linux.tar.gz](https://github.com/tenebrsx/word-blocker/releases/latest/download/WordBlocker-linux.tar.gz)**

## Install
```bash
tar -xzf WordBlocker-linux.tar.gz && cd WordBlocker-linux
./install.sh
```
Then **log out and back in once** so your user can read the keyboard. It starts automatically on login.
Supports Debian/Ubuntu, Fedora and Arch (other distros: install `python3-evdev` and `notify-send` yourself).

## Use
```bash
wordblocker add secret --note "Stay focused!"   # block a word (note shows as a notification)
wordblocker add "bad word"                     # phrases work too
wordblocker allow password                     # exception that never gets blocked
wordblocker list
wordblocker remove secret
wordblocker test "my s3cr3t plan"              # check without typing
```
Changes apply instantly, no restart needed. The list lives in `~/.config/wordblocker/config.json`.

## What it catches
Same engine as the Mac app: exact words, leetspeak (`b4d`), stretched letters (`b444aad`), punctuation tricks (`b.a.d`), lookalike letters (Cyrillic `а`), and typos or swapped letters on longer words (`sceret`). Exceptions such as `badger` stop false positives.

## Limits
- Tracks the US keyboard layout; other layouts may miss some symbols.
- No settings window or tray icon yet. It's managed from the terminal.
- Pausing: `systemctl --user stop wordblocker` (start again with `start`).

## Uninstall
```bash
./uninstall.sh
```

## Tests
```bash
python3 -m pytest tests   # or: python3 tests/test_engine.py-style runner
```
