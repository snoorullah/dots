import Quickshell.Services.Notifications
import QtQuick
import "../theme"
import "../common"

// One toast: 380 wide, padding 16, radius 14. Click opens the source, × dismisses, action
// buttons run the app's actions (NotifCard). It hides itself when its time is up (the
// notification stays in the centre) and re-appears when the app REPLACES it in place:
// the server updates the same Notification object, so summary/body changing is the cue.
Item {
  id: toast

  required property var modelData      // Notification
  property var server: null           // NotifServer: decides what may pop up (dnd, focus)
  property bool alive: true

  readonly property bool critical: modelData.urgency === NotificationUrgency.Critical
  readonly property int lifetime: modelData.expireTimeout > 0 ? modelData.expireTimeout * 1000 : 6000

  readonly property bool shown: alive && (server ? server.lets(modelData) : true)

  width: 380
  implicitHeight: shown ? box.height : 0
  height: implicitHeight
  visible: shown

  Connections {
    target: toast.modelData
    function onSummaryChanged() { toast.revive(); }
    function onBodyChanged() { toast.revive(); }
  }

  function revive() {
    toast.alive = true;
    life.restart();
  }

  Timer {
    id: life
    interval: toast.lifetime
    running: toast.alive && !toast.critical && !hover.hovered
    onTriggered: toast.alive = false
  }

  Surface {
    id: box
    corner: Theme.radius.card
    border.color: Qt.alpha(Theme.color.outline, Theme.alpha.divider)
    width: parent.width
    height: col.implicitHeight + 2 * Theme.space.xxl

    NotifCard {
      id: col
      x: Theme.space.xxl
      y: Theme.space.xxl
      // a critical toast reserves a column on the right for the mark, so the × stays visible
      width: parent.width - 2 * Theme.space.xxl - (toast.critical ? mark.width + Theme.space.s : 0)
      notification: toast.modelData
      summaryLines: 2
      bodyLines: 4
      onOpened: toast.alive = false
    }

    // critical is a shape, not an edge colour
    StatusMark {
      id: mark
      visible: toast.critical
      level: "failed"
      anchors.top: parent.top
      anchors.right: parent.right
      anchors.topMargin: Theme.space.xxl + (Theme.font.line.body - height) / 2     // centred on the header row
      anchors.rightMargin: Theme.space.xxl
    }

    HoverHandler { id: hover }
  }
}
