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

MAX_SEARCH = 6
SLEEP = float(os.environ.get("DOTS_OVERVIEW_GH_SLEEP", 2))     # the env override exists for tests only
MIN_REMAINING = 8
FIELDS = "number,title,url,repository,state,updatedAt,createdAt,author,isPullRequest"


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
            "work": cfg.is_work_repo(repo)}


def fetch(cfg, sleep=time.sleep):
    """Three searches: issues assigned to me, PRs I authored, PRs awaiting my review."""
    if not quota_ok():
        raise GhError("search quota nearly spent; skipping this cycle")
    queries = [
        ("issue", ["search", "issues", "--assignee=@me", "--state=open", "--limit", "50", "--json", FIELDS]),
        ("pr", ["search", "prs", "--author=@me", "--state=open", "--limit", "50", "--json", FIELDS]),
        ("review", ["search", "prs", "--review-requested=@me", "--state=open", "--limit", "50", "--json", FIELDS]),
    ]
    assert len(queries) <= MAX_SEARCH
    items, seen = [], set()
    for i, (kind, args) in enumerate(queries):
        if i:
            sleep(SLEEP)
        for r in _json(args):
            it = _item(r, kind, cfg)
            if it and (it["ref"], kind) not in seen:
                seen.add((it["ref"], kind))
                items.append(it)
    return items


def view(kind, repo, number):
    """State of one item, for the completion detectors. Always `-R repo`: never the cwd's repo."""
    sub = "issue" if kind == "issue" else "pr"
    fields = "state,closedAt" if kind == "issue" else "state,mergedAt,reviews,reviewRequests"
    return _json([sub, "view", str(number), "-R", repo, "--json", fields])
