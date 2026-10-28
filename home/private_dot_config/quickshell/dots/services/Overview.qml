pragma Singleton
import Quickshell
import QtQuick

// The seam to the overview UI. The shell root loads OverviewHost once and parks it here;
// every bar's pill reaches it through this. Absent -> every call is a no-op.
Singleton {
  id: root

  property var host: null

  function toggleCard() { if (root.host) root.host.toggleCard(); }
  function openPanel(page) { if (root.host) root.host.openPanel(page); }
  function lamp(ms) { if (root.host) root.host.lamp(ms); }
}
