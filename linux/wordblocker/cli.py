"""wordblocker command line: manage words and run the daemon."""
import argparse, sys
from . import config, __version__


def main(argv=None):
    p = argparse.ArgumentParser(prog="wordblocker", description="Block chosen words system-wide as you type.")
    p.add_argument("--version", action="version", version=__version__)
    sub = p.add_subparsers(dest="cmd")
    sub.add_parser("run", help="run the blocker in the foreground")
    a = sub.add_parser("add", help="block a word or phrase"); a.add_argument("word", nargs="+")
    a.add_argument("--note", help="pop-up note shown when it's typed")
    r = sub.add_parser("remove", help="unblock a word"); r.add_argument("word", nargs="+")
    x = sub.add_parser("allow", help="add an exception word"); x.add_argument("word")
    ux = sub.add_parser("disallow", help="remove an exception word"); ux.add_argument("word")
    sub.add_parser("list", help="show blocked words and exceptions")
    t = sub.add_parser("test", help="check text against your list without typing it"); t.add_argument("text", nargs="+")
    args = p.parse_args(argv)
    cfg = config.load()
    if args.cmd == "run":
        from .daemon import run; run()
    elif args.cmd == "add":
        w = " ".join(args.word).lower()
        if w not in cfg["words"]: cfg["words"].append(w)
        if args.note: cfg["notes"][w] = args.note
        config.save(cfg); print(f"Blocked “{w}”.")
    elif args.cmd == "remove":
        w = " ".join(args.word).lower()
        cfg["words"] = [x for x in cfg["words"] if x != w]; cfg["notes"].pop(w, None)
        config.save(cfg); print(f"Unblocked “{w}”.")
    elif args.cmd == "allow":
        w = args.word.lower()
        if w not in cfg["exceptions"]: cfg["exceptions"].append(w)
        config.save(cfg); print(f"Allowed “{w}”.")
    elif args.cmd == "disallow":
        cfg["exceptions"] = [x for x in cfg["exceptions"] if x != args.word.lower()]
        config.save(cfg); print(f"Removed exception “{args.word}”.")
    elif args.cmd == "list":
        print("Blocked:", ", ".join(cfg["words"]) or "(none)")
        print("Exceptions:", ", ".join(cfg["exceptions"]) or "(none)")
    elif args.cmd == "test":
        from .engine import Engine
        eng = Engine(cfg["words"], cfg["exceptions"], cfg["notes"], cfg["fuzzy"])
        text, hit = " ".join(args.text), None
        for i in range(1, len(text) + 1):
            hit = eng.match(text[:i]) or hit
            if eng.match(text[:i]): break
        print(f"Blocked: {hit[0]}" if hit else "Not blocked.")
        sys.exit(0 if hit else 1)
    else:
        p.print_help()


if __name__ == "__main__":
    main()
