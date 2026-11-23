// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Shaik Noorullah Shareef
//
// Keyboard model for the control centre (spec: docs/shell/specs/cc-keys.md). Pure functions, no
// QML imports, so qmltestrunner covers them without a compositor. The view feeds one key event
// and a small state object to resolve() and gets back the action name to run.
.pragma library

var TABS = ["queue", "inbox", "agents", "tasks", "time"]
var SUBTABS = ["today", "week", "days", "heatmap", "zones", "progress", "report", "screen", "reminders", "agents"]
var PERIODS = ["today", "week", "month", "quarter"]

// Panes Tab cycles through, per page. A page with one pane has nothing to cycle.
var PANES = {
    queue: ["list", "detail"],
    inbox: ["list", "detail"],
    agents: ["list"],
    tasks: ["list"],
    time: ["tabs", "list"]
}

// Qt key codes the view passes in as ev.key. Printable keys come from ev.text instead, so the
// keyboard layout and Shift are already applied (G, ?, [).
var QT = {
    0x01000000: "Esc", 0x01000001: "Tab", 0x01000002: "Backtab", 0x01000004: "Enter", 0x01000005: "Enter",
    0x01000010: "Home", 0x01000011: "End", 0x01000012: "Left", 0x01000013: "Up", 0x01000014: "Right",
    0x01000015: "Down", 0x01000016: "PageUp", 0x01000017: "PageDown"
}

// Board per-page action keys. [key, action, label]. Used in the detail zone (queue, inbox) and in
// the list zone of pages with no detail pane. `b` and `j` are appended for every queue kind.
var ACTIONS = {
    agent: [["a", "allow", "Allow once"], ["d", "deny", "Deny"], ["o", "open", "Open pane"], ["s", "snooze", "Snooze"]],
    msg: [["r", "reply", "Reply"], ["g", "agent", "Send to agent"], ["q", "queue", "Queue"], ["s", "snooze", "Snooze"], ["o", "open", "Open"]],
    alert: [["v", "analysis", "See analysis"], ["f", "fix", "Fix in repo"], ["q", "queue", "Queue"], ["s", "snooze", "Snooze"]],
    pr: [["o", "open", "Open review"], ["g", "agent", "Send to agent"], ["q", "queue", "Queue"], ["s", "snooze", "Snooze"]],
    ticket: [["c", "comment", "Comment"], ["g", "agent", "Send to agent"], ["q", "queue", "Queue"], ["s", "snooze", "Remind"], ["o", "open", "Open"]],
    mail: [["r", "reply", "Draft reply"], ["g", "agent", "Send to agent"], ["q", "queue", "Queue"], ["s", "snooze", "Snooze"]],
    capture: [["t", "task", "Make a task"], ["g", "agent", "Send to agent"], ["x", "dismiss", "Dismiss"]]
}
var ACTIONS_COMMON = [["b", "breakdown", "Break down and start"], ["j", "jump", "Jump to source"]]

// List-zone action keys for pages without a detail pane, and for Time pages (proposed, not on the
// board: only the keys the page can act on today).
var PAGE_ACTIONS = {
    agents: [["o", "open", "Open pane"], ["t", "time", "Time, Agents tab"]],
    tasks: [["b", "breakdown", "Break down and start"], ["o", "open", "Open"]],
    "time/today": [["s", "focus", "Start or stop focus"], ["b", "break", "Take a break"]],
    "time/report": [["c", "copy", "Copy report"], ["r", "run", "Run daily report"]],
    "time/reminders": [["s", "snooze", "Snooze"], ["d", "done", "Done"]],
    "time/agents": [["o", "open", "Jump to the agent's pane"]]
}

// Saved views the nav lists, in the order { and } step through them. "" is no view.
var VIEWS = ["", "VIPs", "Overdue", "Snoozed", "Infra only"]
var GROUPS = ["Urgency", "Source", "Person"]
var TIME_BY = ["Project", "Item", "Agent", "App"]

var SNOOZE_OPTIONS = 4   // 30 minutes, after this task, tonight, tomorrow

function has(list, v) { return list.indexOf(v) >= 0 }

// ---- tokens ----------------------------------------------------------------
// ev: { key, text, shift, ctrl, alt }. Returns "j", "G", "?", "Esc", "Down", "Ctrl+Enter", ...
function tokenOf(ev) {
    var base = QT[ev.key]
    if (!base) {
        var t = ev.text || ""
        if (t.length !== 1 || t.charCodeAt(0) < 32) return ""
        base = t
    }
    if (ev.ctrl) return "Ctrl+" + base
    if (ev.alt) return "Alt+" + base
    return base
}

// ---- state helpers -----------------------------------------------------------
function textEntry(st) {
    return st.zone === "filter" || (st.zone === "panel" && (st.mode === "reply" || st.mode === "agent"))
}

function panes(page) { return PANES[page] || ["list"] }

function nextPane(page, zone, dir) {
    var p = panes(page), i = p.indexOf(zone)
    if (i < 0) return p[0]
    return p[(i + (dir < 0 ? p.length - 1 : 1)) % p.length]
}

