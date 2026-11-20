pragma ComponentBehavior: Bound
import Quickshell
import QtQuick
import "../barpop"
import "../../services"
import "js/Wall.js" as W
import "js/Acts.js" as A

// The wallpaper picker's behaviour with no window: scan, palettes, preview, apply, shuffle and
// the keyboard. Folder, palette and every action go through py/wp.py (local argv, JSON back).
// Arrowing previews on the desktop after 350 ms (swww, no cache write, no theme); Esc puts it
// back. The window (WallpaperPicker) shows `m`; the test smoke loads this alone.
Item {
  id: win

  readonly property string name: "wallpaper"
  readonly property string pyDir: Quickshell.shellDir + "/modules/wallpaper/py"
  readonly property string wpPy: pyDir + "/wp.py"
  readonly property bool wanted: Ui.open === name

  property bool typing: false            // the window says whether its search field has focus
  property string searchText: ""
  signal focusKeys()
  signal focusSearch(string text)
  signal clearSearch()

  property var st: W.initial()
  property var items: []
  property var folder: ({ name: "", count: 0, skipped: 0, exists: true })
  property var pals: ({})
  property string cur: ""
  property bool shuffle: false
  property bool lock: true
  property string suggest: ""
  property bool focusMode: false          // no focus-mode signal yet
  property string nextAt: ""

  SalahSource { id: salahSrc }
  readonly property bool salah: salahSrc.model.ok && salahSrc.model.cur >= 0

  readonly property var m: W.build({
    items: items, folder: folder, pals: pals, cur: cur, st: st, suggest: suggest, shuffle: shuffle, lock: lock,
    salah: salah, focusMode: focusMode, nextAt: nextAt,
    monitors: Quickshell.screens.map(function (s) { return s.name; })
  })

  function patch(o) {
    var n = {};
    for (var k in win.st) n[k] = win.st[k];
    for (var j in o) n[j] = o[j];
    win.st = n;
  }

  onWantedChanged: {
    if (wanted) {
      win.st = W.initial();
      win.run("scan", ["scan"]);
      win.run("state", ["state"]);
      win.focusKeys();
    } else previewTimer.stop();
  }

  function close() {
    if (win.m.previewing) disp.run(A.wp(wpPy, ["restore"]), "restore");
    Ui.close();
  }

  // ---- data ------------------------------------------------------------------------------
  Dispatcher {
    id: disp
    onFinished: (tag, code, out) => win.handle(tag, code, out)
  }

  function run(tag, args) { disp.run(A.wp(wpPy, args), tag); }

  function handle(tag, code, out) {
    var o = null;
    try { o = JSON.parse(out); } catch (e) { o = null; }
    if (!o) return;
    if (tag === "scan") {
      items = o.items;
      folder = { name: o.name, count: o.count, skipped: o.skipped, exists: o.exists };
      cur = o.cur || "";
      if (st.sel === "") patch({ sel: cur });
      askPalette();
    } else if (tag === "state") {
      shuffle = o.shuffle; lock = o.lock;
    } else if (tag.indexOf("palette:") === 0) {
      var path = tag.slice(8);
      var n = {};
      for (var k in pals) n[k] = pals[k];
      n[path] = o;
      pals = n;
    } else if (tag === "apply" || tag === "next") {
      if (o.ok) {
        if (!o.output) cur = o.path || cur;
        if (!closeAfterApply && !o.output) patch({ toast: true });
        toastTimer.restart();
        if (closeAfterApply) { closeAfterApply = false; Ui.close(); }
      } else closeAfterApply = false;
    } else if (tag === "undo") {
      if (o.ok) { cur = o.path; patch({ toast: false, sel: o.path }); }
    } else if (tag === "fav") {
      items = items.map(function (it) { return it.path === o.path ? { name: it.name, path: it.path, rel: it.rel, ok: it.ok, fav: o.fav } : it; });
    } else if (tag === "folder") {
      if (o.ok) { patch({ folderPrompt: false, query: "", sel: "" }); run("scan", ["scan"]); }
    }
  }

  // palettes are asked for one wallpaper at a time, the selected one first
  function askPalette() {
    var p = m.selPath;
    if (!p || pals[p] || palAsked[p]) return;
    palAsked[p] = true;
    run("palette:" + p, ["palette", p]);
  }
  property var palAsked: ({})
  onMChanged: askPalette()

  Timer { id: toastTimer; interval: 10000; onTriggered: win.patch({ toast: false }) }
  Timer {
    id: previewTimer
    interval: 350
    onTriggered: if (win.m.previewing) disp.run(A.wp(win.wpPy, ["preview", win.m.selPath]), "preview")
  }
  Timer {
    interval: 3600000
    repeat: true
    running: win.shuffle
    onTriggered: disp.run(A.wp(win.wpPy, win.salah ? ["shuffle-tick", "--hold", "salah"] : (win.focusMode ? ["shuffle-tick", "--hold", "focus"] : ["shuffle-tick"])), "next")
  }

  // ---- keys ------------------------------------------------------------------------------
  readonly property var keyNames: ({ 16777234: "left", 16777236: "right", 16777235: "up", 16777237: "down", 16777220: "enter", 16777221: "enter", 32: "space" })

  function side(s) {
    if (!s) return;
    if (s.type === "preview") previewTimer.restart();
    else if (s.type === "restore") { previewTimer.stop(); disp.run(A.wp(wpPy, ["restore"]), "restore"); }
    else if (s.type === "apply") {
      previewTimer.stop();
      disp.run(A.apply(wpPy, s.path, s.output, s.palette), "apply");
      if (!s.stay) win.closeAfterApply = true;
    }
    else if (s.type === "close") Ui.close();
    else if (s.type === "shuffle") { shuffle = s.on; run("state", ["state", "shuffle", s.on ? "on" : "off"]); }
    else if (s.type === "lock") { lock = s.on; run("state", ["state", "lock", s.on ? "on" : "off"]); }
    else if (s.type === "next" || s.type === "random") disp.run(A.wp(wpPy, win.salah ? ["next", "--hold", "salah"] : ["next"]), "next");
    else if (s.type === "fav") run("fav", ["fav", s.path]);
    else if (s.type === "undo") run("undo", ["revert"]);
  }
  property bool closeAfterApply: false

  function onKey(e) {
    var typing = win.typing;
    if (e.key === Qt.Key_Escape) {
      var r0 = W.nav(win.m, win.st, "esc");
      if (win.st.query !== "" || win.st.folderPrompt) { win.clearSearch(); win.focusKeys(); }
      win.patch(r0.st); win.side(r0.side);
      e.accepted = true; return;
    }
    var key = win.keyNames[e.key] || null;
    if (typing) {
      if (key === "enter" && win.st.folderPrompt) { win.run("folder", ["folder", win.searchText]); e.accepted = true; return; }
      if (key === "down" || key === "up") { win.focusKeys(); } else return;
    }
    if (key === null) {
      var t = String(e.text || "");
      if (t === "?" || t === "/" ) {
        if (t === "?") key = "?"; else { win.focusSearch(""); e.accepted = true; return; }
      } else if (/^[sSnNrRfFgGmMlLuU123]$/.test(t)) key = t.toLowerCase();
      else if (/^[a-zA-Z0-9]$/.test(t)) { win.focusSearch(t); win.patch({ query: t }); e.accepted = true; return; }
    }
    if (key === null) return;
    e.accepted = true;
    var r = W.nav(win.m, win.st, key);
    win.patch(r.st);
    win.side(r.side);
  }
}
