#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Rank window titles against a question with the LOCAL model (the `llm` CLI, Ollama). Titles
and ids only: no tickets, no profiles, no classes. A slow or failed model falls back to a fuzzy
match. It suggests, it never acts. Nothing leaves the machine.

  echo '[{"id","title","app"}]' | rank.py "which window was the spec review?"
  rank.py "question" '[{"id","title","app"}]'          (the shell passes the list as an argument)
"""
import json
import os
import re
import shutil
import subprocess
import sys

TOP = 3


def words(s):
    return [w for w in re.findall(r"[a-z0-9]+", s.lower()) if len(w) > 1]


def fuzzy(q, wins):
    qw = set(words(q))
    scored = []
    for w in wins:
        tw = set(words(w.get("title", "") + " " + w.get("app", "")))
        hits = len(qw & tw) + sum(0.5 for a in qw for b in tw if a != b and (a in b or b in a))
        if hits > 0:
            scored.append((-hits, w["id"]))
    scored.sort()
    return [i for _, i in scored[:TOP]]


def model(q, wins, timeout):
    exe = shutil.which("llm")
    if not exe:
        return []
    lines = "\n".join("%s: %s" % (w["id"], w.get("title", "")) for w in wins)
    prompt = ("Window titles, one per line as `id: title`:\n%s\n\nQuestion: %s\n"
              "Answer with at most %d ids from the list, best first, comma separated, nothing else."
              % (lines, q, TOP))
    try:
        r = subprocess.run([exe, prompt], capture_output=True, text=True, timeout=timeout)
    except (OSError, subprocess.SubprocessError):
        return []
    if r.returncode != 0:
        return []
    known = {w["id"] for w in wins}
    out = []
    for tok in re.findall(r"[A-Za-z0-9_-]+", r.stdout):
        if tok in known and tok not in out:
            out.append(tok)
    return out[:TOP]


def main(argv):
    q = argv[0] if argv else ""
    try:
        raw = argv[1] if len(argv) > 1 else sys.stdin.read()
        wins = [w for w in json.loads(raw) if isinstance(w, dict) and "id" in w]
    except ValueError:
        wins = []
    timeout = float(os.environ.get("DOTS_RANK_TIMEOUT", "1.5"))
    ids = model(q, wins, timeout) if q and wins else []
    via = "model"
    if not ids:
        via, ids = "fuzzy", fuzzy(q, wins)
    print(json.dumps({"ok": True, "via": via, "ids": ids}))


if __name__ == "__main__":
    main(sys.argv[1:])
