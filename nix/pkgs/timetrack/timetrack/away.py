"""D7: what an away gap was -- declared on the way out, or asked on the way back.

Meetings are offline, so no local sensor can tell a meeting from a break. Only the user
can. Two paths, both ending in the same human answer:

    Super+Esc      timetrack-away-pick --declare: pick a reason, the screen locks and
                   shows it with a timer. On return the gap is answered from that pick;
                   nothing is asked.
    forgot to lock hypridle locks after 5 min idle. On return:
                     gap < MIN_GAP (3 min)    AW ingest already deducts it; nothing asked
                     gap < PROMPT_MIN (5 min) a short break (deducted) + a 4s toast
                     longer                   the same picker, in a blocking panel

Every undeclared gap is asked about, as often as it happens (the user's call, 2026-10-28,
overriding the D21 budget). With no answer the gap stays UNCONFIRMED for the batch
fallback (`timetrack backfill`). "Log out for today" ENDS the day (work.db `logout`).
Nothing is ever answered for the user: a timeout records an absence, not a choice.

Auto-classification only ever DEDUCTS. Getting a short gap wrong under-reports; it can
never put a minute into the figure that nobody evidenced.
"""
import json
import shutil
import subprocess
import sys
import time
from datetime import date, datetime

from . import config, dbs, interactive
from .backfill import aw

MIN_GAP = aw.MIN_GAP
PROMPT_MIN = 5 * 60        # matches hypridle's lock: an undeclared lock is always asked
RECENT = 5 * 60            # a return older than this was missed; the batch panel has it
SALAH_BEFORE, SALAH_AFTER = 10 * 60, 30 * 60
DECLARE_SLACK = 10 * 60    # a declaration this long before the user left still counts
AUTO = "return:auto"
DECLARED = "manual:declared"
STATE = config.STATE_DIR / "away-state.json"
INTENT = config.STATE_DIR / "away-intent.json"
PRAYER_TIMES = config.HOME / ".config/adhd/prayer-times.conf"
POLL = 15
DINNER_FROM = 17           # a long break from 17:00 on is dinner, not lunch (WORK_V2)

# picker key -> (lock-screen label, deduction category; None = meeting = worked time)
CHOICES = {
    "salah":    ("Salah", "salah"),
    "washroom": ("Washroom / pantry", "washroom"),
    "walk":     ("Walk / short break", "misc"),
    "meal":     ("Lunch / long break", "lunch"),
    "meeting":  ("Meeting", None),
    "logout":   ("Logged out for today", "misc"),
}


def category(key, at):
    cat = CHOICES[key][1]
    if cat == "lunch" and datetime.fromtimestamp(at).hour >= DINNER_FROM:
        return "dinner"
    return cat


def _ts(s):
    return datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()


def last_return(events, now):
    """(gap_start, gap_end) if the user has just come back from a long enough absence.

    `events` is the afk bucket newest first. The newest event must be not-afk and recent;
    the one before it afk. ActivityWatch backdates an afk event to the last input, so its
    start is when the user actually left.
    """
    if len(events) < 2:
        return None
    cur, prev = events[0], events[1]
    if (cur.get("data") or {}).get("status") != "not-afk":
        return None
    if (prev.get("data") or {}).get("status") != "afk":
        return None
    back = _ts(cur["timestamp"])
    left = _ts(prev["timestamp"])
    if now - back > RECENT or back - left < MIN_GAP:
        return None
    return int(left), int(back)


def salah_hint(g0, g1, path=None):
    """The prayer whose iqamah falls inside [g0, g1] (with margins), or None."""
    path = path or PRAYER_TIMES
    try:
        lines = path.read_text().splitlines()
    except OSError:
        return None
    day = datetime.fromtimestamp(g0).date()
    for line in lines:
        parts = line.split("#", 1)[0].split()
        if len(parts) < 2 or ":" not in parts[1]:
            continue
        hh, mm = (int(x) for x in parts[1].split(":"))
        iq = datetime.combine(day, datetime.min.time()).replace(hour=hh, minute=mm).timestamp()
        if g0 <= iq + SALAH_AFTER and g1 >= iq - SALAH_BEFORE:
            return parts[0]
    return None


def _read(path, default):
    try:
        return json.loads(path.read_text())
    except (OSError, ValueError):
        return default


def _write(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps(data))
    tmp.replace(path)


def _state():
    return _read(STATE, {"handled": 0, "prompts": []})


def declare(key, now=None):
    """Super+Esc: record why the user is leaving. The lock screen reads this file."""
    if key not in CHOICES:
        raise SystemExit(f"timetrack: unknown away reason {key!r}")
    now = int(now or time.time())
    label = CHOICES[key][0]
    if key == "salah" and (p := salah_hint(now, now)):
        label = f"Salah · {p}"
    _write(INTENT, {"key": key, "label": label, "since": now})
    if key == "logout":
        with dbs.open_work() as conn:
            conn.execute("INSERT OR IGNORE INTO logout(ts_unix, provenance) VALUES(?, ?)",
                         (now, DECLARED))
            conn.commit()
        _brief()
    return label


