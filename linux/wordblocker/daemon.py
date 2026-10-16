"""Background daemon: reads keyboards via evdev and erases blocked words via uinput.

Works on X11 and Wayland because it sits below the display server.
Needs read access to /dev/input/event* and write access to /dev/uinput
(the installer adds a udev rule and the 'input' group for this).
"""
import os, select, subprocess, time
from . import config
from .engine import Engine

try:
    import evdev
    from evdev import ecodes as e
except ImportError:  # pragma: no cover
    raise SystemExit("python3-evdev is required: sudo apt install python3-evdev  (or pip install evdev)")

MAX_BUF = 64
LETTERS = {getattr(e, f"KEY_{c.upper()}"): c for c in "abcdefghijklmnopqrstuvwxyz"}
DIGITS = {getattr(e, f"KEY_{i}"): str(i) for i in range(10)}
SHIFT_DIGITS = dict(zip("1234567890", "!@#$%^&*()"))
PUNCT = {e.KEY_MINUS: ("-", "_"), e.KEY_EQUAL: ("=", "+"), e.KEY_DOT: (".", ">"),
         e.KEY_COMMA: (",", "<"), e.KEY_SLASH: ("/", "?"), e.KEY_SEMICOLON: (";", ":"),
         e.KEY_APOSTROPHE: ("'", '"'), e.KEY_BACKSLASH: ("\\", "|"),
         e.KEY_LEFTBRACE: ("[", "{"), e.KEY_RIGHTBRACE: ("]", "}"), e.KEY_GRAVE: ("`", "~")}
RESET_KEYS = {e.KEY_ENTER, e.KEY_KPENTER, e.KEY_TAB, e.KEY_ESC, e.KEY_UP, e.KEY_DOWN,
              e.KEY_LEFT, e.KEY_RIGHT, e.KEY_HOME, e.KEY_END, e.KEY_PAGEUP, e.KEY_PAGEDOWN}
SHIFTS = {e.KEY_LEFTSHIFT, e.KEY_RIGHTSHIFT}
MODS = {e.KEY_LEFTCTRL, e.KEY_RIGHTCTRL, e.KEY_LEFTALT, e.KEY_RIGHTALT,
        e.KEY_LEFTMETA, e.KEY_RIGHTMETA}


def keyboards():
    devs = []
    for path in evdev.list_devices():
        d = evdev.InputDevice(path)
        caps = d.capabilities().get(e.EV_KEY, [])
        if e.KEY_A in caps and e.KEY_SPACE in caps and "wordblocker" not in d.name.lower():
            devs.append(d)
    return devs


def notify(word, note):
    msg = note or f"“{word}” is blocked."
    try:
        subprocess.Popen(["notify-send", "-a", "WordBlocker", "🛡️ WordBlocker", msg],
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except FileNotFoundError:
        pass


def run():
    cfg = config.load()
    engine = Engine(cfg["words"], cfg["exceptions"], cfg["notes"], cfg["fuzzy"])
    mtime = config.FILE.stat().st_mtime if config.FILE.exists() else 0
    devs = keyboards()
    if not devs:
        raise SystemExit("No keyboards found. Is your user in the 'input' group? (log out and back in after install)")
    ui = evdev.UInput({e.EV_KEY: [e.KEY_BACKSPACE]}, name="wordblocker-virtual")
    print(f"WordBlocker running on {len(devs)} keyboard(s); {len(engine.words)} blocked word(s).", flush=True)
    buf, shift, mods = "", False, set()
    fds = {d.fd: d for d in devs}
    while True:
        r, _, _ = select.select(fds, [], [], 2.0)
        if config.FILE.exists() and config.FILE.stat().st_mtime != mtime:  # live reload
            mtime = config.FILE.stat().st_mtime
            cfg = config.load()
            engine = Engine(cfg["words"], cfg["exceptions"], cfg["notes"], cfg["fuzzy"])
        for fd in r:
            try:
                events = list(fds[fd].read())
            except OSError:
                continue
            for ev in events:
                if ev.type != e.EV_KEY:
                    continue
                code, val = ev.code, ev.value
                if code in SHIFTS:
                    shift = val != 0; continue
                if code in MODS:
                    (mods.add if val else mods.discard)(code); buf = ""; continue
                if val == 0:
                    continue
                if mods or code in RESET_KEYS:
                    buf = ""; continue
                if code == e.KEY_BACKSPACE:
                    buf = buf[:-1]; continue
                ch = None
                if code in LETTERS:
                    ch = LETTERS[code].upper() if shift else LETTERS[code]
                elif code in DIGITS:
                    ch = SHIFT_DIGITS[DIGITS[code]] if shift else DIGITS[code]
                elif code in PUNCT:
                    ch = PUNCT[code][1 if shift else 0]
                elif code == e.KEY_SPACE:
                    ch = " "
                if ch is None:
                    continue
                buf = (buf + ch)[-MAX_BUF:]
                hit = engine.match(buf)
                if hit:
                    word, n, note = hit
                    time.sleep(0.02)
                    for _ in range(n):
                        ui.write(e.EV_KEY, e.KEY_BACKSPACE, 1); ui.write(e.EV_KEY, e.KEY_BACKSPACE, 0)
                        ui.syn(); time.sleep(0.004)
                    buf = ""
                    notify(word, note)
