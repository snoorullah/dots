// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Shaik Noorullah Shareef
.pragma library

// Pure logic for the moments surfaces: quick capture, re-nudge, return chip, handed card.
// QML only formats and binds; every decision lives here so qmltestrunner can pin it.

var NUDGE_FIRST_MS = 10 * 60 * 1000;
var NUDGE_REPEAT_MS = 30 * 60 * 1000;
var CAPTURE_MAX = 500;
var LABEL_MAX = 26;
var STALE_SEC = 180;

// argv for a local capture, or null when there is nothing to save. `--` makes Taskwarrior
// take the text literally (no due:/project: attribute parsing); the title is one argument.
function captureArgv(text) {
    var t = String(text === undefined || text === null ? "" : text).replace(/\s+/g, " ").trim();
    if (t === "") return null;
    if (t.length > CAPTURE_MAX) t = t.substring(0, CAPTURE_MAX);
    return ["task", "add", "+capture", "--", t];
}

// n = how many times this toast has already come back. First return 10 min after the
// dismissal, then every 30 min.
function renudgeDelayMs(n) {
    return (Number(n) >= 1) ? NUDGE_REPEAT_MS : NUDGE_FIRST_MS;
}

function renudgeDue(waiting, stillTracked) {
    return !!waiting && !!stillTracked;
}

// Only an agent asking for me re-nudges: every other toast is gone once it is gone.
function isWaiting(appName) {
    return appName === "Claude Code";
}

function fmtAge(sec) {
    var s = Number(sec);
    if (!isFinite(s) || s < 0) s = 0;
    var m = Math.floor(s / 60);
    if (m < 60) return m + "m";
    var h = Math.floor(m / 60), r = m % 60;
    return h + "h " + (r < 10 ? "0" : "") + r + "m";
}

// The ticket a person would say aloud: "HD 8580" or "infra#212" (task.ticket from now.json;
// an older file falls back to the ref or an HD number in the title). Never an internal id.
function pad4(n) { n = String(n); return n.length < 4 ? ("0000" + n).slice(-4) : n; }

