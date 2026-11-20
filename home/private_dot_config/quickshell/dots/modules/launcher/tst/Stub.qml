import QtQuick

// Test double for modes the launcher-modes team owns (Dictionary, Files, Fonts) and for a work-item
// source in All. Fixed rows filtered by substring; action 2 of `confirmFirst` rows asks to confirm.
Provider {
  id: root
  property var fixture: []
  property bool confirmFirst: false
  property bool pendingConfirm: false

  function query(text) {
    var q = text.trim().toLowerCase();
    var out = [];
    for (var i = 0; i < fixture.length; i++) {
      var r = fixture[i];
      if (q === "" || r.title.toLowerCase().indexOf(q) >= 0 || (r.match || "").indexOf(q) >= 0) out.push(r);
    }
    rows = out;
  }
  function cancelConfirm() { pendingConfirm = false; }
  function activate(rowIndex, actionIndex) {
    if (confirmFirst && actionIndex === 2 && !pendingConfirm) {
      pendingConfirm = true;
      confirmRequested({ title: "Send to agent?", detail: "This sends the file path to the focused agent pane.", danger: true, label: "Send" });
      return true;
    }
    pendingConfirm = false;
    done(true, "Done: " + rows[rowIndex].title);
    return true;
  }
}
