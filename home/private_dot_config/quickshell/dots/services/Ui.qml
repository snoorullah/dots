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
}
