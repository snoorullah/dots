#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""launcher_recents.py load | add <json> | forget: what the launcher's All mode shows for an empty query.

State: $DOTS_LAUNCHER_STATE or ~/.local/state/dots-launcher/recents.json (0600), newest first, 50 kept.
An entry is a snapshot {p, key, title, sub, icon, q, ts}; it never carries a preview body. `add` refuses
anything that says "sensitive" so a provider that handles private text cannot leak into Recents even by
mistake. `load` prints {"rows": [...]} with at most 8 entries.
"""
import json
import os
import sys
import tempfile
import time

KEEP, SHOW = 50, 8


def path():
    d = os.environ.get("DOTS_LAUNCHER_STATE") or os.path.join(os.path.expanduser("~"), ".local", "state", "dots-launcher")
    return os.path.join(d, "recents.json")


def read():
    try:
        with open(path(), encoding="utf-8") as f:
            v = json.load(f)
        return v if isinstance(v, list) else []
    except (OSError, ValueError):
        return []


def write(items):
    p = path()
    os.makedirs(os.path.dirname(p), exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(p), prefix=".tmp-")
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        json.dump(items, f, ensure_ascii=False)
    os.chmod(tmp, 0o600)
    os.replace(tmp, p)


def add(raw):
    try:
        e = json.loads(raw)
    except ValueError:
        return {"rows": [], "error": "bad json"}
    if not isinstance(e, dict) or e.get("sensitive") or not e.get("p") or not e.get("key"):
        return {"rows": []}
    keep = {k: str(e.get(k, ""))[:300] for k in ("p", "key", "title", "sub", "icon", "q")}
    keep["ts"] = int(time.time())
    items = [i for i in read() if not (i.get("p") == keep["p"] and i.get("key") == keep["key"])]
    write(([keep] + items)[:KEEP])
    return {"rows": []}


def load():
    return {"rows": read()[:SHOW]}


def main(argv):
    v = argv[0] if argv else ""
    if v == "add" and len(argv) > 1:
        out = add(argv[1])
    elif v == "forget":
        write([])
        out = {"rows": []}
    else:
        out = load()
    print(json.dumps(out))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
