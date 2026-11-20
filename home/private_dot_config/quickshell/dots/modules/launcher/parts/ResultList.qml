pragma ComponentBehavior: Bound
import QtQuick
import "../../theme"
import "../../common"
import "../../barpop"

// Left column: the rows of the current mode. One selected row; optional group headers, indent and chips
// (docs/shell/specs/launcher-modes.md section 3). An empty list shows the provider's hint.
Item {
  id: root

  required property var st

  ListView {
    id: list
    objectName: "list"
    anchors.fill: parent
    anchors.margins: 8
    clip: true
    spacing: 0
    model: root.st.rows
    currentIndex: root.st.sel
    boundsBehavior: Flickable.StopAtBounds

    delegate: Item {
      id: cell
      required property var modelData
      required property int index
      readonly property bool on: index === root.st.sel
      readonly property bool head: !!modelData.group && (index === 0 || root.st.rows[index - 1].group !== modelData.group)
      width: list.width
      height: (head ? 24 : 0) + 44

      Text {
        visible: cell.head
        text: (cell.modelData.group || "").toUpperCase()
        color: Theme.color.fgDim
        font.family: Theme.font.mono
        font.pixelSize: Theme.font.size.caption
        font.weight: Theme.font.weight.label
        font.letterSpacing: 1
        renderType: Text.NativeRendering
        x: 10
        y: 4
      }
      Rectangle {
        id: bg
        objectName: "row"
        property string titleText: cell.modelData.title
        property string subText: cell.modelData.sub || ""
        property bool selected: cell.on
        y: cell.head ? 24 : 0
        width: parent.width
        height: 44
        radius: 10
        color: cell.on ? Qt.alpha(Theme.color.fg, Theme.alpha.hover) : "transparent"

        Gly {
          id: ic
          x: 10 + (cell.modelData.indent ? 18 : 0)
          anchors.verticalCenter: parent.verticalCenter
          name: cell.modelData.icon || "squares-four"
          box: 16
          color: Theme.color.fgDim
        }
        Column {
          anchors.left: ic.right
          anchors.leftMargin: 10
          anchors.right: chips.left
          anchors.rightMargin: 8
          anchors.verticalCenter: parent.verticalCenter
          DText {
            width: parent.width
            text: cell.modelData.title
            role: "bodyS"
            elide: Text.ElideRight
            maximumLineCount: 1
          }
          DText {
            width: parent.width
            text: cell.modelData.sub || ""
            role: "bodyS"
            font.pixelSize: Theme.font.size.caption
            lineHeight: 16
            dim: true
            elide: Text.ElideRight
            maximumLineCount: 1
          }
        }
        Row {
          id: chips
          anchors.right: parent.right
          anchors.rightMargin: 10
          anchors.verticalCenter: parent.verticalCenter
          spacing: 4
          Repeater {
            model: cell.modelData.chips || []
            delegate: Rectangle {
              id: chip
              required property var modelData
              height: 18
              width: ct.implicitWidth + 12
              radius: Theme.radius.chip
              color: Qt.alpha(chip.modelData.tone === "danger" ? Theme.color.failed : chip.modelData.tone === "warn" ? Theme.color.waiting
                               : chip.modelData.tone === "accent" ? Theme.color.accent : Theme.color.fgDim, Theme.alpha.wash)
              DText {
                id: ct
                anchors.centerIn: parent
                text: chip.modelData.t
                role: "bodyS"
                font.pixelSize: 11
                lineHeight: 14
                color: chip.modelData.tone === "danger" ? Theme.color.failed : chip.modelData.tone === "warn" ? Theme.color.waiting
                       : chip.modelData.tone === "accent" ? Theme.color.accent : Theme.color.fgDim
              }
            }
          }
        }
        MouseArea {
          anchors.fill: parent
          onClicked: root.st.select(cell.index)
          onDoubleClicked: { root.st.select(cell.index); root.st.activate(0); }
        }
      }
    }
    onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
  }

  DText {
    objectName: "empty"
    visible: root.st.rows.length === 0
    anchors.centerIn: parent
    width: parent.width - 48
    horizontalAlignment: Text.AlignHCenter
    wrapMode: Text.WordWrap
    text: root.st.busy ? "Searching." : (root.st.hint || "Nothing found.")
    role: "bodyS"
    dim: true
  }
}
