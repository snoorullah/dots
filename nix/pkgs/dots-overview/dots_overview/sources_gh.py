"""GitHub, READ ONLY.

Every call here is a search, a view or a plain GET. The `api` subcommand is never given a
method override, and no comment, review, merge or close verb appears anywhere; the tests
grep this package for them, so the guarantee that it cannot write to GitHub is checked,
not promised.

Budget: at most MAX_SEARCH search calls per slow cycle with SLEEP seconds between them,
and the whole cycle is skipped when the search quota is nearly spent.
"""
import json
import os
import subprocess
import time
from datetime import datetime

from . import atomic, config

MAX_SEARCH = 6
SLEEP = float(os.environ.get("DOTS_OVERVIEW_GH_SLEEP", 2))     # the env override exists for tests only
MIN_REMAINING = 8
FEEDBACK_DAYS = 7        # own PRs older than this are not checked for new comments
MAX_VIEWS = 8            # `gh pr view` calls per cycle for that check
FIELDS = "number,title,url,repository,state,updatedAt,createdAt,author,isPullRequest"
# Not in the search JSON: when I was asked. updatedAt is the closest GitHub time we have for it.


class GhError(RuntimeError):
    pass


def run(args, timeout=30):
    """`gh <args>` -> stdout. The single seam tests replace."""
    try:
        p = subprocess.run(["gh"] + list(args), capture_output=True, text=True, timeout=timeout,
                           stdin=subprocess.DEVNULL)
    except (OSError, subprocess.SubprocessError) as e:
        raise GhError(str(e)) from e
    if p.returncode != 0:
        raise GhError((p.stderr or p.stdout).strip()[:200])
    return p.stdout


def _json(args):
    try:
        return json.loads(run(args))
    except ValueError as e:
        raise GhError(f"not JSON: {e}") from e


def whoami():
    return run(["api", "user", "-q", ".login"]).strip()


def quota_ok():
    out = run(["api", "rate_limit", "-q", ".resources.search.remaining"]).strip()
    return int(out or 0) >= MIN_REMAINING


def ref_of(repo, number):
    return f"gh:{repo}#{number}"


def parse_ref(ref):
    """'gh:owner/repo#12' -> ('owner/repo', 12), or None."""
    if not ref or not ref.startswith("gh:") or "#" not in ref:
        return None
    repo, _, n = ref[3:].partition("#")
    if repo.count("/") != 1 or not n.isdigit():
        return None
    return repo, int(n)


def _item(r, kind, cfg):
    # repository.nameWithOwner always comes from the search JSON, never from a guess
    repo = (r.get("repository") or {}).get("nameWithOwner")
    if not repo or not r.get("number"):
        return None
    return {"ref": ref_of(repo, r["number"]), "src": "gh", "kind": kind, "repo": repo,
            "url": r.get("url"), "title": r.get("title") or "", "state": (r.get("state") or "open").lower(),
            "updatedAt": r.get("updatedAt"), "author": (r.get("author") or {}).get("login"),
            "work": cfg.is_work_repo(repo), "createdAt": r.get("createdAt"),
            "individual": False, "mention": False, "feedback": False}


def epoch(iso):
    """GitHub's 2026-10-28T00:00:00Z -> epoch seconds, or None."""
    try:
        return int(datetime.fromisoformat(str(iso).replace("Z", "+00:00")).timestamp())
    except ValueError:
        return None


def last_activity(view, me):
    """(latest by someone else, latest by me) over a PR's comments and reviews, as epochs."""
    other = mine = 0
    for c in (view.get("comments") or []) + (view.get("reviews") or []):
        ts = epoch(c.get("createdAt") or c.get("submittedAt")) or 0
        if ((c.get("author") or {}).get("login") or "").lower() == me.lower():
            mine = max(mine, ts)
        else:
            other = max(other, ts)
    return other, mine


def _previous_feedback():
    """feedback flags from the last cycle's gh-meta.json (empty when there is none)."""
    doc = atomic.read_json(config.STATE_DIR / "gh-meta.json", {}) or {}
    return {r: bool(m.get("feedback")) for r, m in (doc.get("refs") or {}).items() if isinstance(m, dict)}


def _feedback(items, cfg, now, views=MAX_VIEWS):
    """Mark my own PRs in `explicit` repos whose newest comment/review is someone else's.

    A PR whose view failed, or that is past the per-cycle cap, keeps last cycle's answer: not
    knowing is never read as "no feedback"."""
    cand = [i for i in items if i["kind"] == "pr" and cfg.attn_mode(i["ref"]) == "explicit"
            and (epoch(i["updatedAt"]) or 0) >= now - FEEDBACK_DAYS * 86400]
    if not cand:
        return
    me = whoami()
    prev = _previous_feedback()
    for it in cand[views:]:
        it["feedback"] = prev.get(it["ref"], False)
    for it in cand[:views]:
        repo, number = parse_ref(it["ref"])
        try:
            other, mine = last_activity(_json(["pr", "view", str(number), "-R", repo, "--json", "comments,reviews"]), me)
        except GhError:
            it["feedback"] = prev.get(it["ref"], False)
            continue
        mine = max(mine, epoch(it.get("createdAt")) or 0)
        it["feedback"] = other > mine


def fetch(cfg, sleep=time.sleep, now=None):
    """Five searches: issues assigned to me, PRs I authored, PRs awaiting my review (any route),
    those asked of me personally, and PRs that @mention me."""
    if not quota_ok():
        raise GhError("search quota nearly spent; skipping this cycle")
    queries = [
        ("issue", ["search", "issues", "--assignee=@me", "--state=open", "--limit", "50", "--json", FIELDS]),
        ("pr", ["search", "prs", "--author=@me", "--state=open", "--limit", "50", "--json", FIELDS]),
        ("review", ["search", "prs", "--review-requested=@me", "--state=open", "--limit", "50", "--json", FIELDS]),
        ("review", ["search", "prs", "user-review-requested:@me", "--state=open", "--limit", "50", "--json", FIELDS]),
        ("mention", ["search", "prs", "--mentions=@me", "--state=open", "--limit", "50", "--json", FIELDS]),
    ]
    assert len(queries) <= MAX_SEARCH
    items, seen = [], {}
    for i, (kind, args) in enumerate(queries):
        if i:
            sleep(SLEEP)
        individual = any(a.startswith("user-review-requested:") for a in args)   # a query term: gh has no flag for it
        for r in _json(args):
            it = _item(r, kind, cfg)
            if not it:
                continue
            if (it["ref"], kind) not in seen:
                seen[(it["ref"], kind)] = it
                items.append(it)
            if individual:
                seen[(it["ref"], kind)]["individual"] = True
            if kind == "mention":
                seen[(it["ref"], kind)]["mention"] = True
    _feedback(items, cfg, int(now or time.time()))
    return items


def view(kind, repo, number):
    """State of one item, for the completion detectors. Always `-R repo`: never the cwd's repo."""
    sub = "issue" if kind == "issue" else "pr"
    fields = "state,closedAt" if kind == "issue" else "state,mergedAt,reviews,reviewRequests"
    return _json([sub, "view", str(number), "-R", repo, "--json", fields])