function stepIn(list, cur, dir) {
    var i = list.indexOf(cur)
    if (i < 0) return list[0]
    return list[(i + (dir < 0 ? list.length - 1 : 1)) % list.length]
}

function nextView(cur, dir) { return stepIn(VIEWS, cur, dir) }
function nextGroup(cur, dir) { return stepIn(GROUPS, cur, dir) }
function nextBy(cur, dir) { return stepIn(TIME_BY, cur, dir) }
function nextSub(cur, dir) { return stepIn(SUBTABS, cur, dir) }
function nextPeriod(cur, dir) { return stepIn(PERIODS, cur, dir) }

function actionList(st) {
    if (st.page === "queue" || st.page === "inbox") {
        var k = ACTIONS[st.kind]
        return k ? k.concat(ACTIONS_COMMON) : []
    }
    if (st.page === "time") return PAGE_ACTIONS["time/" + st.sub] || []
    return PAGE_ACTIONS[st.page] || []
}

function hasList(page) { return page === "queue" || page === "inbox" }
function hasDetail(page) { return page === "queue" || page === "inbox" }

// Action keys are live in the detail zone of queue and inbox, and in the list zone elsewhere.
// In the queue list zone j, k and g navigate, so the board's Jump (j) and Send to agent (g)
// are reached after Enter or Right moves focus to the detail pane.
function actionZone(st) { return hasDetail(st.page) ? "detail" : "list" }

function act(action, arg, pending) { return { action: action, arg: arg === undefined ? null : arg, pending: pending || "" } }
var NONE = { action: "", arg: null, pending: "" }
var SWALLOW = { action: "none", arg: null, pending: "" }

// ---- resolve -----------------------------------------------------------------
// st: { page, sub, zone, mode, kind, pending, filterActive }
//   page   queue | inbox | agents | tasks | time
//   sub    Time sub-tab id (only for page time)
//   zone   list | detail | tabs | panel | filter | help
//   mode   "" | snooze | reply | agent (only for zone panel)
//   kind   selected queue item kind, "" when none
//   pending  "g" after a first g, else ""
// Returns { action, arg, pending }. action "" means not handled (let the key through);
// "none" means handled with no effect (the key is swallowed).
function resolve(ev, st) {
    var tok = tokenOf(ev)
    if (!tok) return NONE

    // help overlay: only close and scroll
    if (st.zone === "help") {
        if (tok === "Esc" || tok === "?") return act("help.close")
        if (tok === "j" || tok === "Down") return act("help.down")
        if (tok === "k" || tok === "Up") return act("help.up")
        return SWALLOW
    }

    // text entry: everything is typing except these
    if (textEntry(st)) {
        if (st.zone === "filter") {
            if (tok === "Esc" || tok === "Enter") return act("filter.close")
            if (tok === "Ctrl+u") return act("filter.clear")
            return NONE
        }
        if (tok === "Esc") return act("panel.close")
        if (tok === "Ctrl+Enter") return act("panel.submit")
        if (tok === "Ctrl+g" && st.mode === "agent") return act("panel.grant")   // Space would type, so Ctrl+g toggles
        return NONE
    }

    // snooze panel: pick by number or by cursor
    if (st.zone === "panel" && st.mode === "snooze") {
        var n = parseInt(tok, 10)
        if (n >= 1 && n <= SNOOZE_OPTIONS) return act("panel.pick", n)
        if (tok === "Esc") return act("panel.close")
        if (tok === "j" || tok === "Down") return act("panel.next")
        if (tok === "k" || tok === "Up") return act("panel.prev")
        if (tok === "Enter") return act("panel.pick", 0)   // 0: the highlighted option
        return SWALLOW
    }

    var pend = st.pending || ""

    // global
    if (tok === "?") return act("help.open")
    if (tok === "/") return act("filter.open")
    if (tok === "u") return act("undo")
    if (hasList(st.page)) {
        if (tok === "}") return act("view", 1)
        if (tok === "{") return act("view", -1)
        if (tok === "=") return act("group", 1)
    }
    var d = parseInt(tok, 10)
    if (tok.length === 1 && d >= 1 && d <= TABS.length) return act("tab", TABS[d - 1])
    if (tok === "Tab") return act("pane", nextPane(st.page, st.zone, 1))
    if (tok === "Backtab" || tok === "Shift+Tab") return act("pane", nextPane(st.page, st.zone, -1))
    if (tok === "]") return st.page === "time" ? act("subtab", nextSub(st.sub, 1)) : act("chip", 1)
    if (tok === "[") return st.page === "time" ? act("subtab", nextSub(st.sub, -1)) : act("chip", -1)
    if (tok === "Esc") {
        if (st.zone === "detail") return act("pane", "list")
        if (st.page === "time" && st.zone === "list") return act("pane", "tabs")   // up one level, not out
        if (st.filterActive) return act("filter.clear")
        return act("cc.close")
    }

    // sub-tab strip (Time): left and right move between sub-tabs
    if (st.zone === "tabs") {
        if (tok === "Left" || tok === "h") return act("subtab", nextSub(st.sub, -1))
        if (tok === "Right" || tok === "l") return act("subtab", nextSub(st.sub, 1))
        if (tok === "Enter" || tok === "Down" || tok === "j") return act("pane", "list")
        return NONE
    }

    // movement
    var up = tok === "k" || tok === "Up", down = tok === "j" || tok === "Down"
    if (st.zone === "detail") {
        if (tok === "Down") return act("scroll", 1)
        if (tok === "Up") return act("scroll", -1)
        if (tok === "Left" || tok === "h") return act("pane", "list")
    } else {
        if (down) return act("move", 1)
        if (up) return act("move", -1)
        if (tok === "n") return act("move", 1)
        if (tok === "e") return act("move", -1)
        if (tok === "g") return pend === "g" ? act("top") : act("", null, "g")
        if (tok === "G" || tok === "End") return act("bottom")
        if (tok === "Home") return act("top")
        if (tok === "PageDown" || tok === "Ctrl+d") return act("page", 1)
        if (tok === "PageUp" || tok === "Ctrl+u") return act("page", -1)
        if (st.page === "time") {
            if (tok === "Left" || tok === "h") return act("col", -1)
            if (tok === "Right" || tok === "l") return act("col", 1)
            if (tok === "J") return act("scroll", 1)      // scroll the side panel of Week and Heatmap
            if (tok === "K") return act("scroll", -1)
            if (tok === "p") return act("period", 1)
            if (tok === "P") return act("period", -1)
        } else if (hasDetail(st.page) && st.kind) {
            if (tok === "Right" || tok === "l") return act("pane", "detail")
        }
    }

    // primary
    if (tok === "Enter") {
        if (hasDetail(st.page) && st.zone === "list" && st.kind) return act("pane", "detail")
        return act("primary")
    }

    // page action keys
    if (st.zone === actionZone(st)) {
        var list = actionList(st)
        for (var i = 0; i < list.length; i++)
            if (list[i][0] === tok) return act("act." + list[i][1])
    }
    return NONE
}

