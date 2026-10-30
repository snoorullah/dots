"""Push a reviewed alert patch and open a DRAFT PR. Host code only; no LLM, no agent.

Runs only from `dots-overview alert-push <ref>` (the overview's separate "Push and open draft
PR" button). Nothing else calls push(): not launch, not extract, not review. It refuses unless
a person already opened the review of THIS exact patch (the `reviewed` marker holds its sha256).

  fresh temp clone of the owner's configured remote   (the agent's tree is never touched)
  checkout the base sha, `git apply --check`, `git apply --index` the extracted patch
  commit with a fixed identity, hooks off, global config off
  refuse if the branch already exists on the remote; never force; branch is always fix/...
  push to the EXPLICIT url with an explicit <sha>:refs/heads/<branch> refspec
  gh pr create --draft with a host-written title and body-file

Text that came from the agent or the mail reaches GitHub only as a title charset-filtered here
and as the proposal inside a code fence with `@` removed, so it cannot mention or notify anyone.
"""
import hashlib
import os
import re
import shutil
import subprocess
import tempfile
from pathlib import Path

from . import alertrun

AUTHOR = ("dots alert-fix", "alert-fix@users.noreply.github.com")
URL_RE = (re.compile(r"^https://github\.com/([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+?)(?:\.git)?/?$"),
          re.compile(r"^(?:ssh://)?git@github\.com[:/]([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+?)(?:\.git)?$"))
BRANCH_RE = re.compile(r"^fix/[a-z0-9][a-z0-9-]{0,120}$")
HARDEN = ["-c", "core.hooksPath=/dev/null", "-c", "core.fsmonitor=false", "-c", "commit.gpgsign=false",
          "-c", "protocol.ext.allow=never", "-c", "core.fileMode=true"]


class PushError(RuntimeError):
    pass


def owner_repo(url):
    for rx in URL_RE:
        m = rx.match(url or "")
        if m:
            return f"{m.group(1)}/{m.group(2)}"
    return None


def title_for(name):
    return "Fix: " + (re.sub(r"[^A-Za-z0-9 _.:-]", "", name or "")[:80].strip() or "alert")


def defang(text, limit=4000):
    """Agent text made inert for GitHub: no control chars, no `@` (no mention can parse), and
    the caller puts it in a code fence, where links and #refs do not render."""
    t = alertrun.plain(text or "", limit).replace("\r", "").replace("@", "(at)")
    return t.strip()


def fence(text):
    n = max([3] + [len(x) + 1 for x in re.findall(r"`+", text)])
    return "`" * n


def body_for(m, proposal):
    p = defang(proposal)
    f = fence(p)
    return (f"Draft fix for local alert ticket {re.sub(r'[^A-Za-z0-9:_.-]', '', m.get('ref') or '')}.\n\n"
            f"Base commit: {m.get('sha')}\n"
            "Made by an agent that had no git access, no credentials and no network; a person reviewed the "
            "patch before this branch was pushed. Review it like any other contribution.\n\n"
            "Agent proposal, verbatim and untrusted (it came from analysing an alert mail):\n\n"
            f"{f}\n{p}\n{f}\n")


def remote_url(repo, run=subprocess.run):
    r = run(["git", "-C", str(repo), "config", "--get", "remote.origin.url"], capture_output=True, text=True,
            timeout=20, env=alertrun.git_env(), stdin=subprocess.DEVNULL)
    return r.stdout.strip()


def _git(cwd, *args, env=None, run=subprocess.run, ok=(0,)):
    r = run(["git", *HARDEN, *args], cwd=cwd, capture_output=True, text=True, timeout=300,
            env=env or alertrun.git_env(), stdin=subprocess.DEVNULL)
    if r.returncode not in ok:
        raise PushError(f"git {args[0]}: {(r.stderr or r.stdout).strip()[:300]}")
    return r


def push(d, confirmed=False, remote=None, repo_slug=None, run=subprocess.run, gh=None):
    """Returns the PR URL. `confirmed` must be True: only the CLI's alert-push passes it.
    `remote`/`repo_slug` exist for tests; the CLI derives both from the mapped checkout's origin."""
    if confirmed is not True:
        raise PushError("not confirmed")
    d = Path(d)
    m = alertrun.meta(d)
    if not m or not (d / "patch.diff").is_file():
        raise PushError("no patch to push")
    patch = (d / "patch.diff").read_bytes()
    digest = hashlib.sha256(patch).hexdigest()
    if digest != m.get("patch_sha256") or not alertrun.is_reviewed(d):
        raise PushError("this patch was not opened for review; use Review patch first")
    branch, sha = m.get("branch", ""), m.get("sha", "")
    if not BRANCH_RE.match(branch) or not re.fullmatch(r"[0-9a-f]{40}", sha):
        raise PushError("bad run metadata")
    url = remote or remote_url(m["repo"], run)
    slug = repo_slug or owner_repo(url)
    if not slug:
        raise PushError("origin is not a github.com URL; not pushing")
    env = alertrun.git_env()
    cred = ["-c", "credential.helper=", "-c", "credential.helper=!gh auth git-credential"] \
        if url.startswith("https://") else []
    tmp = tempfile.mkdtemp(prefix="dots-push-")
    try:
        c = os.path.join(tmp, "c")
        _git(tmp, *cred, "clone", "--no-checkout", "--no-tags", "--quiet", url, c, env=env, run=run)
        _git(c, "checkout", "--detach", "--quiet", sha, env=env, run=run)
        pf = os.path.join(tmp, "patch.diff")
        Path(pf).write_bytes(patch)
        _git(c, "apply", "--check", pf, env=env, run=run)
        _git(c, "apply", "--index", pf, env=env, run=run)
        cenv = alertrun.git_env({"GIT_AUTHOR_NAME": AUTHOR[0], "GIT_AUTHOR_EMAIL": AUTHOR[1],
                                 "GIT_COMMITTER_NAME": AUTHOR[0], "GIT_COMMITTER_EMAIL": AUTHOR[1]})
        msg = f"{title_for(m.get('title'))}\n\nAlert ticket {re.sub(r'[^A-Za-z0-9:_.-]', '', m.get('ref') or '')}.\n"
        _git(c, "commit", "--no-verify", "--quiet", "-m", msg, env=cenv, run=run)
        new = _git(c, "rev-parse", "HEAD", env=env, run=run).stdout.strip()
        ls = _git(c, *cred, "ls-remote", "--exit-code", url, f"refs/heads/{branch}", env=env, run=run, ok=(0, 2))
        if ls.returncode == 0:
            raise PushError(f"{branch} already exists on the remote; not touching it")
        _git(c, *cred, "push", "--no-verify", url, f"{new}:refs/heads/{branch}", env=env, run=run)
        bf = os.path.join(tmp, "body.md")
        proposal = (d / "io" / "proposal.md").read_text(encoding="utf-8", errors="replace")
        Path(bf).write_text(body_for(m, proposal), encoding="utf-8")
        argv = ["gh", "pr", "create", "--draft", "--repo", slug, "--head", branch,
                "--base", m.get("base_branch") or "main", "--title", title_for(m.get("title")), "--body-file", bf]
        r = (gh or run)(argv, cwd=tmp, capture_output=True, text=True, timeout=120, stdin=subprocess.DEVNULL,
                        env={k: v for k, v in os.environ.items() if k != "GIT_CONFIG_GLOBAL"})
        if r.returncode != 0:
            raise PushError(f"branch pushed but gh pr create failed: {(r.stderr or r.stdout).strip()[:300]}")
        return (r.stdout.strip().splitlines() or [""])[-1]
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