def _brief():
    """Write the day's brief on the way out. Detached and best effort: it must never hold up the picker."""
    if exe := shutil.which("dots-overview"):
        try:
            subprocess.Popen([exe, "report", "--reason", "logout"], stdin=subprocess.DEVNULL,
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
        except OSError:
            pass


def take_intent(g0, g1):
    """The declaration covering a gap that began at g0, consumed so it answers once."""
    it = _read(INTENT, None)
    if not it or it.get("key") not in CHOICES:
        return None
    if not (g0 - DECLARE_SLACK <= it.get("since", 0) <= g1):
        return None
    INTENT.unlink(missing_ok=True)
    return it["key"]


def find_gap(conn, g0, g1):
    """The unconfirmed deduction that best matches [g0, g1), or None."""
    best, best_ov = None, 0
    for r in conn.execute(
            "SELECT id, start_unix, end_unix, minutes FROM deduction"
            " WHERE confirmed = 0 AND start_unix < ? AND end_unix > ?", (g1, g0)):
        ov = min(r["end_unix"], g1) - max(r["start_unix"], g0)
        if ov > best_ov:
            best, best_ov = dict(r), ov
    # half the gap at least, so a neighbouring gap is never answered by mistake
    return best if best and best_ov >= 0.5 * (g1 - g0) else None


def _toast(body):
    try:
        subprocess.Popen(["notify-send", "-a", "timetrack", "-t", "4000", "Away", body],
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except OSError:
        pass


def _clock(t):
    return datetime.fromtimestamp(t).strftime("%H:%M")


def _answer(g0, g1, key, provenance=interactive.PROVENANCE):
    with dbs.open_work() as conn:
        gap = find_gap(conn, g0, g1)
        if not gap:
            return False
        interactive.answer_gap(conn, gap["id"], category(key, g0), provenance=provenance)
        conn.commit()
    return True


def handle(g0, g1, now, launch=None):
    """Classify or ask about one return. Returns what happened, for the log and tests."""
    with dbs.open_work() as conn:
        aw.write(conn, refresh_day=date.today().isoformat())
    mins = round((g1 - g0) / 60)

    if key := take_intent(g0, g1):
        if key == "logout":
            return "declared:logout"     # the day ended at the logout; no gap to answer
        return f"declared:{key}" if _answer(g0, g1, key, DECLARED) else "no-gap"

    if g1 - g0 < PROMPT_MIN:
        if not _answer(g0, g1, "walk", AUTO):
            return "no-gap"
        _toast(f"{mins} min away · counted as a short break")
        return "auto"

    with dbs.open_work(readonly=True) as conn:
        if not find_gap(conn, g0, g1):
            return "no-gap"
    st = _state()
    if config.panic():
        _toast(f"{mins} min away ({_clock(g0)}–{_clock(g1)}) · answer later: timetrack backfill")
        return "deferred"
    st["prompts"] = [t for t in st["prompts"] if now - t < 86400] + [now]
    _write(STATE, st)

    title = f"Away {_clock(g0)}–{_clock(g1)} ({mins} min)"
    # absolute paths: the panel runs under the user manager, whose PATH may lack both
    bin_ = config.HOME / ".local/bin"
    cmd = [str(bin_ / "timetrack-panel"), f"away-{g1}", title, "--",
           str(bin_ / "timetrack-away-pick"), "--ask"]
    launch = launch or (lambda c: subprocess.run(c, capture_output=True, text=True, timeout=700))
    try:
        res = launch(cmd)
    except (OSError, subprocess.SubprocessError):
        return "panel-failed"
    key = (res.stdout or "").strip().splitlines()[-1:] if res.returncode == 0 else []
    if not key or key[0] not in CHOICES:
        return "unanswered"      # the panel spooled timeout/dismissal itself
    # re-found inside _answer: an hourly refresh may have re-numbered the gap meanwhile
    return f"answered:{key[0]}" if _answer(g0, g1, key[0]) else "no-gap"


def prayer_now(now=None):
    now = int(now or time.time())
    return salah_hint(now, now) or ""


def watch():
    """Poll the afk bucket; handle each return once."""
    if shutil.which("notify-send") is None:
        print("away: notify-send missing; toasts will be silent", file=sys.stderr)
    while True:
        now = time.time()
        try:
            events = aw._get(f"/buckets/{aw.bucket('afkstatus')}/events?limit=2")
            ret = last_return(events, now)
        except SystemExit as e:      # aw-server down: nothing to detect, keep watching
            print(f"away: {e}", file=sys.stderr)
            ret = None
        st = _state()
        if ret and ret[1] > st.get("handled", 0):
            st["handled"] = ret[1]
            _write(STATE, st)
            try:
                out = handle(*ret, now)
            except (Exception, SystemExit) as e:   # one bad return must not kill the watcher
                out = f"error: {e}"
            print(f"away {_clock(ret[0])}-{_clock(ret[1])}: {out}", file=sys.stderr, flush=True)
        time.sleep(POLL)
