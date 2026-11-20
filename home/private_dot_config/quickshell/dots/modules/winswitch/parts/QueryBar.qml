import QtQuick
import "../../theme"
import "../../barpop"

// The filter box that replaces the scope pill once you type. A question ends in "?" and asks
// the local model; the glyph says so, and "thinking" is a still hourglass, never a spinner.
Rectangle {
  id: root
  objectName: "filterBox"
  property string query: ""
  property string count: ""
  property bool ai: false
  property bool thinking: false
  property alias field: input
  signal edited(string q)
  signal keyed(var event)
  height: 36
  radius: 18
  color: Theme.color.bg
  border.width: 1
  border.color: Theme.color.accent
  Gly { id: lead; x: Theme.space.xl; anchors.verticalCenter: parent.verticalCenter; name: root.ai ? "sparkle" : "magnifying-glass"; box: 16; color: Theme.color.accent }
  TextInput {
    id: input
    x: lead.x + 16 + 10
    anchors.verticalCenter: parent.verticalCenter
    width: parent.width - x - cnt.width - tg.width - 3 * Theme.space.xl
    text: root.query
    color: Theme.color.fg
    font.family: Theme.font.mono
    font.pixelSize: Theme.font.size.bodyS
    clip: true
    onTextEdited: root.edited(text)
    Keys.onPressed: event => root.keyed(event)
  }
  Gly { id: tg; visible: root.thinking; anchors.right: cnt.left; anchors.rightMargin: Theme.space.m; anchors.verticalCenter: parent.verticalCenter; name: "hourglass-medium"; box: 14; color: Theme.color.accent }
  Cap { id: cnt; objectName: "qCount"; anchors.right: parent.right; anchors.rightMargin: Theme.space.xl; anchors.verticalCenter: parent.verticalCenter; text: root.count }
}