// ---- help overlay ------------------------------------------------------------
// Rows for the `?` overlay, built from the same tables as resolve() so they cannot drift:
// [{ group, keys, label }]. Tests assert every action key appears here.
function helpRows(st) {
    var rows = [
        { group: "Go", keys: "1 2 3 4 5", label: "Queue, Inbox, Agents, Tasks, Time" },
        { group: "Go", keys: "Tab  Shift+Tab", label: "Next, previous pane" },
        { group: "Go", keys: "[  ]", label: st.page === "time" ? "Previous, next sub-tab" : "Previous, next filter chip" },
        { group: "Go", keys: "Esc", label: "Back, close, then leave the control centre" },
        { group: "Move", keys: "j k  n e  Up Down", label: "Next, previous row" },
        { group: "Move", keys: "g g  G", label: "Top, bottom" },
        { group: "Move", keys: "PageUp PageDown", label: "Page" },
        { group: "Move", keys: "Enter", label: "Open, or primary action" },
        { group: "Find", keys: "/", label: "Filter" },
        { group: "Find", keys: "?", label: "This help" },
        { group: "Find", keys: "u", label: "Undo the last done or snooze" }
    ]
    if (hasList(st.page)) {
        rows.push({ group: "Find", keys: "{  }", label: "Previous, next saved view" })
        rows.push({ group: "Find", keys: "=", label: "Group by: next grouping" })
    }
    if (st.mode === "agent") rows.push({ group: "Actions", keys: "Ctrl+g", label: "Toggle the one-reply grant" })
    if (st.page === "time") {
        rows.push({ group: "Time", keys: "h l  Left Right", label: "Previous, next day or column" })
        rows.push({ group: "Time", keys: "p  P", label: st.sub === "today" ? "Where time went: next, previous grouping" : "Next, previous period" })
        rows.push({ group: "Time", keys: "Enter", label: "Open the day, or the page's main action" })
        rows.push({ group: "Time", keys: "J  K", label: "Scroll the side panel (Week, Heatmap)" })
    }
    if (hasDetail(st.page)) rows.push({ group: "Move", keys: "l  Right", label: "Focus the detail pane" })
    var list = actionList(st)
    for (var i = 0; i < list.length; i++)
        rows.push({ group: "Actions", keys: list[i][0], label: list[i][2] })
    return rows
}

// ---- focus ring --------------------------------------------------------------
// One rule everywhere: the focused element draws a visible ring in the accent token. The view
// binds these numbers; it never invents its own. Tokens, not hex.
//   element  the focused row, chip, button or sub-tab
//   pane     the pane that holds keyboard focus (hairline, not the thick ring)
function ring(kind, focused, keyboard) {
    if (!focused || !keyboard) return { visible: false, width: 0, offset: 0, color: "accent" }
    if (kind === "pane") return { visible: true, width: 1, offset: 0, color: "accent" }
    return { visible: true, width: 2, offset: 2, color: "accent" }
}
