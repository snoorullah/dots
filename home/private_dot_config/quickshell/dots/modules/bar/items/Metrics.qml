import QtQuick
import "../../theme"
import "../../common"
import ".."

// Today's numbers, two or three, each a small icon and a figure. Only the ones with a real
// value are listed (js/BarModel.js). XP is the one accent figure. Click opens the system area.
Chip {
  id: root

  property var metrics: []         // [{ key, icon, text, title, accent }]

  objectName: "metrics"
  padX: 0
  hoverable: false
  visible: metrics.length > 0
  Row {
    height: parent.height
    spacing: Theme.space.l + 2

    Repeater {
      model: root.metrics

      Row {
        id: m
        required property var modelData
        objectName: "metric"
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.space.s

        Glyph {
          anchors.verticalCenter: parent.verticalCenter
          visible: m.modelData.icon !== ""
          name: m.modelData.icon
          box: 14
          color: Theme.color.fgDim
        }
        DText {
          anchors.verticalCenter: parent.verticalCenter
          role: "bodyS"
          mono: true
          text: m.modelData.text
          color: m.modelData.accent ? Theme.color.accent : Theme.color.fg
        }
        DText {
          anchors.verticalCenter: parent.verticalCenter
          visible: m.modelData.key === "xp"
          role: "bodyS"
          dim: true
          text: "XP"
        }
      }
    }
  }
}
