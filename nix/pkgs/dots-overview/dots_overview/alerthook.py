#!/usr/bin/env python3
"""PreToolUse gate for the alert-fix agent. Stdlib only, runs outside the model's control.

Claude Code feeds the tool call as JSON on stdin. This script prints a deny decision (and
exits 2) or says nothing and exits 0, which leaves the call to the normal permission prompt
(the agent is started in manual mode, so a person still approves).

  python3 alerthook.py --branch fix/local-ab12-disk-full   < tool-call.json

Bash commands are parsed with shlex and DEFAULT-DENIED when they:
  - contain a shell control operator, substitution, variable, newline or env assignment
  - run an interpreter with -c / -e, or a wrapper that runs another command (env, xargs, ...)
  - name a network, cluster, mail or ssh tool
  - are `git` / `gh` and not one of the few verbs allowed below.
Allowed git: read-only verbs, local work (add, commit, rm, mv, restore, stash, worktree add),
checkout/switch of the fix branch, and `git push [-u] origin <the exact fix branch>` with no
refspec, no force and no change under .github/workflows. Allowed gh: `gh pr create --draft`.
Anything else on git or gh is refused, so aliases, -c config, -C tricks, URL remotes and
`gh api` / `gh pr merge` / `gh pr ready` never get through.
"""
import json
import os
import re
import shlex
import subprocess
import sys

OPS = set("();<>|&")
SHELLS = {"bash", "sh", "zsh", "dash", "ksh", "fish", "csh", "tcsh"}
# interpreter -> short-flag letters / long flags that run code given on the command line
EVAL = {**{s: ("c", ("--command",)) for s in SHELLS},
        "python": ("c", ()), "python3": ("c", ()), "pypy": ("c", ()), "pypy3": ("c", ()),
        "perl": ("eE", ()), "ruby": ("e", ()), "node": ("ep", ("--eval", "--print")),
        "nodejs": ("ep", ("--eval", "--print")), "deno": ("e", ("eval",)), "bun": ("e", ("--eval",)),
        "php": ("r", ()), "lua": ("e", ()), "tclsh": ("", ()), "awk": ("", ("--source",)),
        "gawk": ("", ()), "osascript": ("e", ()), "pwsh": ("c", ("-Command",))}
WRAPPERS = {"env", "command", "builtin", "exec", "eval", "xargs", "nohup", "nice", "ionice", "timeout",
            "sudo", "doas", "su", "runuser", "time", "stdbuf", "setsid", "watch", "flock", "chroot",
            "unshare", "nsenter", "strace", "ltrace", "gdb", "busybox", "script", "parallel", "at",
            "batch", "crontab", "source", ".", "trap", "alias", "coproc", "fakeroot", "firejail"}
BLOCKED = {"kubectl", "helm", "argocd", "k9s", "kubectx", "kustomize", "flux", "terraform", "tofu",
           "ansible", "ansible-playbook", "docker", "podman", "nerdctl", "crictl",
           "ssh", "scp", "sftp", "rsync", "ssh-agent", "ssh-add", "mosh",
           "curl", "wget", "nc", "ncat", "netcat", "socat", "telnet", "ftp", "aria2c", "http", "xh",
           "dots-mail", "dots-inbox", "aerc", "msmtp", "sendmail", "mail", "mailx", "mutt", "neomutt",
           "notmuch", "mbsync", "himalaya", "slackcat", "notify-send", "xdg-open", "open",
           "dots-overview", "task", "timew", "claude", "herdr", "llm", "pi",
           "gpg", "pass", "age", "secret-tool", "kwallet-query"}
DESTRUCTIVE_FIND = {"-exec", "-execdir", "-ok", "-okdir", "-delete", "-fprint", "-fprintf", "-fls"}
# Per-verb FLAG ALLOWLIST: any option not matched is refused, so nothing that runs a program
# (-O, --open-files-in-pager, --ext-diff, --textconv, --exec) or writes a file (--output) or
# reads one into a commit/PR (-F, --template) can appear.
_READ = (r"--(stat|name-only|name-status|numstat|shortstat|cached|staged|no-color|color|oneline|graph|"
         r"decorate|patch|all|first-parent|reverse|follow|no-merges|merges|abbrev-commit|no-ext-diff|"
         r"no-textconv|summary|check|quiet|raw|full-index|binary|minimal|patience|histogram|word-diff|"
         r"ignore-all-space|ignore-space-change|ignore-blank-lines|text|function-context|exit-code|"
         r"no-renames|relative-date|show-toplevel|abbrev-ref|git-dir|absolute-git-dir|git-common-dir|"
         r"verify|is-inside-work-tree|show-cdup|show-prefix|symbolic-full-name|others|modified|deleted|"
         r"exclude-standard|tags|long|always|dirty|count|root|"
         r"(stat-width|stat-count|unified|max-count|skip|abbrev|short|find-renames|find-copies)(=\d+%?)?|"
         r"(pretty|format|date|since|until|after|before|author|committer|grep|diff-filter)=[^\x00]*|"
         r"short|pretty)|-([pswbunqzatrlL]+|n?\d+|U\d+|S|G|M\d*)")
