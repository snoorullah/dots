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

// What the chip says it is going back to: the ticket ref, else the task text.
function backLabel(task) {
    if (!task) return "your task";
    var ref = task.ref ? String(task.ref) : "";
    if (ref !== "" && ref.indexOf("local:") !== 0) return ref;
    var d = task.desc ? String(task.desc) : "";
    if (d === "") return "your task";
    return d.length > LABEL_MAX ? d.substring(0, LABEL_MAX) + "…" : d;
}

// A detour is the clock being "away" while a task is declared. doc is now.json's body.
function detour(doc, nowSec) {
    var none = { active: false, sec: 0, age: "0m", label: "", text: "" };
    if (!doc || !doc.task || !doc.clock) return none;
    // a dead writer is not a detour: same 180 s rule as the overview's staleness
    if (typeof doc.ts === "number" && Number(nowSec) - doc.ts > STALE_SEC) return none;
    var c = doc.clock;
    if (c.state !== "away" || typeof c.sinceTs !== "number") return none;
    var sec = Math.max(0, Number(nowSec) - c.sinceTs);
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
