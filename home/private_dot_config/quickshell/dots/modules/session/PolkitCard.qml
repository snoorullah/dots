pragma ComponentBehavior: Bound
import QtQuick
import "../theme"
import "../common"

// The password card: what is asking, a field, Allow and Deny. `view` comes from
// Session.polkitView. When it carries an agent hint, Deny holds the focus and the hint says
// so. The password lives only in the field: it is cleared on submit and never logged.
Item {
  id: root

  property var view: ({ title: "", action: "", prompt: "Password", echo: false, error: "", info: "", agent: "", denyFirst: false, canAllow: true })
  property bool busy: false
  signal submitted(string value)
  signal cancelled()

  implicitHeight: col.implicitHeight

  function focusDefault() { if (root.view.denyFirst) deny.forceActiveFocus(); else field.forceActiveFocus() }
  function send() { if (!root.view.canAllow || root.busy) return; var v = field.text; field.text = ""; root.submitted(v) }
  onViewChanged: focusDefault()
  Component.onCompleted: focusDefault()
  Keys.onEscapePressed: root.cancelled()

  Column {
    id: col
    width: parent.width
    spacing: Theme.space.xl - 2
    opacity: root.busy ? 0.6 : 1

    DText { role: "caption"; text: "Password needed" }

    Column {
      width: parent.width
      DText { width: parent.width; role: "bodyS"; font.weight: 700; wrapMode: Text.WordWrap; text: root.view.title }
      Row {
        visible: root.view.action !== ""
        spacing: 4
        DText { role: "caption"; font.capitalization: Font.MixedCase; font.letterSpacing: 0; font.weight: Theme.font.weight.body; dim: true; text: "Action" }
        DText { role: "caption"; font.capitalization: Font.MixedCase; font.letterSpacing: 0; font.weight: Theme.font.weight.body; mono: true; text: root.view.action }
      }
    }

    Rectangle {
      id: box
      objectName: "pwField"
      width: parent.width
      height: 36
      radius: Theme.radius.row
      color: Qt.alpha(Theme.color.fg, Theme.alpha.hover)
      border.width: 1
      border.color: field.activeFocus ? Theme.color.accent : Qt.alpha(Theme.color.fg, 0.32)
      TextInput {
        id: field
        anchors { fill: parent; leftMargin: Theme.space.xl; rightMargin: Theme.space.xl }
        verticalAlignment: TextInput.AlignVCenter
        echoMode: root.view.echo ? TextInput.Normal : TextInput.Password
        passwordCharacter: "•"
        font.family: Theme.font.mono
        font.pixelSize: Theme.font.size.body
        font.letterSpacing: root.view.echo ? 0 : 2
        color: Theme.color.fg
        selectionColor: Theme.color.accent
        selectedTextColor: Theme.color.accentFg
        clip: true
        enabled: !root.busy
        onAccepted: root.send()
        DText { visible: field.text === "" && !field.activeFocus; anchors.verticalCenter: parent.verticalCenter; dim: true; text: root.view.prompt }
      }
    }

    Row {
      visible: root.view.error !== ""
      objectName: "pwError"
      spacing: Theme.space.m
      StatusMark { level: "failed"; size: Theme.font.size.title; anchors.verticalCenter: parent.verticalCenter }
      DText { role: "bodyS"; color: Theme.color.failed; text: root.view.error; anchors.verticalCenter: parent.verticalCenter }
    }
    DText { visible: root.view.info !== ""; width: parent.width; role: "bodyS"; dim: true; wrapMode: Text.WordWrap; text: root.view.info }

    Row {
      spacing: 6
      Rectangle {
        id: allow
        objectName: "pwAllow"
        width: allowLabel.implicitWidth + 2 * Theme.space.xl - 2
        height: 28
        radius: Theme.radius.chip + 2
        color: Theme.color.accent
        opacity: root.view.canAllow && !root.busy ? 1 : 0.45
        DText { id: allowLabel; anchors.centerIn: parent; role: "bodyS"; font.weight: 600; color: Theme.color.accentFg; text: "Allow" }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.send() }
      }
      Rectangle {
        id: deny
        objectName: "pwDeny"
        width: denyLabel.implicitWidth + 2 * Theme.space.xl - 2
        height: 28
        radius: Theme.radius.chip + 2
        color: Theme.color.surfaceContainer
        border.width: 1
        border.color: deny.activeFocus ? Theme.color.accent : Theme.color.outline
        activeFocusOnTab: true
        Keys.onReturnPressed: root.cancelled()
        Keys.onEnterPressed: root.cancelled()
        Keys.onSpacePressed: root.cancelled()
        DText { id: denyLabel; anchors.centerIn: parent; role: "bodyS"; text: "Deny" }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.cancelled() }
      }
    }

    Row {
      objectName: "pwAgent"
      visible: root.view.agent !== ""
      width: parent.width
      spacing: Theme.space.m
      StatusMark { level: "waiting"; size: Theme.font.size.title; anchors.verticalCenter: parent.verticalCenter }
      DText { width: parent.width - Theme.font.size.title - Theme.space.m; role: "bodyS"; color: Theme.color.waiting; wrapMode: Text.WordWrap
              text: root.view.agent + ". Deny is the default."; anchors.verticalCenter: parent.verticalCenter }
    }
  }
}
