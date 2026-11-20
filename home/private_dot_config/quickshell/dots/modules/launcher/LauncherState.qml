import QtQuick
import "js/Model.js" as M

// The launcher core's state: one field, one mode, the rows of that mode, a selection, the confirm card
// and a toast. It owns the field (providers never take focus) and routes keys through js/Model.js.
// Presentation reads it; providers are only called through query / activate / reset.
Item {
  id: root
  visible: false

  property var providers: []            // [All, ...]; All first (static list in Launcher.qml)
  property bool open: false
  property string blocked: ""           // "" | "locked" | "salah": closed card, providers are not queried

  property string query: ""
  property string modeId: "all"
  property int sel: 0
  property bool moved: false            // the user moved the selection: keep it across re-queries, else stay on the top row
  property string selKey: ""            // the selected row's key: the selection survives a re-query
  property int sec: 0                   // highlighted secondary action, 0 = none
  property var confirm: null            // { title, detail, danger, label } from a provider
  property int confirmAction: 0
  property string toast: ""
  property var rows: []
  property var pendingRecent: null      // the row whose activation is waiting for done()

  signal closeRequested()
  signal farewell(string text)          // a toast that would die with the window

  readonly property var all: providers.length > 0 ? providers[0] : null
  readonly property var tabs: providers.filter(function (p) { return p.providerId === "all" || p.prefix !== ""; })
  readonly property var mode: byId(modeId)
  readonly property var cur: rows.length > 0 && sel < rows.length ? rows[sel] : null
  readonly property int nActions: cur && cur.actions ? cur.actions.length : 0
  readonly property bool busy: mode ? mode.busy : false
  readonly property string hint: mode ? mode.hint : ""
  readonly property string status: M.statusLine(toast, busy, rows.length === 0, hint)

  function byId(pid) {
    for (var i = 0; i < providers.length; i++) if (providers[i].providerId === pid) return providers[i];
    return providers.length > 0 ? providers[0] : null;
  }

  // ---- open / close --------------------------------------------------------------------
  onOpenChanged: { if (open) begin(startPrefix); else end(); }
  property string startPrefix: ""

  function begin(prefix) {
    query = ""; confirm = null; toast = ""; sel = 0; selKey = ""; sec = 0; moved = false; rows = [];
    var m = prefix ? M.matchPrefix(prefix, providers) : null;
    modeId = m ? m.pid : "all";
    requery();
  }
  function end() {
    for (var i = 0; i < providers.length; i++) providers[i].reset();
    query = ""; confirm = null; toast = ""; rows = []; sel = 0; selKey = ""; sec = 0; moved = false; modeId = "all"; pendingRecent = null;
  }

  // ---- field ----------------------------------------------------------------------------
  // Panel calls this with the raw field text. A typed prefix switches mode and is removed from the field.
  function setText(t) {
    if (modeId === "all") {
      var m = M.matchPrefix(t, providers);
      if (m) { modeId = m.pid; t = m.rest; }
    }
    if (t !== query) { sel = 0; selKey = ""; sec = 0; moved = false; }
    query = t;
    requery();
  }
  function setMode(pid) { if (pid === modeId) return; modeId = pid; sel = 0; selKey = ""; sec = 0; moved = false; confirm = null; requery(); }

  function requery() {
    if (!open) return;
    if (blocked !== "") { rows = []; return; }
    var p = mode;
    if (p) p.query(query);
    refresh();
  }

  function refresh() {
    if (blocked !== "" || !open || !mode) { rows = []; return; }
    var p = mode;
    var list = p.error !== "" ? [{ key: "__error", title: p.error, sub: "", icon: "warning", _error: true,
                                   preview: { head: "Something went wrong", body: p.error }, actions: [] }]
                              : p.rows;
    rows = list;
    sel = moved ? M.reselect(list, selKey, sel) : 0;
    selKey = list.length > 0 ? list[sel].key : "";
    if (sec >= nActions) sec = 0;
  }
  onBlockedChanged: { if (blocked !== "") rows = []; else requery(); }

  // ---- actions ---------------------------------------------------------------------------
  function select(i) { if (i >= 0 && i < rows.length) { sel = i; selKey = rows[i].key; sec = 0; moved = true; } }

  function activate(a) {
    var r = cur;
    if (!r || r._error || !r.actions || a < 0 || a >= r.actions.length || r.actions[a].disabled) return false;
    confirmAction = a;
    pendingRecent = r;
    var ok = mode.activate(sel, a);
    if (!ok) pendingRecent = null;
    return ok;
  }
  function doConfirm() {
    var a = confirmAction;
    confirm = null;
    mode.activate(sel, a);        // the provider treats this second call as confirmed
  }
  function cancelConfirm() {
    confirm = null; pendingRecent = null;
    if (mode && typeof mode.cancelConfirm === "function") mode.cancelConfirm();   // optional hook: forget the pending row
  }

  function showToast(t) { toast = t; toastTimer.restart(); }

  function pressEscape() {
    var s = M.escapeStep({ confirm: confirm !== null, query: query });
    if (s === "confirm") cancelConfirm();
    else if (s === "clear") setText("");
    else closeRequested();
  }

  function handleKey(ev) {
    var n = nActions;
    var r = M.route({ key: ev.key, ctrl: (ev.modifiers & Qt.ControlModifier) !== 0, shift: (ev.modifiers & Qt.ShiftModifier) !== 0 },
                    { confirm: confirm !== null, queryEmpty: query === "", modeIsAll: modeId === "all", nActions: n });
    if (!r) return false;
    if (r.t === "escape") pressEscape();
    else if (r.t === "modeNext" || r.t === "modePrev") {
      var ids = tabs.map(function (p) { return p.providerId; });
      setMode(M.cycle(ids, modeId, r.t === "modeNext" ? 1 : -1));
    }
    else if (r.t === "move") { if (confirm === null) select(M.move(sel, rows.length, r.d)); }
    else if (r.t === "activate") activate(r.a);
    else if (r.t === "runSecondary") activate(sec > 0 ? sec : (n > 1 ? 1 : 0));
    else if (r.t === "secondary") sec = M.nextSecondary(sec, n, r.d);
    else if (r.t === "confirm") doConfirm();
    else if (r.t === "backMode") setMode("all");
    return true;
  }

  Timer { id: toastTimer; interval: 2500; onTriggered: root.toast = "" }

  Connections {
    target: root.mode
    function onRowsChanged() { root.refresh(); }
    function onErrorChanged() { root.refresh(); }
    function onDone(close, toast) {
      var pr = root.pendingRecent;
      root.pendingRecent = null;
      if (pr && root.all) {
        var row = pr._recent ? { key: pr._k, title: pr.title, sub: pr.sub, icon: pr.icon } : pr;
        root.all.note(pr._p || root.modeId, row, root.query);
      }
      if (close && toast !== "") root.farewell(toast);
      else if (toast !== "") root.showToast(toast);
      if (close) root.closeRequested();
    }
    function onConfirmRequested(spec) { root.confirm = spec; }
    function onModeRequested(pid) { root.setMode(pid); }
  }
}
