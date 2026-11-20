pragma ComponentBehavior: Bound
import QtQuick
import "../../theme"
import "../../common"
import ".."

// Profiles, collapsed: only the ACTIVE profile shows (icon + name). Hovering the strip, or
// clicking the active one, opens the rest as icons; clicking one asks for that profile.
// The active profile is the one that owns the focused workspace (js/Profiles.js).
Row {
  id: root

  property var profiles: []        // [{ name, icon }]
  property string active: ""
  property bool pinOpen: false     // test hook: show the expanded strip as if hovered
  property bool pinned: false      // opened by a click on the active profile
  readonly property bool expanded: pinOpen || pinned || hover.hovered
  readonly property int dot: Theme.space.xxxl
  signal profileRequested(string name)
  signal switcherRequested(real x)   // the active chip opens the workspace switcher

  height: parent ? parent.height : dot
  spacing: Theme.space.s

  HoverHandler {
    id: hover
    onHoveredChanged: if (!hovered) root.pinned = false
  }

  Repeater {
    model: root.profiles

    Rectangle {
      id: p
      required property var modelData
      readonly property bool on: p.modelData.name === root.active

      objectName: "profile"
      visible: p.on || root.expanded
      width: pRow.implicitWidth + 2 * Theme.space.m
      height: Theme.space.xxxl + Theme.space.s + Theme.space.s + 2   // 30, as a workspace
      anchors.verticalCenter: parent.verticalCenter
      radius: Theme.radius.pill
      color: p.on ? Theme.color.surfaceContainerHigh
           : (tap.containsMouse ? Qt.alpha(Theme.color.fg, Theme.alpha.hover) : "transparent")

      Row {
        id: pRow
        x: Theme.space.m
        height: parent.height
        spacing: Theme.space.s

        Glyph {
          anchors.verticalCenter: parent.verticalCenter
          name: p.modelData.icon
          active: p.on
          box: 17
          color: p.on ? Theme.color.fg : Theme.color.fgDim
        }
        DText {
          objectName: "profileName"
          anchors.verticalCenter: parent.verticalCenter
          visible: p.on
          role: "bodyS"
          text: p.modelData.name
        }
      }

      MouseArea {
        id: tap
        anchors.fill: parent
        hoverEnabled: true
        onClicked: {
          if (p.on) { root.pinned = false; root.switcherRequested(p.mapToItem(null, p.width / 2, 0).x) }
          else { root.pinned = false; root.profileRequested(p.modelData.name) }
        }
      }
    }
  }
}