READ_FLAG = re.compile(r"^(" + _READ + r")$")
LOCAL_FLAGS = {
    "add": r"^(-[AuNnvf]|--(all|update|intent-to-add|dry-run|verbose|ignore-removal|no-all|force))$",
    "commit": r"^(-[asqnv]*m|-[asqnv]+|--(all|signoff|amend|no-edit|quiet|allow-empty|no-verify|verbose|"
              r"author=[^\x00]*|message=[^\x00]*|date=[^\x00]*)|-m.+)$",
    "rm": r"^(-[rfnq]+|--(cached|dry-run|quiet|ignore-unmatch|force))$",
    "mv": r"^(-[fknv]+|--(force|dry-run|verbose))$",
    "restore": r"^(-[SWq]+|--(staged|worktree|quiet|source=[^\x00]*|ours|theirs))$",
    "stash": r"^(-[ukqam]+|--(include-untracked|keep-index|quiet|all|index|message|patch)|-p)$",
}
SAFE_GIT_READ = {"status", "diff", "log", "show", "rev-parse", "rev-list", "ls-files", "blame",
                 "describe", "cat-file", "diff-tree", "name-rev", "show-ref", "merge-base",
                 "reflog", "ls-tree", "version"}
SAFE_GIT_LOCAL = set(LOCAL_FLAGS)
WORKFLOWS = re.compile(r"(^|/)\.github/workflows(/|$)")
NAME = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._/-]{0,120}$")


class Deny(Exception):
    pass


def tokens(cmd):
    if not isinstance(cmd, str) or not cmd.strip():
        raise Deny("empty command")
    if re.search(r"[\n\r\0`$]", cmd):
        raise Deny("newline, backtick or $ (expansion/substitution) in a command")
    lex = shlex.shlex(cmd, posix=True, punctuation_chars=True)
    lex.whitespace_split = True
    try:
        toks = list(lex)
    except ValueError as e:
        raise Deny(f"unparseable command: {e}")
    for t in toks:
        if t and set(t) <= OPS:
            raise Deny(f"shell control operator {t!r}")
    if not toks:
        raise Deny("empty command")
    return toks


def interpreter_eval(prog, args):
    letters, longs = EVAL[prog]
    for a in args:
        if a in longs or any(a.startswith(l + "=") for l in longs if l.startswith("--")):
            return True
        if a.startswith("-") and not a.startswith("--") and letters and any(c in letters for c in a[1:]):
            return True
    return False


def split_git(args):
    """-> (subcommand, rest). Only `--no-pager` may precede the verb: -C, -c, --config-env,
    --git-dir ... could set core.pager, core.fsmonitor, diff.external or an alias."""
    i = 0
    while i < len(args):
        a = args[i]
        if a == "--no-pager":
            i += 1
        elif a.startswith("-"):
            raise Deny(f"git option {a!r} before the verb is not allowed (-C, -c, --config-env, --git-dir ...)")
        else:
            return a, args[i + 1:]
    raise Deny("git without a verb")


def push_names(cwd, branch):
    """File names a push of `branch` would add: commits on it that no remote has."""
    r = subprocess.run(["git", "-C", cwd or ".", "log", branch, "--not", "--remotes",
                        "--name-only", "--format="], capture_output=True, text=True, timeout=30)
    if r.returncode != 0:
        raise Deny("cannot work out what the push would send (git log failed)")
    return [l for l in r.stdout.splitlines() if l.strip()]


