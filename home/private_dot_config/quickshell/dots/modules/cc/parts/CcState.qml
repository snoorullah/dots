pragma Singleton
import QtQuick
import Quickshell
import qs.modules.overview
import "../../../services"
import "../js/Queue.js" as Q

// The control centre's state and its read-only view of the overview feed. Everything the
// board computes in renderVals() lives here: filter, group, selection, which items are
// hidden for this session, and the status line. Nothing here is stored or sent. The only
// writes are local argv execs (xdg-open, and the overview's own Actions).
Singleton {
  id: root

  // ---- shell-owned: which tab ------------------------------------------------
  readonly property string tab: Ui.ccTab
  function setTab(t) { root.mode = ""; Ui.ccTab = t; }

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

  // ---- data -------------------------------------------------------------------
  readonly property var clock: Feed.nowDoc ? Feed.nowDoc.clock : null
  readonly property real sinceTs: (clock && clock.sinceTs) ? clock.sinceTs : 0
  readonly property real loginTs: (clock && clock.loginTs) ? clock.loginTs : 0   // today's session opened
  readonly property var feedItems: Feed.attDoc ? Feed.attDoc.items : []
  readonly property var all: Q.fromFeed(feedItems, Feed.nowTs, sinceTs)
  readonly property var shown: Q.select(all, { tab: tab, src: src, view: view, hidden: hidden })
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
  readonly property var agents: Q.agentRows(all, Feed.nowDoc ? Feed.nowDoc.agent : null,
                                            Feed.today ? Feed.today.byAgent : [])
  readonly property var nextTasks: {
    var out = []
    var items = Feed.attDoc ? Feed.attDoc.items : []
    for (var i = 0; i < items.length; i++) if (items[i].kind === "task") out.push(items[i])
    return out
  }
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

  function openUrl(item) {
    if (item.url && /^https?:\/\/[^\s]+$/.test(item.url)) {
      Quickshell.execDetached(["xdg-open", item.url])
      return true
    }
    return item.jump ? Actions.jump(item.raw) : false
  }

  function run(action, arg) {
    var it = root.sel
    if (!it || !Q.canRun(action, it)) return false
    if (action.effect === "mode") { root.mode = (root.mode === action.mode) ? "" : action.mode; return true }
    if (action.effect === "hide") { root.hide(it.id, "done", Q.statusFor(action.label)); return true }
    var ok = false
    if (action.effect === "open") ok = root.openUrl(it)
    else if (action.effect === "jump") ok = Actions.jump(it.raw) || root.openUrl(it)
    else if (action.effect === "breakdown") ok = Actions.breakdown(it.raw)
    if (ok) root.status = Q.statusFor(action.label)
    return ok
  }
  function runKey(key) {
    for (var i = 0; i < actions.length; i++) if (actions[i].key === key) return root.run(actions[i])
    return false
  }
  function snooze(label) { if (sel) root.hide(sel.id, "snoozed", Q.statusFor("Snooze", label)); }
}
