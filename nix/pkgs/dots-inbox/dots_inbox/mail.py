"""Read messages out of notmuch. Read-only: tagging goes through tag() and nothing else.

A message is a plain dict, the one shape every module uses:

    {"id": message-id, "thread": notmuch thread id, "file": path, "folder": "INBOX",
     "from": "Name <addr>", "from_addr": "addr", "to": [...addrs], "cc": [...addrs],
     "subject": str, "date": unix, "tags": set,
     "headers": {lower-case name: value} for the few that matter (list-id,
                 x-github-reason, in-reply-to, references, auto-submitted, precedence,
                 x-mailer, x-ms-exchange-*)}

Bodies are read only on request (body()), and only by code that needs them.
"""
import email
import email.policy
import email.utils
import json
import subprocess
from pathlib import Path

from . import config

HEADERS = ("list-id", "x-github-reason", "x-github-sender", "in-reply-to", "references",
           "auto-submitted", "precedence", "x-auto-response-suppress", "message-id")


def _nm(*args, input=None):
    env = {"NOTMUCH_CONFIG": str(config.XDG_CONFIG / "notmuch/default/config")}
    import os
    r = subprocess.run(["notmuch", *args], capture_output=True, text=True, input=input,
                       env={**os.environ, **env}, timeout=300)
    if r.returncode != 0:
        raise RuntimeError(f"notmuch {args[0]}: {r.stderr.strip()[:200]}")
    return r.stdout


def _addrs(v):
    return [a.lower() for _, a in email.utils.getaddresses([v or ""]) if a]


def _headers(path):
    try:
        with open(path, "rb") as fh:
            msg = email.message_from_binary_file(fh, policy=email.policy.compat32,
                                                 _class=email.message.Message)
    except OSError:
        return {}, None
    h = {k: str(msg.get(k, "")) for k in HEADERS if msg.get(k) is not None}
    return h, msg


def messages(query, limit=None):
    """Messages matching a notmuch query, newest first."""
    args = ["search", "--format=json", "--output=messages", "--sort=newest-first"]
    if limit:
        args.append(f"--limit={limit}")
    ids = json.loads(_nm(*args, query) or "[]")
    return [m for m in (get(i) for i in ids) if m]


def get(mid):
    out = json.loads(_nm("show", "--format=json", "--body=false", "--entire-thread=false",
                         f"id:{mid}") or "[]")
    node = _first(out)
    if not node:
        return None
    hd = node.get("headers", {})
    path = (node.get("filename") or [None])[0]
    extra, _ = _headers(path) if path else ({}, None)
    frm = hd.get("From", "")
    folder = ""
    if path:
        rel = Path(path).relative_to(config.BOX) if str(path).startswith(str(config.BOX)) else Path(path)
        folder = str(rel.parent.parent) if rel.parent.name in ("cur", "new", "tmp") else str(rel.parent)
    thread = _nm("search", "--output=threads", f"id:{mid}").strip().removeprefix("thread:")
    return {"id": mid, "thread": thread, "file": path, "folder": folder,
            "from": frm, "from_addr": (_addrs(frm) or [""])[0],
            "to": _addrs(hd.get("To")), "cc": _addrs(hd.get("Cc")),
            "subject": hd.get("Subject", ""), "date": int(node.get("timestamp") or 0),
            "tags": set(node.get("tags") or []), "headers": extra}


def _first(tree):
    """The first message node in notmuch's nested thread JSON."""
    stack = [tree]
    while stack:
        x = stack.pop(0)
        if isinstance(x, dict) and "id" in x and "headers" in x:
            return x
        if isinstance(x, list):
            stack[0:0] = x
    return None


def body(m, limit=20000):
    """Plain-text body, trimmed. Only for code that must read content."""
    _, msg = _headers(m["file"]) if m.get("file") else ({}, None)
    if msg is None:
        return ""
    parts = msg.walk() if msg.is_multipart() else [msg]
    for p in parts:
        if p.get_content_type() == "text/plain":
            try:
                return p.get_payload(decode=True).decode(p.get_content_charset() or "utf-8", "replace")[:limit]
            except Exception:
                continue
    for p in (msg.walk() if msg.is_multipart() else [msg]):
        if p.get_content_type() == "text/html":
            import html, re
            raw = p.get_payload(decode=True) or b""
            txt = re.sub(r"<[^>]+>", " ", raw.decode(p.get_content_charset() or "utf-8", "replace"))
            return re.sub(r"\s+", " ", html.unescape(txt))[:limit]
    return ""


def tag(mid, *changes):
    """notmuch tag +a -b -- id:MID. The single write path into the index."""
    if changes:
        _nm("tag", *changes, "--", f"id:{mid}")


def count(query):
    return int(_nm("count", query).strip() or 0)
