import Quickshell
import QtQuick

// Kube mode (`k:`): kubeconfig contexts. Read-only by default; switching the current context asks
// first (owner decision 6). Contract: docs/shell/specs/launcher-contract.md.
// Mode spec: docs/shell/specs/launcher-modes.md. Presentation only: `dots-launch-kube` runs kubectl
// with argv (config view, config use-context, config set-context --namespace).
Provider {
  id: root

  providerId: "kube"
  name: "Kube"
  prefix: "k:"
  icon: "cube"
  inAll: false      // context names never appear in All, Recents or screenshots of All
  allLimit: 1
  allWeight: 0.5
  sensitive: true

  readonly property var usedIcons: ({ context: "cube", namespace: "folder" })

  // set by the integration: the cluster the shell and the on-screen data point at, for the amber strip
  property string shellContext: ""
  property string viewContext: ""
  readonly property bool mismatch: shellContext !== "" && viewContext !== "" && shellContext !== viewContext

  property string view: "list"       // list | ns
  property string nsFor: ""
  property string note: ""           // "updated" when the kubeconfig changed on disk
  property string kubeState: ""      // "nokube" when there is no kubeconfig
  property string pendingKey: ""     // context waiting for the second activate (the confirm card)
  property string pendingNs: ""      // namespace chosen in ns view, applied before the switch

  property string bin: Quickshell.env("DOTS_LAUNCH_BIN") || (Quickshell.env("HOME") + "/.local/bin")
  readonly property string tool: bin + "/dots-launch-kube"
  property string lastText: ""

  function query(text) {
    root.lastText = text;
    root.pending = text;
    root.view = "list";
    root.pendingKey = "";
    q.restart();
  }

  // the core calls this on Esc over the confirm card
  function cancelConfirm() { root.pendingKey = ""; confirmTimer.stop(); }
  // the confirm card's "Peek instead (safer)" button: pinned --context, the global one stays
  function peekInstead() {
    var c = root.pendingKey;
    root.cancelConfirm();
    if (!c) return;
    root.run([root.tool, "act", "peek", c], function(o) { root.done(!!o.close, o.toast || ""); });
  }
  function backToList() { root.query(root.lastText); }

  function activate(rowIndex, actionIndex) {
    var row = root.rows[rowIndex];
    var act = row && row.actions ? row.actions[actionIndex] : null;
    if (!act || act.disabled) return false;
    if (act.verb === "use") return root.switchTo(row.key);
    if (act.verb === "ns") {
      root.run([root.tool, "namespaces", String(act.arg)], function(o) {
        root.rows = o.rows || [];
        root.hint = o.hint || "";
        root.nsFor = String(act.arg);
        root.view = "ns";
      });
      return true;
    }
    if (act.verb === "set-ns") {
      root.pendingNs = String(act.arg);
      root.run([root.tool, "act", "set-ns", String(act.arg)], function(o) {
        root.view = "list";
        root.switchTo(root.nsFor);
      });
      return true;
    }
    root.run([root.tool, "act", act.verb, String(act.arg)], function(o) {
      root.done(!!o.close, o.toast || "");
    });
    return true;
  }

  // First call asks (unless the helper says the tier needs no card); the second call, for the same
  // context, switches. The pending state expires so a cancelled card cannot confirm a later Enter.
  function switchTo(ctx) {
    if (root.pendingKey === ctx) {
      root.pendingKey = "";
      confirmTimer.stop();
      root.run([root.tool, "act", "use", ctx], function(o) {
        root.done(!!o.close, o.toast || "");
      });
      return true;
    }
    root.run([root.tool, "act", "confirm", ctx], function(o) {
      if (o.confirm) {
        root.pendingKey = ctx;
        confirmTimer.restart();
        root.confirmRequested(o.spec);
      } else {
        root.run([root.tool, "act", "use", ctx], function(p) { root.done(!!p.close, p.toast || ""); });
      }
    });
    return true;
  }

  function reset() {
    root.rows = [];
    root.error = "";
    root.busy = false;
    root.seq++;
    root.view = "list";
    root.pendingKey = "";
    root.note = "";
    confirmTimer.stop();
  }

  Timer { id: confirmTimer; interval: 15000; onTriggered: root.pendingKey = "" }

  Timer {
    id: q
    interval: root.debounce
    onTriggered: root.run([root.tool, "query", root.pending], function(o) {
      root.rows = o.rows || [];
      root.hint = o.hint || "";
      root.note = o.note || "";
      root.kubeState = o.state || "";
    })
  }
}
