"""PreToolUse hook for the alert-fix agent. Stdlib only; reads the tool call as JSON on stdin.

READ THIS FIRST: this hook is defence in depth, NOT the security boundary. The boundary is
(1) the agent has no git, no credentials and no network, because all git and GitHub work is host
code that runs after a human click (alertpush.py), and (2) the bwrap sandbox on its Bash tool
(settings: failIfUnavailable, no unsandboxed escape, writes only in work/ and io/proposal.md,
home unreadable). A bypass of this file must still find nothing to steal and nothing to call.

What it does:
  - tool-name ALLOWLIST: Read, Edit, Write, Glob, Grep, Bash. Any other tool name is denied.
  - Edit/Write only inside work/ (or exactly io/proposal.md), after realpath; a target that is
    itself a symlink, or that resolves outside, is denied; no `.git*` or `.github` component.
  - Read/Glob/Grep only inside work/ or io/ after realpath.
  - Bash: one plain command. Shell syntax (; & | < > $ ` ( ) newline) is denied, and the first
    word may not carry `# ! { } * ? [ =`. Network, git, gh, cluster, mail, privilege and
    interpreter-eval commands are denied by name. This is a speed bump, not a parser to trust.

Fail closed: any exception, bad JSON or missing argument exits 2. settings.json wires it as
`timeout 10 python3 alerthook.py ... || exit 2`, so a crash, a timeout or a missing python also
denies.
"""
import argparse
import json
import os
import shlex
import sys

ALLOWED_TOOLS = {"Read", "Edit", "Write", "Glob", "Grep", "Bash"}
SHELL_SYNTAX = set(";&|<>$`()\n\r\\")
BAD_FIRST = set("#!{}*?[=~")
DENY_COMMANDS = {
    # network and remote access
    "curl", "wget", "nc", "ncat", "netcat", "socat", "telnet", "ssh", "scp", "sftp", "rsync", "ftp", "dig", "nslookup",
    # git and GitHub: host-only
    "git", "gh", "hub",
    # cluster, cloud, mail
    "kubectl", "helm", "argocd", "k9s", "terraform", "tofu", "aws", "gcloud", "az", "docker", "podman",
    "dots-mail", "dots-inbox", "aerc", "msmtp", "sendmail", "mail", "notmuch", "dots-overview", "herdr",
    # privilege, wrappers that run another command, eval-style interpreters
    "sudo", "su", "doas", "env", "xargs", "nohup", "timeout", "command", "exec", "nice", "time", "setsid",
    "busybox", "eval", "source", ".", "bash", "sh", "zsh", "dash", "fish", "perl", "ruby", "php", "node",
    "nodejs", "deno", "lua", "awk", "gawk", "find",
}


def deny(reason):
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "PreToolUse", "permissionDecision": "deny",
        "permissionDecisionReason": f"alert-fix hook: {reason}"}}))
    sys.exit(2)


def inside(path, roots):
    """True when path (realpath) is a root or below one."""
    rp = os.path.realpath(path)
    return any(rp == r or rp.startswith(r + os.sep) for r in roots)


def check_path(path, roots, write, work, proposal):
    if not isinstance(path, str) or not path or "\0" in path:
        deny("missing or odd path")
    path = os.path.abspath(os.path.join(work, os.path.expanduser(path)) if not os.path.isabs(path) else path)
    if write:
        if os.path.islink(path):
            deny("write target is a symlink")
        if os.path.realpath(path) == os.path.realpath(proposal):
            return
        if not inside(path, [work]):
            deny("write outside work/")
        rel = os.path.relpath(os.path.realpath(path), work)
        if any(p.lower().startswith(".git") for p in rel.split(os.sep)):
            deny("write to a .git* or .github path")
    elif not inside(path, roots):
        deny("read outside work/ and io/")


def check_bash(cmd):
    if not isinstance(cmd, str) or not cmd.strip():
        deny("empty command")
    if len(cmd) > 2000:
        deny("command too long")
    if any(c in SHELL_SYNTAX for c in cmd):
        deny("shell syntax is not allowed: one plain command per call")
    lex = shlex.shlex(cmd, posix=True, punctuation_chars=False)
    lex.whitespace_split = True
    lex.commenters = ""                      # '#' is a character, not a comment
    try:
        words = list(lex)
    except ValueError:
        deny("unparseable command")
    if not words:
        deny("empty command")
    if any(w.startswith(("#", "!")) for w in words):
        deny("a word starting with # or ! is not allowed")
    first = words[0]
    if any(c in BAD_FIRST for c in first) or first.startswith("-"):
        deny("odd command word")
    name = os.path.basename(first)
    if name in DENY_COMMANDS or name.startswith("mkfs") or name.startswith("."):
        deny(f"command {name!r} is not allowed")
    if name.startswith("python") and any(
            w == "-c" or (w.startswith("-") and not w.startswith("--") and w.endswith("c")) for w in words[1:]):
        deny("interpreter -c is not allowed")
    for w in words[1:]:
        if w in ("--exec", "-exec", "-execdir", "--eval") or w.startswith("--exec="):
            deny("exec option")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--work", required=True)
    ap.add_argument("--io", required=True)
    a = ap.parse_args()
    work, io = os.path.realpath(a.work), os.path.realpath(a.io)
    proposal = os.path.join(io, "proposal.md")
    ev = json.load(sys.stdin)
    tool, inp = ev.get("tool_name"), ev.get("tool_input") or {}
    if tool not in ALLOWED_TOOLS:
        deny(f"tool {str(tool)[:40]!r} is not on the allowlist")
    if tool in ("Edit", "Write"):
        check_path(inp.get("file_path"), [work], True, work, proposal)
    elif tool == "Read":
        check_path(inp.get("file_path"), [work, io], False, work, proposal)
    elif tool in ("Glob", "Grep"):
        if inp.get("path"):
            check_path(inp.get("path"), [work, io], False, work, proposal)
        pat = inp.get("pattern") if tool == "Glob" else None
        if isinstance(pat, str) and (pat.startswith("/") or ".." in pat.split("/")):
            deny("glob pattern leaves the working directory")
    elif tool == "Bash":
        check_bash(inp.get("command"))
    sys.exit(0)


if __name__ == "__main__":
    try:
        main()
    except SystemExit:
        raise
    except BaseException as e:                # fail closed on anything unexpected
        print(json.dumps({"hookSpecificOutput": {
            "hookEventName": "PreToolUse", "permissionDecision": "deny",
            "permissionDecisionReason": f"alert-fix hook crashed: {type(e).__name__}"}}))
        sys.exit(2)
