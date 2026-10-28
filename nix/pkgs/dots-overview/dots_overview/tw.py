"""Taskwarrior through the `task` CLI, JSON only.

Every value that reaches `task` is an argv element, never a shell string, and a
description always goes after `--` so a hostile title ("+tag", "ref:x", "rc.hooks=off")
cannot be parsed as syntax. Attribute values are checked before use: a `ref` that does
not look like a ref is refused rather than quoted.

`run` is the single seam; tests replace it.
"""
import calendar
import json
import re
import subprocess
import time

REF_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9:_./#-]{0,119}$")
UUID_RE = re.compile(r"\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b")
BASE = ["task", "rc.confirmation=off", "rc.verbose=new-uuid", "rc.json.array=on", "rc.color=off", "rc.bulk=0"]


class TwError(RuntimeError):
    pass


def run(args, timeout=20):
    """Run `task <args>` and return stdout. Raises TwError on a non-zero exit."""
    try:
        p = subprocess.run(BASE + list(args), capture_output=True, text=True, timeout=timeout, stdin=subprocess.DEVNULL)
    except (OSError, subprocess.SubprocessError) as e:
        raise TwError(str(e)) from e
    if p.returncode != 0:
        raise TwError((p.stderr or p.stdout).strip()[:300])
    return p.stdout


def _date(epoch):
    return time.strftime("%Y-%m-%dT%H:%M:%S", time.gmtime(int(epoch))) + "Z"


def export(*flt):
    """`task <filter> export` -> list of dicts, with the UDAs normalised to short keys."""
    out = run(list(flt) + ["export"])
    try:
        rows = json.loads(out)
    except ValueError as e:
        raise TwError(f"export is not JSON: {e}") from e
    return [_norm(r) for r in rows]


def _epoch(s):
    if not s:
        return None
    try:
        return calendar.timegm(time.strptime(s, "%Y%m%dT%H%M%SZ"))
    except ValueError:
        return None


def _norm(r):
    r = dict(r)
    r["desc"] = r.get("description", "")
    r["ref"] = r.get("ref") or None
    r["src"] = r.get("src") or None
    r["entry_ts"] = _epoch(r.get("entry"))
    r["start_ts"] = _epoch(r.get("start"))
    r["end_ts"] = _epoch(r.get("end"))
    r["srcsync_ts"] = _epoch(r.get("srcsync"))
    return r


def valid_ref(ref):
    return bool(ref) and bool(REF_RE.match(ref))


def by_ref(ref):
    """The one task carrying `ref`, or None. More than one is an invariant breach."""
    if not valid_ref(ref):
        raise TwError(f"refusing odd ref {ref!r}")
    rows = export(f"ref.is:{ref}")
    live = [r for r in rows if r.get("status") != "deleted"]
    if len(live) > 1:
        raise TwError(f"ref {ref} matches {len(live)} tasks")
    return live[0] if live else None


def _attrs(attrs):
    out = []
    for k, v in attrs.items():
        if v is None or v == "":
            continue
        if not re.fullmatch(r"[a-z]+", k):
            raise TwError(f"bad attribute name {k!r}")
        if k in ("srcsync",):
            v = _date(v)
        if k == "ref" and not valid_ref(v):
            raise TwError(f"refusing odd ref {v!r}")
        out.append(f"{k}:{v}")
    return out


def add(desc, tags=(), **attrs):
    """Create a task and return its uuid. The description is never parsed as syntax."""
    for t in tags:
        if not re.fullmatch(r"[a-z][a-z0-9_]*", t):
            raise TwError(f"bad tag {t!r}")
    out = run(["add"] + [f"+{t}" for t in tags] + _attrs(attrs) + ["--", (desc or "untitled").strip()[:300] or "untitled"])
    m = UUID_RE.search(out)
    if not m:
        raise TwError(f"no uuid in: {out.strip()[:120]}")
    return m.group(0)


def modify(uuid, **attrs):
    run([uuid, "modify"] + _attrs(attrs))


def done(uuid, end=None, **attrs):
    """Mark done, recording the source state and sync time first when given.

    `end` (epoch) back-dates the completion to when the source finished it.
    """
    if attrs:
        modify(uuid, **attrs)
    run([uuid, "done"])
    if end:
        run([uuid, "modify", "end:" + time.strftime("%Y-%m-%dT%H:%M:%S", time.localtime(int(end)))])


def start(uuid):
    run([uuid, "start"])


def pending():
    return export("status:pending")


def completed_since(epoch):
    return export("status:completed", f"end.after:{_date(epoch)}")
