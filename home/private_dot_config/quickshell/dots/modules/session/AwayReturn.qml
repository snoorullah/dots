pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Io
import "../theme"
import "../common"
import "js/Session.js" as S

// "While you were away": what was declared or detected, plus agent and mail rows when
// whoever hosts this has them. Read-only. `declared` is the parsed away-intent.json (set
// intentPath and it is read and kept current), `idleSince` and `now` are unix seconds.
Item {
  id: root

  property string intentPath: ""
  property var declared: null
  property real now: Date.now() / 1000
  property real idleSince: 0
  property var agent: null            // {text, note}
  property var mail: null             // {text, note}
  readonly property var rows: S.returnRows(declared, now, idleSince, agent, mail)

  implicitHeight: panel.height

  FileView {
    path: root.intentPath
    watchChanges: true
    onFileChanged: reload()
    onLoaded: { try { root.declared = JSON.parse(text()) } catch (e) { root.declared = null } }
    onLoadFailed: root.declared = null
  }

  Rectangle {
    id: panel
    width: parent.width
    height: list.y + list.implicitHeight + Theme.space.xxl
    radius: Theme.radius.card + 2
    color: Theme.color.surface
    border.width: 1
    border.color: Qt.alpha(Theme.color.outline, Theme.alpha.divider)

    DText { id: cap; x: 20; y: Theme.space.xxl; role: "caption"; text: "While you were away (declared and detected)" }
    Column {
      id: list
      objectName: "returnRows"
      x: 20
      y: cap.y + cap.height + Theme.space.xl - 2
      width: parent.width - 40
      spacing: Theme.space.m
      Repeater {
        model: root.rows
        Rectangle {
          id: r
          required property var modelData
          objectName: "return-row-" + modelData.id
          readonly property color tone: modelData.tone === "waiting" ? Theme.color.waiting
            : modelData.tone === "accent" ? Theme.color.accent : Theme.color.fgDim
          width: parent.width
          height: 40
          radius: Theme.radius.row
          color: Theme.color.surfaceContainer
          border.width: 1
          border.color: modelData.tone === "waiting" ? Theme.color.waiting : Theme.color.outline
          Row {
            x: 14; width: 120; height: parent.height; spacing: Theme.space.m
            StatusMark { visible: r.modelData.tone === "waiting"; level: "waiting"; size: Theme.font.size.title; anchors.verticalCenter: parent.verticalCenter }
            DText { anchors.verticalCenter: parent.verticalCenter; font.weight: 600; color: r.tone; text: r.modelData.a }
          }
          DText { x: 14 + 120 + 14; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 148 - 140; elide: Text.ElideRight; text: r.modelData.b }
          DText { anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter } dim: true; text: r.modelData.d }
        }
      }
    }
  }
}
