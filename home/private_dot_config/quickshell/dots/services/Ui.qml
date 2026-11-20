pragma Singleton
import Quickshell
import QtQuick

// Which popout is open, where it hangs from. One at a time: opening one closes the rest.
Singleton {
  id: root

  property string open: ""         // calendar | media | quick | center | ""
  property string screenName: ""
  property real anchorX: 0         // window-local x the popout's notch points at

  function toggle(name, screen, x) {
    if (root.open === name) { root.open = ""; return; }
    root.screenName = screen || root.screenName;
    if (x !== undefined && x >= 0) root.anchorX = x;
    root.open = name;
  }
  function close() { root.open = ""; }

  // Popout names (one at a time, via toggle): calendar | salah | waiting | agent | tray | media | system | center | workspaces | session | away | launcher | winswitch | wallpaper | logomenu | tiling | scratchpad | restore
  // Full-screen control centre and the edge sidebar are separate from popouts.
  property bool cc: false
  property string ccTab: "queue"   // queue | inbox | agents | work | time
  property bool sidebar: false
  function toggleCc(tab) {
    if (root.cc && (!tab || tab === root.ccTab)) { root.cc = false; return; }
    if (tab) root.ccTab = tab;
    root.open = ""; root.sidebar = false; root.cc = true;
  }
  function toggleSidebar() { root.sidebar = !root.sidebar; if (root.sidebar) { root.cc = false; root.open = ""; } }
  function closeAll() { root.open = ""; root.cc = false; root.sidebar = false; }
}
