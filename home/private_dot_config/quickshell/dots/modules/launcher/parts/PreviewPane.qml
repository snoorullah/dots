pragma ComponentBehavior: Bound
import QtQuick
import "../../theme"
import "../../common"

// Right column: head (20 px, or the font shown at 36 px), body, optional image and snippet fields, and
// the action buttons at the bottom. Everything comes from the selected row's `preview` and `actions`.
Item {
  id: root

  required property var st
  readonly property var row: root.st.cur
  readonly property var pv: row && row.preview ? row.preview : ({ head: "", body: "" })

  Flickable {
    anchors { left: parent.left; right: parent.right; top: parent.top; bottom: acts.top; leftMargin: 18; rightMargin: 18; topMargin: 16; bottomMargin: 10 }
    contentHeight: col.height
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    Column {
      id: col
      width: parent.width
      spacing: 10

      Rectangle {
        objectName: "banner"
        visible: !!root.st.mode && !!root.st.mode.banner
        width: parent.width
        height: visible ? bt.implicitHeight + 12 : 0
        radius: 8
        color: Qt.alpha(Theme.color.waiting, Theme.alpha.wash)
        DText { id: bt; x: 10; y: 6; width: parent.width - 20; wrapMode: Text.WordWrap; role: "bodyS"; text: root.st.mode && root.st.mode.banner ? (root.st.mode.banner.title + " " + (root.st.mode.banner.detail || "")) : "" }
      }
      Text {
        objectName: "head"
        width: parent.width
        text: root.pv.head || ""
        wrapMode: Text.WrapAnywhere
        color: Theme.color.fg
        font.family: root.pv.font ? root.pv.font : Theme.font.mono
        font.pixelSize: root.pv.font ? 36 : Theme.font.size.headline
        font.weight: Theme.font.weight.display
        lineHeight: root.pv.font ? 1.2 : 1.2
        renderType: Text.NativeRendering
      }
      Image {
        objectName: "image"
        visible: !!root.pv.image && status !== Image.Error
        source: root.pv.image ? "file://" + root.pv.image : ""
        width: Math.min(parent.width, implicitWidth > 0 ? implicitWidth : parent.width)
        height: visible ? Math.min(240, width * (implicitHeight > 0 ? implicitHeight / implicitWidth : 0.6)) : 0
        fillMode: Image.PreserveAspectFit
        horizontalAlignment: Image.AlignLeft
        smooth: true
      }
      Repeater {
        model: root.pv.fields || []
        delegate: Row {
          id: fld
          required property var modelData
          objectName: "field-row"
          spacing: 10
          DText { width: 90; text: fld.modelData.name; role: "bodyS"; dim: true }
          DText {
            width: col.width - 100
            text: fld.modelData.value || (fld.modelData.state === "empty" ? "(empty)" : "")
            role: "bodyS"
            color: fld.modelData.state === "ghost" ? Theme.color.fgFaint : fld.modelData.state === "empty" ? Theme.color.waiting : Theme.color.fg
            wrapMode: Text.WordWrap
          }
        }
      }
      Text {
        objectName: "body"
        width: parent.width
        text: root.pv.body || ""
        wrapMode: Text.Wrap
        color: Qt.alpha(Theme.color.fg, 0.88)
        font.family: Theme.font.mono
        font.pixelSize: Theme.font.size.bodyS
        lineHeight: 21
        lineHeightMode: Text.FixedHeight
        textFormat: Text.PlainText
        renderType: Text.NativeRendering
      }
    }
  }

  Flow {
    id: acts
    objectName: "actions"
    anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: 18; rightMargin: 18; bottomMargin: 16 }
    spacing: 6
    Repeater {
      model: root.row && root.row.actions ? root.row.actions : []
      delegate: ActionButton {
        required property var modelData
        required property int index
        objectName: "action"
        label: modelData.label
        primary: index === 0
        picked: index === root.st.sec
        disabled: !!modelData.disabled
        onClicked: root.st.activate(index)
      }
    }
  }
}
