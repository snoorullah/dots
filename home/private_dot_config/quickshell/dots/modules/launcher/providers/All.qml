pragma ComponentBehavior: Bound
import Quickshell
import Quickshell.Io
import QtQuick
import "../js/Model.js" as M

// All: merges every `inAll` provider (contract section 4). Empty query -> Recents (last 8, never from a
// `sensitive` provider). Otherwise each source is queried in parallel, keeps at most `allLimit` rows, and
// rows appear as each one answers. Enter runs the row's own action 0 through its provider.
Provider {
  id: root

  providerId: "all"
  name: "All"
  prefix: ""
  icon: "squares-four"
  inAll: false
  hint: "Type to search apps, commands, math and more."

  property var sources: []              // the other providers, in chip order (set by the core)
  property var recents: []              // snapshots from launcher_recents.py
  property string text: ""
  property var pendingRecent: null      // { pid, key }: a Recents row waiting for its provider to answer
  property var confirmSrc: null         // the source that asked for a confirm card
  readonly property string py: Qt.resolvedUrl("../js/").toString().replace("file://", "")

  busy: root.anyBusy()

  function anyBusy() {
    for (var i = 0; i < sources.length; i++) if (sources[i].inAll && sources[i].busy) return true;
    return false;
  }
  function byId(pid) {
    for (var i = 0; i < sources.length; i++) if (sources[i].providerId === pid) return sources[i];
    return null;
  }

  function query(t) {
    text = t;
    pendingRecent = null;
    if (t.trim() === "") {
      for (var i = 0; i < sources.length; i++) sources[i].reset();
      rows = M.recentRows(recents);
      load();
      return;
    }
    for (var j = 0; j < sources.length; j++) if (sources[j].inAll) sources[j].query(t);
    merge();
  }

  function merge() {
    if (text.trim() === "") return;
    var groups = [];
    for (var i = 0; i < sources.length; i++) {
      var s = sources[i];
      if (!s.inAll) continue;
      var keep = [];
      for (var k = 0; k < s.rows.length; k++) if (!s.rows[k].noAll) keep.push(s.rows[k]);
      groups.push({ pid: s.providerId, weight: s.allWeight, limit: s.allLimit, rows: s.error ? [] : keep });
    }
    var out = M.rankAll(groups, M.recentMap(recents), M.nowSec());
    for (var n = 0; n < out.length; n++) {
      var src = byId(out[n]._p);
      // rankAll numbers rows within the filtered list; the source is activated by its own row index
      for (var q = 0; q < src.rows.length; q++) if (src.rows[q].key === out[n]._k) { out[n]._i = q; break; }
      if (!out[n].icon) out[n].icon = src.icon;
    }
    rows = out;
  }

  function onSource(src) {
    var p = pendingRecent;
    if (p && src.providerId === p.pid) {
      for (var i = 0; i < src.rows.length; i++) {
        if (src.rows[i].key === p.key) { pendingRecent = null; src.activate(i, 0); return; }
      }
    }
    merge();
  }

  function activate(rowIndex, actionIndex) {
    var r = rows[rowIndex];
    if (!r) return false;
    var src = byId(r._p);
    if (!src) return false;
    if (r._recent) {
      pendingRecent = { pid: r._p, key: r._k };
      pendTimer.restart();
      src.query(r._q);
      return true;
    }
    var own = src.rows[r._i];
    if (!own || own.key !== r._k) return false;
    return src.activate(r._i, actionIndex);
  }

  // The core calls this after an activation succeeded. Sensitive providers are never remembered.
  function note(pid, row, q) {
    var src = byId(pid);
    if (!src || src.sensitive || !row.key || row._error) return;
    var e = { p: pid, key: row.key, title: row.title || "", sub: row.sub || "", icon: row.icon || src.icon, q: q || row.title || "" };
    Quickshell.execDetached(["python3", root.py + "launcher_recents.py", "add", JSON.stringify(e)]);
    var keep = [];
    for (var i = 0; i < recents.length; i++) if (!(recents[i].p === pid && recents[i].key === row.key)) keep.push(recents[i]);
    e.ts = M.nowSec();
    recents = [e].concat(keep).slice(0, 50);
  }

  // the core calls this on Esc over the confirm card; the source forgets its pending row
  function cancelConfirm() {
    var s = confirmSrc;
    confirmSrc = null;
    if (s && typeof s.cancelConfirm === "function") s.cancelConfirm();
  }

  function reset() {
    text = "";
    pendingRecent = null;
    confirmSrc = null;
    rows = [];
    error = "";
    for (var i = 0; i < sources.length; i++) sources[i].reset();
  }

  function load() {
    if (!rp.running) rp.running = true;
  }

  Timer { id: pendTimer; interval: 3000; onTriggered: root.pendingRecent = null }

  Process {
    id: rp
    command: ["python3", root.py + "launcher_recents.py", "load"]
    stdout: StdioCollector {
      onStreamFinished: {
        try { root.recents = JSON.parse(text).rows || []; } catch (e) { root.recents = []; }
        if (root.text.trim() === "") root.rows = M.recentRows(root.recents);
      }
    }
  }

  Instantiator {
    model: root.sources
    delegate: Connections {
      required property var modelData
      target: modelData
      function onRowsChanged() { root.onSource(modelData); }
      function onErrorChanged() { root.merge(); }
      function onDone(close, toast) { root.done(close, toast); }
      function onConfirmRequested(spec) { root.confirmSrc = modelData; root.confirmRequested(spec); }
      function onModeRequested(pid) { root.modeRequested(pid); }
    }
  }
}
