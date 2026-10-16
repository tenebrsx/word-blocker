"""Word list storage in ~/.config/wordblocker/."""
import json, os
from pathlib import Path

DIR = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "wordblocker"
FILE = DIR / "config.json"
DEFAULT = {"words": [], "exceptions": ["badger", "badge", "password", "compass"],
           "notes": {}, "fuzzy": True, "beep": False}


def load():
    if FILE.exists():
        data = json.loads(FILE.read_text())
        return {**DEFAULT, **data}
    return dict(DEFAULT)


def save(cfg):
    DIR.mkdir(parents=True, exist_ok=True)
    FILE.write_text(json.dumps(cfg, indent=2, ensure_ascii=False))