def git_rule(args, branch, cwd):
    verb, rest = split_git(args)
    if verb in SAFE_GIT_READ or verb in SAFE_GIT_LOCAL:
        pat = re.compile(LOCAL_FLAGS[verb]) if verb in LOCAL_FLAGS else (
            re.compile(r"^(" + _READ + r"|-L)$") if verb == "blame" else
            re.compile(r"^(" + _READ + r"|-[tep])$") if verb == "cat-file" else READ_FLAG)
        for a in rest:
            if a == "--":
                break
            if a.startswith("-") and a != "-" and not pat.match(a):
                raise Deny(f"git {verb}: option {a!r} is not on the allowed list")
        if verb == "stash" and rest and rest[0] not in {"push", "pop", "list", "show", "apply", "drop", "save"} \
                and not rest[0].startswith("-"):
            raise Deny("git stash: unknown form")
        if verb == "reflog" and rest and rest[0] in {"expire", "delete"}:
            raise Deny("git reflog expire/delete")
        return
    if verb == "branch":
        if all(a in {"-a", "-r", "-v", "-vv", "--list", "--show-current", "-l"} for a in rest):
            return
        raise Deny("git branch: only listing is allowed")
    if verb in ("checkout", "switch"):
        flags = [a for a in rest if a.startswith("-")]
        pos = [a for a in rest if not a.startswith("-")]
        if set(flags) <= {"-b", "-c"} and pos == [branch]:
            return
        raise Deny(f"git {verb}: only the fix branch {branch} may be checked out")
    if verb == "fetch":
        if rest in ([], ["origin"], ["--prune", "origin"]):
            return
        raise Deny("git fetch: only plain `git fetch [origin]`")
    if verb == "worktree":
        if rest[:1] == ["list"] and len(rest) == 1:
            return
        if rest[:1] == ["add"]:
            a, pos, i = rest[1:], [], 0
            while i < len(a):
                if a[i] == "-b" and i + 1 < len(a):
                    if a[i + 1] != branch:
                        raise Deny("worktree add -b: only the fix branch")
                    i += 2
                elif a[i].startswith("-"):
                    raise Deny(f"worktree add: option {a[i]!r} not allowed")
                else:
                    pos.append(a[i]); i += 1
            if 1 <= len(pos) <= 2:
                return
        raise Deny("git worktree: only `list` and `add [-b <fix branch>] <path> [<start>]`")
    if verb == "push":
        a = [x for x in rest if x not in ("-u", "--set-upstream")]
        if len(a) == 2 and a[0] == "origin" and a[1] == branch and all(
                x in ("-u", "--set-upstream") or x in a for x in rest):
            if ":" in a[1] or a[1].startswith(("+", "-")):
                raise Deny("push refspec")
            bad = [n for n in push_names(cwd, branch) if WORKFLOWS.search(n)]
            if bad:
                raise Deny(f"the push would change a workflow file: {bad[0]}")
            return
        raise Deny(f"git push: only `git push [-u] origin {branch}` (no refspec, no force, no other remote)")
    raise Deny(f"git {verb}: not on the allowed list (read-only verbs, local work, the fix-branch push)")


GH_PR_CREATE_FLAGS = {"--draft", "--fill", "--fill-first", "--fill-verbose", "--no-maintainer-edit",
                      "-d"}
GH_PR_CREATE_VALUE = {"--title": "t", "-t": "t", "--body": "b", "-b": "b", "--base": "B", "-B": "B", "--head": "H", "-H": "H"}


def gh_rule(args, branch):
    if tuple(args[:2]) != ("pr", "create"):   # the one gh write, drafts only
        raise Deny("gh: only `gh pr create --draft` is allowed")
    rest, i, draft = args[2:], 0, False
    while i < len(rest):
        a = rest[i]
        key, eq, val = a.partition("=") if a.startswith("--") else (a, "", "")
        if a in GH_PR_CREATE_FLAGS:
            draft = draft or a in ("--draft", "-d")
            i += 1
        elif key in GH_PR_CREATE_VALUE:
            if not eq:
                if i + 1 >= len(rest):
                    raise Deny(f"gh pr create: {a} needs a value")
                val = rest[i + 1]; i += 1
            if GH_PR_CREATE_VALUE[key] == "H" and val not in (branch, f"origin:{branch}"):
                raise Deny("gh pr create: --head must be the fix branch")
            i += 1
        else:
            raise Deny(f"gh pr create: option {a!r} not allowed (no --body-file/-F, --repo/-R, --web, reviewers, labels)")
    if not draft:
        raise Deny("gh pr create must have --draft")


def check_bash(cmd, branch, cwd):
    toks = tokens(cmd)
    if re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", toks[0]):
        raise Deny("environment assignment before a command")
    prog = os.path.basename(toks[0])
    args = toks[1:]
    if prog in WRAPPERS:
        raise Deny(f"{prog} runs other commands")
    if prog in BLOCKED:
        raise Deny(f"{prog} is not available to this agent")
    if prog in EVAL and interpreter_eval(prog, args):
        raise Deny(f"{prog} with inline code")
    if prog == "find" and DESTRUCTIVE_FIND & set(args):
        raise Deny("find with -exec/-delete")
    if prog == "git":
        git_rule(args, branch, cwd)
    elif prog == "gh":
        gh_rule(args, branch)
    elif prog.startswith("git-") or prog.startswith("gh-"):
        raise Deny(f"{prog}: git/gh helper binaries are not allowed")


def decide(call, branch):
    name = call.get("tool_name") or ""
    inp = call.get("tool_input") or {}
    if name in ("WebFetch", "WebSearch") or name.startswith("mcp__"):
        raise Deny(f"{name} is not available to this agent")
    if name == "Bash":
        check_bash(inp.get("command"), branch, call.get("cwd"))


def main(argv=None, stdin=None, out=None):
    argv = sys.argv[1:] if argv is None else argv
    branch = argv[argv.index("--branch") + 1] if "--branch" in argv else ""
    try:
        if not NAME.match(branch) or ":" in branch:
            raise Deny("hook misconfigured: no valid --branch")
        call = json.load(stdin or sys.stdin)
        decide(call, branch)
    except Deny as e:
        reason = f"alert-agent gate: {e}"
    except Exception as e:                    # fail closed
        reason = f"alert-agent gate: could not evaluate ({type(e).__name__})"
    else:
        return 0
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse",
                                              "permissionDecision": "deny",
                                              "permissionDecisionReason": reason}}), file=out or sys.stdout)
    print(reason, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
