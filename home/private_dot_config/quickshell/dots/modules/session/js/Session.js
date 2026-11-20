// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Shaik Noorullah Shareef
//
// The session module's model: pure functions, no I/O. QML draws what these return.
// An act is {op:"argv", argv:[...]} (run a local command, argv only) or
// {op:"off", why:"..."} (no backend: the control renders disabled and says why).
.pragma library

function argv() { return { op: "argv", argv: Array.prototype.slice.call(arguments) } }
function off(why) { return { op: "off", why: why } }
function disabled(act) { return !act || act.op === "off" }

// ---- away picker ----------------------------------------------------------------------

// rows for the picker from `session.py choices` output; the first row is the Enter target
function awayRows(choices) {
    var rows = []
    for (var i = 0; i < (choices || []).length; i++) {
        var c = choices[i]
        rows.push({ key: c.key, label: c.label, hint: String(i + 1), lead: !!c.lead })
    }
    return rows
}

// arrow keys and wrap-around; d is -1 or +1
function step(i, n, d) { return n <= 0 ? 0 : (i + d + n) % n }
// 1..9 jumps to that row, otherwise -1
function jump(text, n) { var k = parseInt(text, 10); return k >= 1 && k <= n ? k - 1 : -1 }

function helperArgv(py, sub, arg) {
    var a = ["python3", "-I", py, sub]
    if (arg !== undefined) a.push(arg)
    return a
}

// ---- session menu ---------------------------------------------------------------------
// env: {sessionId, user, early ("3:18" or ""), backup (argv array or null)}
// blocker: {pending} while the check runs (destructive buttons stay off), then {blocked, cmd, pane},
// or {blocked:false, unchecked:true} when herdr could not be read (live, and the card says so)
function sessionButtons(env, blocker) {
    env = env || {}
    var pending = !!(blocker && blocker.pending)
    var blocked = !!(blocker && blocker.blocked)
    var why = pending ? "Checking running commands..."
        : blocked ? "Blocked while " + blocker.cmd + " runs in pane " + blocker.pane : ""
    var logout = env.sessionId ? argv("loginctl", "terminate-session", String(env.sessionId))
        : env.user ? argv("loginctl", "terminate-user", String(env.user)) : off("no session id")
    function guard(act) { return pending || blocked ? off(why) : act }
    return [
        { id: "lock", title: "Lock", sub: "Keeps the day open", act: argv("loginctl", "lock-session") },
        { id: "logout", title: "Log out", sub: env.early ? "Ends your day, " + env.early + " early" : "Ends your day",
          act: guard(logout) },
        { id: "suspend", title: "Suspend", sub: "Saves state first", act: argv("systemctl", "suspend") },
        { id: "reboot", title: "Reboot", sub: "Restores after login", act: guard(argv("systemctl", "reboot")) },
        { id: "poweroff", title: "Shut down", sub: "Saves state first", danger: true,
          act: guard(argv("systemctl", "poweroff")) },
        { id: "backup", title: "Back up, then shut down", sub: "Company and personal",
          act: env.backup && env.backup.length ? guard({ op: "argv", argv: env.backup }) : off("no backup command yet") }
    ]
}

// ---- password prompt ------------------------------------------------------------------
// f: plain snapshot of the polkit flow; returns what the card shows
function polkitView(f) {
    f = f || {}
    var prompt = String(f.inputPrompt || "").replace(/\s*:\s*$/, "")
    var title = f.message ? String(f.message) : "Authentication needed"
    return {
        title: title,
        action: f.actionId ? String(f.actionId) : "",
        prompt: prompt || "Password",
        echo: !!f.responseVisible,
        error: f.supplementaryIsError ? String(f.supplementaryMessage || "") : "",
        info: !f.supplementaryIsError ? String(f.supplementaryMessage || "") : "",
        agent: f.agentHint ? String(f.agentHint) : "",
        denyFirst: !!f.agentHint,
        canAllow: !!f.responseRequired
    }
}

// the herdr snapshot -> the agent line, or "" (an agent pane working is the only signal polkit lacks)
function agentHint(panes) {
    for (var i = 0; i < (panes || []).length; i++) {
        var p = panes[i]
        if (p.agent && p.agent_status === "working") {
            var m = /:p(\d+)$/.exec(p.pane_id || "")
            return "An agent is working in pane " + (m ? m[1] : p.pane_id)
        }
    }
    return ""
}

// ---- return rows ----------------------------------------------------------------------
var PHRASE = { salah: "Salah", washroom: "Washroom break", walk: "Short break",
               meal: "Lunch break", meeting: "Meeting", logout: "Logged out" }

function fmtGap(sec) {
    var m = Math.max(0, Math.round(sec / 60))
    if (m < 60) return m + " min"
    var h = Math.floor(m / 60), r = m % 60
    return r ? h + " h " + r + " min" : h + " h"
}

// declared: {key,label,since}|null (away-intent.json); now, idleSince: unix seconds;
// agent, mail: {text, note}|null (props from whoever has the data)
function returnRows(declared, now, idleSince, agent, mail) {
    var rows = []
    if (declared && declared.since) {
        var phrase = declared.key === "salah" && declared.label ? declared.label : (PHRASE[declared.key] || declared.label || "Away")
        rows.push({ id: "gap", a: "Declared", b: phrase + ", set by you", d: fmtGap(now - declared.since), tone: "accent" })
    } else if (idleSince) {
        rows.push({ id: "gap", a: "Detected", b: "Idle, no input", d: fmtGap(now - idleSince), tone: "accent" })
    }
    if (agent) rows.push({ id: "agent", a: "Agent", b: agent.text, d: agent.note || "", tone: "waiting" })
    if (mail) rows.push({ id: "mail", a: "Mail", b: mail.text, d: mail.note || "", tone: "dim" })
    return rows
}
