pragma ComponentBehavior: Bound
import QtQuick
import "../../theme"
import "../../common"
import "../../barpop"

// Board row 2 (40 px): one chip per mode with its prefix. The active chip is raised, the rest are dim.
// Twelve chips are wider than the card, so the strip sits in a clipped, scrollbar-less Flickable and the
// active chip is scrolled fully into view whenever the mode changes (click, prefix, Tab, Shift+Tab).
Item {
  id: root

  required property var st
  implicitHeight: 40

  readonly property int edge: 10

  // bring the active chip fully inside the visible strip, animated; no-op while it already is
  function reveal() {
    var target = fl.contentX;
    for (var i = 0; i < chips.count; i++) {
      var c = chips.itemAt(i);
      if (!c || root.st.tabs[i].providerId !== root.st.modeId) continue;
      var left = strip.x + c.x - root.edge, right = strip.x + c.x + c.width + root.edge;
      if (left < fl.contentX) target = left;
      else if (right > fl.contentX + fl.width) target = right - fl.width;
      break;
    }
    target = Math.max(0, Math.min(target, fl.contentWidth - fl.width));
    if (Math.abs(target - fl.contentX) < 1) return;
    scroll.stop();
    scroll.from = fl.contentX;
    scroll.to = target;
    scroll.start();
  }

  Connections {
    target: root.st
    function onModeIdChanged() { root.reveal(); }
  }

  Flickable {
    id: fl
    objectName: "tabStrip"
    anchors.fill: parent
    clip: true
    contentWidth: strip.width + 2 * root.edge
    contentHeight: height
    flickableDirection: Flickable.HorizontalFlick
    boundsBehavior: Flickable.StopAtBounds
    interactive: contentWidth > width
    onContentWidthChanged: Qt.callLater(root.reveal)
    onWidthChanged: Qt.callLater(root.reveal)

    NumberAnimation {
      id: scroll
      target: fl
      property: "contentX"
      duration: Theme.motion.base
      easing.type: Theme.motion.easeOut
    }

    Row {
      id: strip
      x: root.edge
      anchors.verticalCenter: parent.verticalCenter
      spacing: 2

      Repeater {
        id: chips
        model: root.st.tabs
        delegate: Rectangle {
          id: chip
          required property var modelData
          readonly property bool on: root.st.modeId === modelData.providerId
          objectName: "tab"
          property string tabId: modelData.providerId
          property bool active: on
          height: 28
          width: lab.implicitWidth + 20
          radius: 8
          color: on ? Theme.color.surfaceContainerHigh : "transparent"

          Row {
            id: lab
            anchors.centerIn: parent
            spacing: 6
            Gly { name: chip.modelData.icon; box: 14; color: chip.on ? Theme.color.fg : Theme.color.fgDim; anchors.verticalCenter: parent.verticalCenter }
            DText { text: chip.modelData.name; role: "bodyS"; font.pixelSize: Theme.font.size.caption; color: chip.on ? Theme.color.fg : Theme.color.fgDim; anchors.verticalCenter: parent.verticalCenter }
            DText { visible: chip.modelData.prefix !== ""; text: chip.modelData.prefix; role: "bodyS"; font.pixelSize: Theme.font.size.caption; dim: true; anchors.verticalCenter: parent.verticalCenter }
          }
          MouseArea { anchors.fill: parent; onClicked: root.st.setMode(chip.modelData.providerId) }
        }
      }
    }
  }
}
