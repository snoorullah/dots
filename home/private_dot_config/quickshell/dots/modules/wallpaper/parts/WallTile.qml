pragma ComponentBehavior: Bound
import QtQuick
import "../../theme"
import "../../barpop"

// One wallpaper: the image at 16:10, five palette swatches, the name and a contrast dot.
// An unreadable file is dimmed, shows a warning glyph and can never be selected.
Item {
  id: root
  property var t: ({})
  property string src: ""
  signal picked()
  signal favourite()
  signal dismissed()

  width: 133
  height: 126

  Rectangle {
    anchors.fill: parent
    radius: Theme.radius.row
    color: Theme.color.bg
    border.width: 2
    border.color: root.t.ring === "accent" ? Theme.color.accent : (root.t.ring === "cur" ? Theme.color.unknown : "transparent")
    opacity: root.t.isBroken ? 0.5 : 1
    clip: true

    Rectangle {
      id: art
      x: 2; y: 2
      width: parent.width - 4
      height: Math.round(width * 10 / 16)
      color: Theme.color.surfaceContainer
      Image {
        anchors.fill: parent
        visible: !root.t.isBroken && !root.t.loading && root.src !== ""
        source: root.src
        asynchronous: true
        cache: true
        fillMode: Image.PreserveAspectCrop
        sourceSize.width: 266
        sourceSize.height: 166
      }
      Rectangle {
        visible: !!root.t.isCur
        x: 6; y: 6; width: 20; height: 20; radius: 10
        color: Theme.color.accent
        Gly { anchors.centerIn: parent; name: "check"; box: 12; color: Theme.color.accentFg }
      }
      Gly { visible: !!root.t.isBroken; anchors.centerIn: parent; name: "warning"; box: 24; color: Theme.color.fgDim }
      Rectangle {
        visible: !!root.t.isSug
        objectName: "suggestBar"
        x: 0; y: parent.height - 20; width: parent.width; height: 20
        color: Qt.alpha(Theme.color.bg, 0.82)
        Cap { x: 6; anchors.verticalCenter: parent.verticalCenter; text: "Suggested for night"; dim: false; color: Theme.color.accent }
      }
    }
    Row {
      x: 8; y: art.y + art.height + 6
      width: parent.width - 16
      height: 8
      spacing: 2
      Repeater {
        model: 5
        Rectangle {
          required property int index
          width: parent ? (parent.width - 8) / 5 : 0; height: 8; radius: 2
          color: !root.t.swatch ? Theme.color.surfaceContainer
            : index === 0 ? root.t.swatch.surface
            : index === 1 ? Theme.color.accent
            : index === 2 ? root.t.swatch.text
            : index === 3 ? Theme.color.waiting : Theme.color.failed
        }
      }
    }
    Row {
      x: 8; y: art.y + art.height + 16
      width: parent.width - 16
      height: 18
      spacing: 6
      Cap { objectName: "tileName"; anchors.verticalCenter: parent ? parent.verticalCenter : undefined; width: parent ? parent.width - 14 : 0; elide: Text.ElideRight; text: root.t.name || ""; dim: false }
      Rectangle {
        visible: root.t.pass !== null && root.t.pass !== undefined
        anchors.verticalCenter: parent.verticalCenter
        width: 8; height: 8; radius: 4
        color: root.t.pass ? Theme.color.accent : Theme.color.failed
      }
    }
  }
  MouseArea { anchors.fill: parent; onClicked: root.picked() }
  Rectangle {
    visible: !!root.t.showStar
    objectName: "starBtn"
    x: parent.width - 34; y: 2; width: 32; height: 32; radius: 16
    color: "transparent"
    Gly { anchors.centerIn: parent; name: "star"; active: !!root.t.isFav; box: 18; color: root.t.isFav ? Theme.color.waiting : Theme.color.fg }
    MouseArea { anchors.fill: parent; onClicked: root.favourite() }
  }
  Rectangle {
    visible: !!root.t.isSug
    x: parent.width - 34; y: 2; width: 32; height: 32; radius: 16
    color: Qt.alpha(Theme.color.bg, 0.7)
    Gly { anchors.centerIn: parent; name: "x"; box: 16; color: Theme.color.fg }
    MouseArea { anchors.fill: parent; onClicked: root.dismissed() }
  }
}