function ticketOf(task) {
    if (!task) return "";
    if (task.ticket) return String(task.ticket);
    var ref = task.ref ? String(task.ref) : "", d = task.desc ? String(task.desc) : "";
    var m = /^(?:HD[ -]?#?)?(\d{3,6})$/.exec(ref);
    if (m) return "HD " + pad4(m[1]);
    m = /^gh:[^\/\s]+\/([^#\s]+)#(\d+)$/.exec(ref);
    if (m) return m[1] + "#" + m[2];
    m = /\bHD[ -]?#?(\d{3,6})\b/.exec(d);
    return m ? "HD " + pad4(m[1]) : "";
}

function plainDesc(desc) {
    var d = String(desc === undefined || desc === null ? "" : desc);
    d = d.replace(/\(\s*(?:(?:TASK-\d{4}-\d+|HD[ -]?#?\d{3,6})\s*[,;]?\s*)+\)/g, " ");
    d = d.replace(/\bTASK-\d{4}-\d+\b/g, " ");
    d = d.replace(/^\s*HD[ -]?#?\d{3,6}\s*[:\-]\s*/, "");
    return d.replace(/\s+/g, " ").replace(/^[\s:,;-]+|[\s:,;-]+$/g, "");
}

// What the chip says it is going back to: the ticket, else the task text without ids.
function backLabel(task) {
    if (!task) return "your task";
    var t = ticketOf(task);
    if (t !== "") return t;
    var d = plainDesc(task.desc);
    if (d === "") return "your task";
    return d.length > LABEL_MAX ? d.substring(0, LABEL_MAX) + "…" : d;
}

// ---- where my attention is: Hyprland's focused window, local only -----------------------
// The task lives in a terminal (herdr). A detour is leaving that place for something else
// (Comms, Web ...) for DETOUR_SEC or more. The shell feeds one sample per focus change; this
// folds it into a small state {home, homeWs, offSince, key}. QML never decides.
var DETOUR_SEC = 120;
var HOME_PROFILES = ["Agents", "Dev"];     // the work surfaces, home until a terminal says otherwise
var BACK_KEY = "Super+Alt+B";
var TERMINALS = /^(?:com\.mitchellh\.ghostty|ghostty|kitty|alacritty|foot|footclient|wezterm|org\.wezfurlong\.wezterm|xterm|konsole)$/i;

function freshFocus() { return { home: "", homeWs: 0, offSince: 0, key: "" }; }

// f: {cls, profile, ws}. terminal | other | neutral (a shell popup, nothing focused, a
// special workspace: says nothing about whether I left).
function focusKind(f) {
    if (!f) return "neutral";
    var cls = f.cls ? String(f.cls) : "";
    if (cls === "" || cls.indexOf("dots.") === 0) return "neutral";
    if (!f.profile) return "neutral";
    return TERMINALS.test(cls) ? "terminal" : "other";
}

function onHome(profile, home) {
    var work = HOME_PROFILES.indexOf(profile) >= 0;
    if (home === "") return work;
    return profile === home || (work && HOME_PROFILES.indexOf(home) >= 0);
}

// st: the previous state, f: the sample, nowSec, key: which task this is (a new task resets)
function focusStep(st, f, nowSec, key) {
    var s = { home: st && st.home ? st.home : "", homeWs: st && st.homeWs ? st.homeWs : 0,
              offSince: st && st.offSince ? st.offSince : 0, key: st && st.key ? st.key : "" };
    var k = key === undefined || key === null ? "" : String(key);
    if (k !== s.key) s = { home: "", homeWs: 0, offSince: 0, key: k };
    var kind = focusKind(f);
    if (kind === "neutral") return s;
    if (kind === "terminal") {
        s.home = String(f.profile);
        s.homeWs = Number(f.ws) > 0 ? Number(f.ws) : s.homeWs;
        s.offSince = 0;
        return s;
    }
    if (onHome(String(f.profile), s.home)) s.offSince = 0;
    else if (!s.offSince) s.offSince = Number(nowSec);
    return s;
}

// A detour is the clock being "away" while a task is declared, or focus off the task for
// DETOUR_SEC. doc is now.json's body, fs the focus state (optional).
function detour(doc, nowSec, fs) {
    var none = { active: false, sec: 0, age: "0m", label: "", text: "" };
    if (!doc || !doc.task || !doc.clock) return none;
    // a dead writer is not a detour: same 180 s rule as the overview's staleness
    if (typeof doc.ts === "number" && Number(nowSec) - doc.ts > STALE_SEC) return none;
    var c = doc.clock, sec = -1;
    if (c.state === "away" && typeof c.sinceTs === "number") sec = Math.max(0, Number(nowSec) - c.sinceTs);
    else if (c.state === "in" && fs && fs.offSince > 0) {
        var off = Number(nowSec) - fs.offSince;
        if (off >= DETOUR_SEC) sec = off;
    }
    if (sec < 0) return none;
    var age = fmtAge(sec), label = backLabel(doc.task);
    return { active: true, sec: sec, age: age, label: label, text: "Detour " + age + " · back to " + label };
}

// A leading "-" would be read as an option by dots-jump.
function jumpArgv(task) {
    var ref = task && task.ref ? String(task.ref) : "";
    if (ref === "" || ref.charAt(0) === "-") return null;
    return ["dots-jump", ref];
}

function handedModel(obj) {
    var o = (obj && typeof obj === "object") ? obj : {};
    var steps = [];
    var src = Array.isArray(o.steps) ? o.steps : [];
    for (var i = 0; i < src.length; i++) {
        var s = src[i];
        if (!s || typeof s !== "object") continue;
        steps.push({ at: s.at === undefined || s.at === null ? "" : String(s.at), text: s.text ? String(s.text) : "" });
    }
    var m = { ask: o.ask ? String(o.ask) : "", said: o.said ? String(o.said) : "",
              permission: o.permission ? String(o.permission) : "", steps: steps };
    m.empty = m.ask === "" && steps.length === 0;
    return m;
}

// hyprctl, in the dispatch form Hyprland 0.56 (Lua config) accepts: the same one services/Hypr.qml uses.
function focusWsArgv(id) {
    var n = parseInt(id);
    if (!(n > 0)) return null;
    return ["hyprctl", "dispatch", "hl.dsp.focus({ workspace = \"" + n + "\" })"];
}

// Back: the workspace the terminal was on, then the task's pane in herdr. Each is its own argv.
function backArgvs(task, homeWs) {
    var out = [], w = focusWsArgv(homeWs), j = jumpArgv(task);
    if (w) out.push(w);
    if (j) out.push(j);
    return out;
}
