import Quickshell
import QtQuick
import "../theme"
import "../common"
import "js/Moments.js" as M

// The return chip: "Detour 4m · back to HD 4412  Super+Alt+B". Place it in the bar or the shell;
// it is zero width and invisible while there is no detour, so it never leaves a gap.
// Click (or the shell's Super+Alt+B bind, dots.ret back) returns to the terminal's workspace and runs
// `dots-jump <ref>`: local only.
// `detour` and `task` default to the live now.json; tests and callers may override them.
Item {
  id: chip

  property var detour: MomentState.detour
  property var task: MomentState.task
  readonly property bool active: !!detour && detour.active === true

  signal returned()

  function back() {
    if (!chip.active) return false;
    var list = M.backArgvs(chip.task, MomentState.focusState.homeWs);
    if (list.length === 0) return false;
    for (var i = 0; i < list.length; i++) {
      var argv = list[i];
      Quickshell.execDetached(argv);
    }
    chip.returned();
    return true;
  }

  implicitWidth: active ? face.implicitWidth : 0
  implicitHeight: 32
  width: implicitWidth
  height: implicitHeight
  visible: active

  Rectangle {
    id: face
    objectName: "returnFace"
    implicitWidth: row.implicitWidth + 20
    width: parent.width
    height: parent.height
    radius: Theme.radius.chip + 2
    color: Qt.alpha(Theme.color.waiting, Theme.alpha.wash)

    Row {
      id: row
      anchors.centerIn: parent
      spacing: Theme.space.m
      Icon {
        anchors.verticalCenter: parent.verticalCenter
        name: MomentIcons.back
        size: Theme.font.size.title
        color: Theme.color.waiting
      }
      DText {
        anchors.verticalCenter: parent.verticalCenter
        role: "bodyS"
        color: Theme.color.waiting
        font.weight: Font.Medium
        text: chip.detour ? chip.detour.text : ""
      }
      DText {
        anchors.verticalCenter: parent.verticalCenter
        font.pixelSize: Theme.font.size.caption
        color: Theme.color.waiting
        opacity: 0.8
        text: MomentState.backKey
      }
    }

    Rectangle {
      anchors.fill: parent
      radius: face.radius
      color: Theme.color.fg
      opacity: ma.containsMouse ? Theme.alpha.hover : 0
    }
    MouseArea {
      id: ma
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: chip.back()
    }
  }
}
