import QtQuick
import "../../theme"
import "../../common"
import "../../barpop"

// The candidate wallpaper with a sketch of the shell on it, drawn in the candidate palette:
// a bar with the task chip, a window, an alert and a lock card. The palette only changes the
// surface and the text; dots-theme fixes the accent in every mode, so that comes from Theme.
Item {
  id: root
  property string src: ""
  property string surface: ""        // "" = the shell's own
  property string text: ""
  readonly property color pSurface: surface !== "" ? surface : Theme.color.surface
  readonly property color pText: text !== "" ? text : Theme.color.fg
  height: 128

  Rectangle {
    anchors.fill: parent
    radius: Theme.radius.row
    color: Theme.color.surfaceContainer
    border.width: 1
    border.color: Theme.color.outlineVariant
    clip: true
    Image { anchors.fill: parent; source: root.src; asynchronous: true; fillMode: Image.PreserveAspectCrop; sourceSize.width: 400; sourceSize.height: 260 }

    Rectangle {
      x: 0; y: 0; width: parent.width; height: 26
      color: root.pSurface; opacity: 0.94
    }
    Row {
      x: 8; y: 0; height: 26; spacing: 8
      Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 8; height: 8; radius: 4; color: Theme.color.accent }
      Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: chip.implicitWidth + 16; height: 20; radius: 10
        color: Qt.alpha(Theme.color.accent, Theme.alpha.pressed); border.width: 1; border.color: Theme.color.accent
        Cap { id: chip; anchors.centerIn: parent; text: "Sample task 24:10"; dim: false; color: root.pText }
      }
    }
    Rectangle {
      x: 10; y: 36; width: 152; height: 82; radius: 8; color: root.pSurface; clip: true
      Rectangle { width: parent.width; height: 20; color: Qt.alpha(Theme.color.fg, 0.06); Cap { x: 8; anchors.verticalCenter: parent.verticalCenter; text: "Sample window"; dim: false; color: root.pText } }
      Column {
        x: 8; y: 28; spacing: 6
        Rectangle { width: 120; height: 5; radius: 3; color: root.pText; opacity: 0.5 }
        Rectangle { width: 92; height: 5; radius: 3; color: root.pText; opacity: 0.35 }
        Rectangle { width: 52; height: 5; radius: 3; color: Theme.color.accent }
      }
    }
    Rectangle {
      x: parent.width - 160; y: 34; width: 150; height: 40; radius: 8; color: root.pSurface
      Row { x: 8; y: 4; spacing: 6; Gly { anchors.verticalCenter: parent.verticalCenter; name: "bell"; box: 14; color: Theme.color.waiting } Cap { anchors.verticalCenter: parent.verticalCenter; text: "Sample alert"; dim: false; color: root.pText } }
      Rectangle { x: 8; y: 28; width: 100; height: 4; radius: 2; color: root.pText; opacity: 0.35 }
    }
    Rectangle {
      x: parent.width - 160; y: parent.height - 52; width: 150; height: 44; radius: 8; clip: true
      color: root.pSurface
      border.width: 1; border.color: Qt.alpha(Theme.color.fg, 0.2)
      Image { anchors.fill: parent; source: root.src; asynchronous: true; fillMode: Image.PreserveAspectCrop; sourceSize.width: 200; sourceSize.height: 120; opacity: 0.5 }
      Rectangle { anchors.fill: parent; color: Qt.alpha(Theme.color.bg, 0.5) }
      Row {
        anchors.centerIn: parent; spacing: 8
        DText { anchors.verticalCenter: parent.verticalCenter; text: "12:00"; role: "headline"; color: root.pText }
        Gly { anchors.verticalCenter: parent.verticalCenter; name: "lock"; box: 16; color: root.pText }
      }
    }
  }
}
