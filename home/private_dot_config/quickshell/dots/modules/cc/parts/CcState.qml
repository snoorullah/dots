pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.overview
import "../../../services"
import "../js/Queue.js" as Q
import "../js/Keys.js" as K
import "../js/AgentMetrics.js" as AM

// The control centre's state and its read-only view of the overview feed. Everything the
// board computes in renderVals() lives here: filter, group, selection, which items are
// hidden for this session, and the status line. Nothing here is stored or sent. The only
// writes are local argv execs (xdg-open, and the overview's own Actions).
Singleton {
  id: root

  // ---- shell-owned: which tab ------------------------------------------------
  readonly property string tab: Ui.ccTab
  function setTab(t) {
    root.mode = ""
    root.helpOpen = false
    root.filterFocus = false
    root.filterText = ""
    root.clearMarks()
    root.pending = ""
    root.pane = (t === "time") ? "tabs" : "list"
    Ui.ccTab = t
  }

  // ---- view state (the board's `state`) --------------------------------------
  property string src: "All"
  property string group: "Urgency"
  property string view: ""
  property string selId: ""
  property string mode: ""          // "" | reply | agent | snooze
  property bool grant: true
  property var hidden: ({})         // id -> done | snoozed (this session only)
  property string lastId: ""
  property string status: "Nothing else is waiting on you past these."
  property string timeTab: "Today"
  property string timeBy: "Item"
  property string taskView: "Today"

  // ---- agent-metrics.json and away.json (docs/shell/specs/cc-agent-metrics.md) ---------------
  // Read here so the Agents page and Time > Agents share one reader. Tests point the paths at a fixture.
  property string agentMetricsPath: Feed.dir + "/agent-metrics.json"
  property string agentMetricsText: ""
  property bool agentMetricsTried: false
  property string awayPath: Feed.dir + "/away.json"
  property string awayText: ""
  FileView {
    path: root.agentMetricsPath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: { root.agentMetricsText = text(); root.agentMetricsTried = true }
    onLoadFailed: { root.agentMetricsText = ""; root.agentMetricsTried = true }
  }
  FileView {
    path: root.awayPath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.awayText = text()
    onLoadFailed: root.awayText = ""
  }
  readonly property var agentMetrics: AM.parse(agentMetricsText)
  readonly property var awayModel: AM.away(awayText)
  // ref -> title, so a ticket's key can be said the way the rest of the panel says it
  readonly property var refTitles: {
    var m = {}, refs = Feed.mirrorDoc ? Feed.mirrorDoc.refs : []
    for (var i = 0; i < refs.length; i++) if (refs[i] && refs[i].ref) m[refs[i].ref] = refs[i].title || ""
    return m
  }

  // ---- data -------------------------------------------------------------------
  readonly property var clock: Feed.nowDoc ? Feed.nowDoc.clock : null
  readonly property real sinceTs: (clock && clock.sinceTs) ? clock.sinceTs : 0
  readonly property real loginTs: (clock && clock.loginTs) ? clock.loginTs : 0   // today's session opened
  readonly property var feedItems: Feed.attDoc ? Feed.attDoc.items : []
  readonly property var all: Q.fromFeed(feedItems, Feed.nowTs, sinceTs)
  readonly property var shown: {
    var s = Q.select(all, { tab: tab, src: src, view: view, hidden: hidden })
    if (needle === "") return s
    return s.filter(function (it) { return root.has(it.title + " " + it.who + " " + it.sub + " " + it.src) })
  }
  readonly property var sections: Q.group(shown, group)
  readonly property var flat: {
    var out = []
    for (var i = 0; i < sections.length; i++) for (var j = 0; j < sections[i].items.length; j++) out.push(sections[i].items[j])
    return out
  }
  readonly property var counts: Q.counts(all, hidden)
  readonly property string effId: {
    for (var i = 0; i < flat.length; i++) if (flat[i].id === selId) return selId
    return flat.length ? flat[0].id : ""
  }
  readonly property var sel: {
    for (var i = 0; i < flat.length; i++) if (flat[i].id === effId) return flat[i]
    return null
  }
  readonly property var actions: sel ? Q.actionsFor(sel.kind) : []
  readonly property var sourceRows: Q.sourceRows(Feed.sources)
  // task items that sit in a herdr pane, and the hook's per-session record for each
  readonly property var agentTasks: {
    var out = []
    for (var i = 0; i < feedItems.length; i++) {
      var t = feedItems[i]
      if (t && t.kind === "task" && t.jump && t.jump.sess && /^[0-9A-Za-z_-]+$/.test(String(t.jump.sess))) out.push(t)
    }
    return out
  }
  property var sessionDocs: ({})
  readonly property var agents: Q.agentRows(all, Feed.nowDoc ? Feed.nowDoc.agent : null,
                                            Feed.today ? Feed.today.byAgent : [], agentTasks, sessionDocs)
  readonly property var agentsShown: needle === "" ? agents : agents.filter(function (a) { return root.has(a.name + " " + a.task + " " + a.forRef + " " + a.state) })
  function setSession(id, text) {
    var doc = null
    try { doc = JSON.parse(text) } catch (e) { doc = null }
    if (!doc) return
    var m = {}
    for (var k in sessionDocs) m[k] = sessionDocs[k]
    m[id] = doc
    root.sessionDocs = m
  }
  Instantiator {
    model: root.agentTasks
    delegate: FileView {
      id: fv
      required property var modelData
      path: Feed.dir + "/sessions/" + modelData.jump.sess + ".json"
      watchChanges: true
      onFileChanged: reload()
      onLoaded: root.setSession(modelData.jump.sess, fv.text())
    }
  }
  readonly property var nextTasks: {
    var out = []
    var items = Feed.attDoc ? Feed.attDoc.items : []
    for (var i = 0; i < items.length; i++) if (items[i].kind === "task") out.push(items[i])
    return out
  }
  readonly property var tasksShown: needle === "" ? nextTasks : nextTasks.filter(function (t) { return root.has(Q.label(t.ticket, t.ref, t.title) + " " + (t.title || "") + " " + (t.actor || "")) })
  readonly property bool canUndo: lastId !== ""

  // ---- actions ------------------------------------------------------------------
  function pick(id) { root.selId = id; root.mode = ""; }
  function step(delta) { root.pick(Q.neighbour(flat, effId, delta)); }

  function hide(id, how, msg) {
    var h = {}
    for (var k in hidden) h[k] = hidden[k]
    var next = Q.afterRemoval(flat, id)
    h[id] = how
    root.hidden = h
    root.lastId = id
    root.status = msg
    root.mode = ""
    root.selId = next
  }
  function undo() {
    if (lastId === "") return
    var h = {}
    for (var k in hidden) if (k !== lastId) h[k] = hidden[k]
    root.hidden = h
    root.selId = lastId
    root.lastId = ""
    root.status = "Back on the list."
  }

  // Leave the control centre, then (for a link) bring the browser forward. Hyprland 0.56 runs a
  // Lua config: the dispatch payload is the hl.dsp.focus form, as in services/Hypr.qml. The
  // short delay lets the control centre's keyboard grab go first.
  readonly property string browserFocus: "hl.dsp.focus({ window = \"class:^(zen-beta|zen|firefox|librewolf|chromium|google-chrome|brave-browser)$\" })"
  Timer {
    id: browserTimer
    interval: 300
    onTriggered: Quickshell.execDetached(["hyprctl", "dispatch", root.browserFocus])
  }
  function leave(toBrowser) {
    Ui.cc = false
    if (toBrowser) browserTimer.restart()
  }

  function openUrl(item) {
    if (item.url && /^https?:\/\/[^\s]+$/.test(item.url)) {
      Quickshell.execDetached(["xdg-open", item.url])
      root.leave(true)
      return true
    }
    if (!item.jump) return false
    var ok = Actions.jump(item.raw)
    if (ok) root.leave(false)
    return ok
  }

  // the Agents page's link to the numbers: Time, Agents sub-tab, cursor in the page
  function openTimeAgents() {
    root.setTab("time")
    root.timeTab = "Agents"
    root.pane = "list"
  }

  // an Agents-tab row: focus its herdr pane, then close
  function jumpRow(row) {
    if (!row || !row.item || !row.item.raw) return false
    var ok = Actions.jump(row.item.raw)
    if (ok) root.leave(false)
    return ok
  }

  function run(action, arg) {
    var it = root.sel
    if (!it || !Q.canRun(action, it)) return false
    if (action.effect === "mode") { root.mode = (root.mode === action.mode) ? "" : action.mode; return true }
    if (action.effect === "hide") { root.hide(it.id, "done", Q.statusFor(action.label)); return true }
    var ok = false
    if (action.effect === "open") ok = root.openUrl(it)
    else if (action.effect === "jump") {
      ok = Actions.jump(it.raw)
      if (ok) root.leave(false)
      else ok = root.openUrl(it)
    }
    else if (action.effect === "breakdown") ok = Actions.breakdown(it.raw)
    if (ok) root.status = Q.statusFor(action.label)
    return ok
  }
  function runKey(key) {
    for (var i = 0; i < actions.length; i++) if (actions[i].key === key) return root.run(actions[i])
    return false
  }
  function snooze(label) { if (sel) root.hide(sel.id, "snoozed", Q.statusFor("Snooze", label)); }

  // ---- keyboard model (spec: docs/shell/specs/cc-keys.md) -----------------------------------
  // js/Keys.js is the pure keymap. This block holds the focus state it needs and applies the
  // action it returns. The view owns the one key handler (CcView.handle) and calls handleKey.
  property string pane: "list"          // list | detail | tabs: the pane that holds focus
  property bool helpOpen: false
  property bool filterFocus: false      // the filter field has the keyboard
  property string filterText: ""
  property bool keyboard: false         // true after a key press, false after a mouse press
  property bool chipFocus: false        // [ ] moved the chip or view strip: ring it
  property bool viewFocus: false        // { } stepped the saved views: ring the chosen one
  property bool groupFocus: false       // = stepped Group by: ring the chosen one
  property var remHidden: ({})          // Time > Reminders rows hidden this session
  function clearMarks() { chipFocus = false; viewFocus = false; groupFocus = false }
  property string pending: ""           // "g" after a first g
  property int snoozeIdx: 0
  property int taskIdx: 0
  property int agentIdx: 0
  signal detailScrolled(real dy)
  signal helpScrolled(real dy)
  signal closeAsked()
  signal timeScrolled(real dy)          // Time > Today: j k scroll Where time went

  readonly property var srcList: ["All", "Agent", "Slack", "Mail", "GitHub", "ERP", "Alert"]
  readonly property var taskViews: ["Today", "Board", "All"]
  readonly property var snoozeLabels: ["30 minutes", "After this task", "Tonight", "Tomorrow"]
  readonly property var subLabels: ({ today: "Today", week: "Week", days: "Days", heatmap: "Heatmap", zones: "Focus zones",
                                      progress: "Progress", report: "Report", screen: "Screen and health", reminders: "Reminders", agents: "Agents" })
  readonly property string needle: filterText.trim().toLowerCase()
  function has(hay) { return needle === "" || String(hay).toLowerCase().indexOf(needle) >= 0 }

  readonly property string pageId: tab === "work" ? "tasks" : tab
  readonly property string subId: {
    for (var k in subLabels) if (subLabels[k] === timeTab) return k
    return "today"
  }
  readonly property string zone: helpOpen ? "help" : (mode !== "" ? "panel" : (filterFocus ? "filter" : pane))
  readonly property string kindNow: ((pageId === "queue" || pageId === "inbox") && sel) ? sel.kind : ""
  readonly property var keyState: ({ page: pageId, sub: subId, zone: zone, mode: mode, kind: kindNow, pending: pending, filterActive: needle !== "" })
  readonly property int agentCur: Math.max(0, Math.min(agentIdx, agentsShown.length - 1))
  readonly property int taskCur: Math.max(0, Math.min(taskIdx, tasksShown.length - 1))
  readonly property var helpGroups: {
    var rows = K.helpRows(keyState), out = [], at = {}
    for (var i = 0; i < rows.length; i++) {
      var g = rows[i].group
      if (at[g] === undefined) { at[g] = out.length; out.push({ name: g, rows: [] }) }
      out[at[g]].rows.push(rows[i])
    }
    return out
  }
  // the five most useful keys for the page and zone, for the footer
  readonly property string hint: {
    if (helpOpen) return "j k scroll · ? or Esc close"
    if (zone === "filter") return "type to filter · Enter keep · Ctrl+u clear · Esc leave"
    if (zone === "panel") return mode === "snooze" ? "1-4 pick · j k move · Enter pick · Esc close" : "type · Ctrl+Enter send (off) · Esc close"
    var acts = K.actionList(keyState).slice(0, 3).map(function (a) { return a[0] + " " + a[2].toLowerCase() })
    if (pageId === "queue" || pageId === "inbox") {
      if (zone === "detail") return acts.concat(["h back", "? help"]).join(" · ")
      return "j k move · Enter open · / filter · [ ] source · ? help"
    }
    if (pageId === "time") return zone === "tabs" ? "h l sub-tab · j or Enter into the page · ? help · 1-5 tabs" : (subId === "today" ? "j k scroll · p P group · s focus · b break · ? help · Esc tabs" : "j k move · h l column · p P period · ? help · Esc tabs")
    return ["j k move"].concat(acts, ["/ filter", "? help"]).join(" · ")
  }

  function say(msg) { root.status = msg }
  onFilterTextChanged: { root.taskIdx = 0; root.agentIdx = 0 }
  onModeChanged: if (mode === "snooze") root.snoozeIdx = 0
  Connections {
    target: Ui
    function onCcChanged() {
      if (!Ui.cc) return
      root.helpOpen = false; root.filterFocus = false; root.mode = ""; root.pending = ""
      root.pane = (root.tab === "time") ? "tabs" : "list"
    }
  }

  function evOf(e) {
    var m = e.modifiers, t = e.text || ""
    var ctrl = !!(m & Qt.ControlModifier)
    if (ctrl && e.key >= 0x41 && e.key <= 0x5a) t = String.fromCharCode(e.key + 32)   // Ctrl+D arrives as a control char
    return { key: e.key, text: t, shift: !!(m & Qt.ShiftModifier), ctrl: ctrl, alt: !!(m & Qt.AltModifier) }
  }

  // One key press. `pg` is the active page item: if it defines handleKey(res, state) it gets
  // the resolved action first and returns true when it took it (the Time page does).
  function handleKey(e, pg) {
    if (e.modifiers & (Qt.AltModifier | Qt.MetaModifier)) return false
    root.keyboard = true
    var st = root.keyState
    var res = K.resolve(root.evOf(e), st)
    root.pending = res.pending || ""
    if (res.pending === "g") return true
    if (!res.action) return false
    if (pg && typeof pg.handleKey === "function" && pg.handleKey(res, st)) return true
    return root.apply(res, st)
  }

  function curIdx() {
    if (pageId === "agents") return agentCur
    if (pageId === "tasks") return taskCur
    for (var i = 0; i < flat.length; i++) if (flat[i].id === effId) return i
    return 0
  }
  function listLen() { return pageId === "agents" ? agentsShown.length : (pageId === "tasks" ? tasksShown.length : flat.length) }
  function moveTo(i) {
    var n = listLen()
    if (n === 0) return
    var j = Math.max(0, Math.min(n - 1, i))
    if (pageId === "agents") root.agentIdx = j
    else if (pageId === "tasks") root.taskIdx = j
    else if (pageId === "queue" || pageId === "inbox") root.pick(flat[j].id)
  }
  function stepList(arr, cur, dir) { var i = arr.indexOf(cur); return arr[(Math.max(0, i) + (dir < 0 ? arr.length - 1 : 1)) % arr.length] }

  function failed(a) { root.say(a ? (a.effect === "stub" ? a.label + " is read-only for now." : "Nothing to " + a.label.toLowerCase() + " here.") : "Nothing selected.") }
  function runNamed(name) {
    var list = (K.ACTIONS[kindNow] || []).concat(K.ACTIONS_COMMON), key = ""
    for (var i = 0; i < list.length; i++) if (list[i][1] === name) key = list[i][0]
    for (var j = 0; j < actions.length; j++) {
      if (actions[j].key !== key) continue
      if (!root.run(actions[j])) root.failed(actions[j])
      return
    }
  }
  function openTask(t) {
    if (!t) return root.say("Nothing selected.")
    var ok = Actions.jump(t)
    if (ok) { root.leave(false); return }
    root.say("Nothing to open for this task.")
  }

  function apply(res, st) {
    var a = res.action, arg = res.arg
    var pgId = st.page
    if (a === "none") return true
    if (a === "tab") { root.setTab(arg === "tasks" ? "work" : arg); return true }
    if (a === "undo") { root.clearMarks(); if (root.canUndo) root.undo(); else root.say("Nothing to undo."); return true }
    if (a === "view") {
      root.clearMarks(); root.viewFocus = true
      root.view = K.nextView(root.view, arg)
      root.say(root.view === "" ? "Saved view: none." : "Saved view: " + root.view + ".")
      return true
    }
    if (a === "group") {
      root.clearMarks(); root.groupFocus = true
      root.group = K.nextGroup(root.group, arg)
      root.say("Grouped by " + root.group.toLowerCase() + ".")
      return true
    }
    if (a === "panel.grant") { root.grant = !root.grant; root.say(root.grant ? "It may reply once, this thread only." : "No reply is granted."); return true }
    if (a === "pane") {
      root.clearMarks()
      if (arg === "detail" && !sel) return true
      root.pane = arg
      return true
    }
    if (a === "subtab") { root.timeTab = root.subLabels[arg]; root.clearMarks(); root.chipFocus = true; return true }
    if (a === "chip") {
      root.clearMarks(); root.chipFocus = true
      if (pgId === "tasks") root.taskView = root.stepList(root.taskViews, root.taskView, arg)
      else if (pgId === "queue" || pgId === "inbox") root.src = root.stepList(root.srcList, root.src, arg)
      return true
    }
    if (pgId === "time" && st.sub === "today") {         // Today has no metrics cursor: p P group, s focus, b break
      if (a === "period") { root.timeBy = K.nextBy(root.timeBy, arg); root.say("Where time went: by " + root.timeBy.toLowerCase() + "."); return true }
      if (a === "move") { root.timeScrolled(arg * 40); return true }
      if (a === "page") { root.timeScrolled(arg * 160); return true }
      if (a === "top") { root.timeScrolled(-100000); return true }
      if (a === "bottom") { root.timeScrolled(100000); return true }
      if (a === "act.focus") {
        var run = Feed.focusRunning
        if (Actions.focus(run ? "stop" : "start")) root.say(run ? "Stopping focus." : "Starting focus.")
        return true
      }
      if (a === "act.break") { root.say(Actions.focus("break") ? "Break asked." : "Could not ask for a break."); return true }
    }
    if (a === "move") { root.clearMarks(); root.moveTo(root.curIdx() + arg); return true }
    if (a === "top") { root.moveTo(0); return true }
    if (a === "bottom") { root.moveTo(root.listLen() - 1); return true }
    if (a === "page") { root.moveTo(root.curIdx() + arg * 8); return true }
    if (a === "scroll") { root.detailScrolled(arg * 60); return true }
    if (a === "col" || a === "period") return true     // Time keys the Time page does not take
    if (a === "primary") {
      if (pgId === "agents") { if (!root.jumpRow(agentsShown[agentCur])) root.say("Nothing to open for this agent."); return true }
      if (pgId === "tasks") { root.openTask(tasksShown[taskCur]); return true }
      if (pgId === "queue" || pgId === "inbox") {
        var pr = null
        for (var i = 0; i < actions.length; i++) if (actions[i].primary) pr = actions[i]
        if (pr && !root.run(pr)) root.failed(pr)
      }
      return true
    }
    if (a === "filter.open") {
      if (pgId === "time") root.say("Nothing to filter on this page.")
      else root.filterFocus = true
      return true
    }
    if (a === "filter.close") { root.filterFocus = false; return true }
    if (a === "filter.clear") { root.filterText = ""; root.filterFocus = false; return true }
    if (a === "help.open") { root.helpOpen = true; return true }
    if (a === "help.close") { root.helpOpen = false; return true }
    if (a === "help.down") { root.helpScrolled(60); return true }
    if (a === "help.up") { root.helpScrolled(-60); return true }
    if (a === "panel.close") { root.mode = ""; return true }
    if (a === "panel.next") { root.snoozeIdx = Math.min(root.snoozeLabels.length - 1, root.snoozeIdx + 1); return true }
    if (a === "panel.prev") { root.snoozeIdx = Math.max(0, root.snoozeIdx - 1); return true }
    if (a === "panel.pick") { root.snooze(root.snoozeLabels[(arg > 0 ? arg : root.snoozeIdx + 1) - 1]); return true }
    if (a === "panel.submit") { root.say("Sending stays off. Nothing is sent from a key press."); return true }
    if (a === "cc.close") { root.closeAsked(); return true }
    if (a.indexOf("act.") === 0) {
      var name = a.substring(4)
      if (pgId === "queue" || pgId === "inbox") root.runNamed(name)
      else if (pgId === "agents" && name === "open") { if (!root.jumpRow(agentsShown[agentCur])) root.say("Nothing to open for this agent.") }
      else if (pgId === "agents" && name === "time") root.openTimeAgents()
      else if (pgId === "tasks" && name === "open") root.openTask(tasksShown[taskCur])
      else if (pgId === "tasks" && name === "breakdown") {
        var t = tasksShown[taskCur]
        root.say(t && Actions.breakdown(t) ? "Breaking it down. An agent starts it." : "Nothing to break down here.")
      } else root.say("Not available on this page yet.")
      return true
    }
    return true
  }
}
