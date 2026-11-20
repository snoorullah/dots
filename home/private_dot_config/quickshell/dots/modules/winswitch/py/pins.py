#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Window to ticket pins for the window switcher. Local file only, never read back out of the
machine. One JSON object on stdout, exit 0.

  pins.py list | set ADDR TICKET | unset ADDR | prune ADDR... | current | ticket TEXT
"""
import json
import os
import re
import sys
from pathlib import Path


def store():
    base = os.environ.get("XDG_STATE_HOME") or str(Path(os.environ.get("HOME", "~")).expanduser() / ".local/state")
    return Path(base) / "dots-winswitch"


def write(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + ".tmp")
    tmp.write_text(text)
    os.replace(tmp, path)


def load():
    try:
        d = json.loads((store() / "pins.json").read_text())
        return {k: v for k, v in d.items() if isinstance(v, str)} if isinstance(d, dict) else {}
    except (OSError, ValueError):
        return {}


def save(d):
    write(store() / "pins.json", json.dumps(d))


ADDR = re.compile(r"0x[0-9a-f]{1,16}")
TICKET = re.compile(r"[A-Za-z0-9][A-Za-z0-9 _.-]{0,23}")


def main(argv):
    cmd, a = (argv[0], argv[1:]) if argv else ("list", [])
    if cmd == "list":
        out = {"ok": True, "pins": load()}
    elif cmd == "set" and len(a) == 2:
        if ADDR.fullmatch(a[0]) and TICKET.fullmatch(a[1]):
            d = load()
            d[a[0]] = a[1]
            save(d)
            out = {"ok": True}
        else:
            out = {"ok": False, "error": "bad address or ticket"}
    elif cmd == "unset" and len(a) == 1:
        d = load()
        d.pop(a[0], None)
        save(d)
        out = {"ok": True}
    elif cmd == "prune":
        live = set(a)
        save({k: v for k, v in load().items() if k in live})
        out = {"ok": True}
    elif cmd == "current":
        try:
            t = (store() / "ticket").read_text().strip()
        except OSError:
            t = ""
        out = {"ok": True, "ticket": t if TICKET.fullmatch(t) else ""}
    elif cmd == "ticket" and len(a) == 1:
        if TICKET.fullmatch(a[0]):
            write(store() / "ticket", a[0])
            out = {"ok": True}
        else:
            out = {"ok": False, "error": "bad ticket"}
    else:
        out = {"ok": False, "error": "usage"}
    print(json.dumps(out))


if __name__ == "__main__":
    main(sys.argv[1:])
