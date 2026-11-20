pragma ComponentBehavior: Bound
import QtQuick
import "../theme"
import "../common"
import "../barpop"

// The scratchpad's card: five tabs, a note that survives restarts, and four actions. Only Note
// is built; Terminal, Snippet, Math and Ask say so. Nothing here sends anything.
// `m` comes from js/Scratch.js build().
Item {
  id: root

  property var m: ({ tabs: [], tab: "note", built: true, text: "", empty: true, actions: [], profile: "", foot: "" })
  property bool readOnly: false
  property alias editor: ed
  signal tabPicked(string id)
  signal edited(string text)
  signal acted(string id)

  implicitWidth: 480
  implicitHeight: col.implicitHeight
  width: implicitWidth
  height: implicitHeight

  Column {
    id: col
    width: parent.width
    spacing: Theme.space.xl

    Lbl { text: "Scratchpad" + (root.m.profile ? " · " + root.m.profile : "") }

    Row {
      spacing: Theme.space.s
      Repeater {
        model: root.m.tabs
        Rectangle {
          id: tab
          required property var modelData
          objectName: "scratchTab"
          height: 30
          width: tl.implicitWidth + 2 * Theme.space.xl + 14 + Theme.space.m
          radius: Theme.radius.chip + 2
          color: tab.modelData.on ? Qt.alpha(Theme.color.fg, 0.10) : (ma.containsMouse ? Qt.alpha(Theme.color.fg, Theme.alpha.rest) : "transparent")
          border.width: tab.modelData.on ? 1 : 0
          border.color: Theme.color.outlineVariant
          opacity: tab.modelData.built ? 1 : 0.7
          Row {
            anchors.centerIn: parent
            spacing: Theme.space.m
            Gly { anchors.verticalCenter: parent.verticalCenter; name: tab.modelData.icon; box: 14; color: tab.modelData.on ? Theme.color.fg : Theme.color.fgDim }
            DText { id: tl; anchors.verticalCenter: parent.verticalCenter; text: tab.modelData.label; role: "bodyS"; dim: !tab.modelData.on }
          }
          MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.tabPicked(tab.modelData.id) }
        }
      }
    }

    Rectangle {
      objectName: "noteArea"
      width: parent.width
      height: 260
      radius: Theme.radius.row
      color: Theme.color.bg
      border.width: 1
      border.color: ed.activeFocus ? Theme.color.accent : Theme.color.outlineVariant
      clip: true
      TextEdit {
        id: ed
        objectName: "noteEditor"
        visible: root.m.built
        anchors.fill: parent
        anchors.margins: Theme.space.xl
        readOnly: root.readOnly
        wrapMode: TextEdit.Wrap
        selectByMouse: true
        color: Theme.color.fg
        selectionColor: Qt.alpha(Theme.color.accent, 0.35)
        font.family: Theme.font.mono
        font.pixelSize: Theme.font.size.bodyS
        text: root.m.text
        onTextChanged: if (text !== root.m.text) root.edited(text)
        DText { visible: ed.text === ""; text: "Type a note. It stays with this profile."; role: "bodyS"; dim: true }
      }
      Column {
        objectName: "stubNote"
        visible: !root.m.built
        anchors.centerIn: parent
        spacing: Theme.space.m
        DText { anchors.horizontalCenter: parent.horizontalCenter; text: "Not built yet."; role: "body" }
        Cap { anchors.horizontalCenter: parent.horizontalCenter; text: "Read-only for now. Note works." }
      }
    }

    Flow {
      width: parent.width
      spacing: Theme.space.m
      Repeater {
        model: root.m.actions
        Btn {
          required property var modelData
          objectName: "scratchAction"
          label: modelData.label
          kind: modelData.on ? "primary" : "ghost"
          stub: modelData.stub
          tip: modelData.tip
          pad: Theme.space.l
          onClicked: root.acted(modelData.id)
        }
      }
    }

    Cap { objectName: "scratchFoot"; width: parent.width; wrapMode: Text.WordWrap; text: root.m.foot }
  }
}
