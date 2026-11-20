import Quickshell
import QtQuick

// Commands (">"): saved commands from ~/.config/dots-launcher/commands.json. Run goes to a NEW herdr pane
// through js/launcher_cmds.py (argv only); Copy uses wl-copy; Edit opens the file in $EDITOR in a pane.
// "Save a new command" takes `name :: command :: tag, tag` typed in the field.
Provider {
  id: root

  providerId: "cmd"
  name: "Commands"
  prefix: ">"
  icon: "terminal-window"
  inAll: true
  allLimit: 3
  allWeight: 1.0
  hint: "No saved commands yet. Type  name :: command  and pick Save a new command."

  readonly property string py: Qt.resolvedUrl("../js/").toString().replace("file://", "")
  helper: ["python3", root.py + "launcher_cmds.py", "query"]

  function refresh() { run(helper.concat([pending]), function (o) { root.rows = o.rows || []; }); }

  function activate(rowIndex, actionIndex) {
    var r = rows[rowIndex];
    if (!r) return false;
    if (r.key === "__new") {
      if ((r.query || "").indexOf("::") < 0) { done(false, "Type  name :: command  in the field first."); return true; }
      run(["python3", root.py + "launcher_cmds.py", "save", r.query], function (o) { root.done(false, o.toast || "Saved"); root.refresh(); });
      return true;
    }
    if (actionIndex === 0) {
      run(["python3", root.py + "launcher_cmds.py", "run", r.key], function (o) { root.done(true, ""); });
      return true;
    }
    if (actionIndex === 1) {
      Quickshell.execDetached(["wl-copy", r.cmd || r.title]);
      done(true, "Copied the command");
      return true;
    }
    if (actionIndex === 2) {
      run(["python3", root.py + "launcher_cmds.py", "edit", r.key], function (o) { root.done(true, o.toast || "Editing"); });
      return true;
    }
    return false;
  }
}
