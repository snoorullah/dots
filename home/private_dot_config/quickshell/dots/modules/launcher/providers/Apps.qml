import Quickshell
import QtQuick
import "../js/Model.js" as M

// Apps: installed desktop entries (Quickshell DesktopEntries). All-only (no chip, no prefix).
// Launch goes through `dots-launch <desktop-id>`, the same path otter-launcher uses, which starts the
// app detached and reports a crash at start.
Provider {
  id: root

  providerId: "apps"
  name: "Apps"
  prefix: ""
  icon: "app-window"
  inAll: true
  allLimit: 3
  allWeight: 1.0
  hint: "No installed app matches."

  property string lastText: ""

  function query(text) {
    lastText = text;
    var q = text.trim();
    if (q === "") { rows = []; return; }
    var apps = DesktopEntries.applications.values;
    var out = [];
    for (var i = 0; i < apps.length; i++) {
      var e = apps[i];
      if (e.noDisplay) continue;
      var s = M.maxOf(M.fuzzy(q, e.name), 0.85 * M.fuzzy(q, e.genericName), 0.7 * M.fuzzy(q, (e.keywords || []).join(" ")),
                       0.6 * M.fuzzy(q, e.comment));
      if (s <= 0) continue;
      out.push({ key: e.id, title: e.name, sub: e.genericName || e.comment || "Application", score: s,
                 icon: e.runInTerminal ? "terminal-window" : "app-window",
                 preview: { head: e.name, body: (e.comment || e.genericName || "Application") + "\n\nDesktop entry: " + e.id },
                 actions: [{ label: "Open", primary: true }, { label: "Copy name" }] });
    }
    out.sort(function (a, b) { return b.score - a.score || (a.title < b.title ? -1 : 1); });
    rows = out.slice(0, 30);
  }

  // entries are scanned asynchronously at shell start: answer again once they arrive
  Connections {
    target: DesktopEntries.applications
    function onValuesChanged() { if (root.lastText !== "") root.query(root.lastText); }
  }

  function activate(rowIndex, actionIndex) {
    var r = rows[rowIndex];
    if (!r) return false;
    if (actionIndex === 0) {
      Quickshell.execDetached(["dots-launch", r.key]);
      done(true, "");           // dots-launch reports a crash at start itself
      return true;
    }
    if (actionIndex === 1) {
      Quickshell.execDetached(["wl-copy", r.title]);
      done(true, "Copied " + r.title);
      return true;
    }
    return false;
  }
}
