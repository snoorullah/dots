import QtQuick
import "../../theme"
import "../../common"
import "../../barpop"

// Board row 1 (56 px): search glyph, the mode prefix in accent, the field, the busy note and the shortcut.
Item {
  id: root

  required property var st
  property string shortcut: "Super + Space"
  property alias field: input

  signal keyed(var event)

  implicitHeight: 56

  Gly { id: glass; x: 18; anchors.verticalCenter: parent.verticalCenter; name: "magnifying-glass"; box: 20; color: Theme.color.fgDim }

  Row {
    anchors.left: glass.right
    anchors.leftMargin: 12
    anchors.right: tail.left
    anchors.rightMargin: 12
    anchors.verticalCenter: parent.verticalCenter
    spacing: 0

    Text {
      id: pre
      objectName: "prefix"
      visible: text !== ""
      text: root.st.mode ? root.st.mode.prefix : ""
      color: Theme.color.accent
      font.family: Theme.font.mono
      font.pixelSize: 18
      anchors.verticalCenter: parent.verticalCenter
      renderType: Text.NativeRendering
    }
    TextInput {
      id: input
      objectName: "field"
      width: parent.width - (pre.visible ? pre.width : 0)
      anchors.verticalCenter: parent.verticalCenter
      color: Theme.color.fg
      selectionColor: Qt.alpha(Theme.color.accent, Theme.alpha.on)
      selectedTextColor: Theme.color.fg
      font.family: Theme.font.mono
      font.pixelSize: 18
      clip: true
      focus: true
      renderType: Text.NativeRendering
      text: root.st.query
      onTextEdited: root.st.setText(text)
      Keys.onPressed: event => { event.accepted = root.st.handleKey(event); }
      // the core owns the text: a prefix typed here is moved into the chip, a clear comes back down
      Connections {
        target: root.st
        function onQueryChanged() { if (input.text !== root.st.query) input.text = root.st.query; }
      }
      Text {
        visible: input.text === "" && root.st.query === ""
        text: root.st.modeId === "all" ? "Search, or type a prefix: c: > =" : "Type to search " + root.st.mode.name
        color: Theme.color.fgFaint
        font: input.font
        anchors.verticalCenter: parent.verticalCenter
        renderType: Text.NativeRendering
      }
    }
  }

  Row {
    id: tail
    anchors.right: parent.right
    anchors.rightMargin: 18
    anchors.verticalCenter: parent.verticalCenter
    spacing: 12
    DText {
      objectName: "busy"
      visible: root.st.busy
      text: "Searching"
      role: "bodyS"
      font.pixelSize: Theme.font.size.caption
      dim: true
    }
    DText {
      text: root.shortcut
      role: "bodyS"
      font.pixelSize: Theme.font.size.caption
      dim: true
    }
  }
}
