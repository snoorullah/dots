pragma ComponentBehavior: Bound
import QtQuick
import "../../theme"
import "../../common"
import "../../barpop"

// The focused profile as a tree: header, then each workspace with its windows. Used by the
// popover and, beside the rail, by the full switcher.
Item {
  id: root
  property var m: ({})
  property int maxBody: 560
  property bool showSalah: false
  signal wsFocus(int id)
  signal picked(string addr)
  signal move(string addr, string name)
  signal retry(string addr)
  signal startSet(string profile)
  signal newWs(int id)
  signal backSet()

  readonly property var fp: m.fp || ({ ws: [], total: 0, needs: 0, name: "", icon: "stack", empty: true })
  readonly property bool showSet: !!m.setsKnown
  implicitHeight: head.height + (showSet ? setRow.height + Theme.space.m : 0) + Math.min(body.contentHeight + 10, maxBody)

  Item {
    id: head
    objectName: "treeHead"
    x: Theme.space.xxl
    width: parent.width - 2 * Theme.space.xxl
    height: 60
    Row {
      id: leftRow
      objectName: "headLeft"
      anchors.verticalCenter: parent.verticalCenter
      spacing: Theme.space.xl - 2
      Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: 36; height: 36; radius: Theme.radius.row
        color: Qt.alpha(Theme.color.accent, Theme.alpha.on)
        Gly { anchors.centerIn: parent; name: root.fp.icon; box: 22; color: Theme.color.accent }
      }
      DText {
        objectName: "profName"
        anchors.verticalCenter: parent.verticalCenter
        text: root.fp.name
        role: "headline"
        elide: Text.ElideRight
        // never reach under the right-hand pills
        width: Math.max(0, Math.min(implicitWidth, head.width - rightRow.width - Theme.space.xl
                 - 36 - leftRow.spacing * 2 - (needsPill.visible ? needsPill.width : 0)))
      }
      Pill { id: needsPill; objectName: "needsPill"; visible: root.fp.needs > 0; anchors.verticalCenter: parent.verticalCenter; text: root.fp.needs + " need you"; tone: "amber"; bordered: true }
    }
    Row {
      id: rightRow
      objectName: "headRight"
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      spacing: Theme.space.l
      Pill { id: maskPill; objectName: "maskPill"; visible: !!root.m.mask; anchors.verticalCenter: parent.verticalCenter; text: "Masked"; tone: "accent"; bordered: true }
      Pill { objectName: "salahPill"; visible: root.showSalah; anchors.verticalCenter: parent.verticalCenter; text: "Salah"; tone: "accent"; bordered: true }
      Cap { objectName: "profTotal"; visible: !maskPill.visible && !root.showSalah; anchors.verticalCenter: parent.verticalCenter; text: root.fp.total + (root.fp.total === 1 ? " window" : " windows") }
    }
  }

  SetRow {
    id: setRow
    visible: root.showSet
    x: Theme.space.xl
    y: head.height
    width: parent.width - 2 * Theme.space.xl
    height: visible ? 44 : 0
    ret: root.fp.ret || ({ has: false })
    onPressed: root.backSet()
  }

  Flickable {
    id: body
    anchors.top: head.bottom
    anchors.topMargin: root.showSet ? setRow.height + Theme.space.m : 0
    anchors.bottom: parent.bottom
    width: parent.width
    contentHeight: col.implicitHeight + 10
    contentWidth: width
    clip: true
    interactive: contentHeight > height
    boundsBehavior: Flickable.StopAtBounds

    Column {
      id: col
      x: Theme.space.xl
      width: parent.width - 2 * Theme.space.xl
      spacing: Theme.space.xl

      // empty profile
      Rectangle {
        objectName: "emptyState"
        visible: root.fp.empty
        width: parent.width
        height: visible ? emp.implicitHeight + 44 : 0
        radius: 12
        color: "transparent"
        border.width: 1
        border.color: Theme.color.outlineVariant
        Column {
          id: emp
          anchors.centerIn: parent
          spacing: Theme.space.xl
          DText { anchors.horizontalCenter: parent.horizontalCenter; text: "Nothing open"; role: "body" }
          Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Theme.space.l
            Btn { objectName: "startSet"; label: "Start startup set"; kind: "primary"; onClicked: root.startSet(root.fp.name) }
            Btn { objectName: "newWs"; label: "New workspace"; kind: "ghost"; stub: root.m.newWs <= 0; tip: "this profile has no free workspace"; onClicked: root.newWs(root.m.newWs) }
          }
          Btn {
            objectName: "openWs"
            anchors.horizontalCenter: parent.horizontalCenter
            label: "Go to workspace " + root.fp.primary
            kind: "link"
            onClicked: root.wsFocus(root.fp.primary)
          }
        }
      }

      Repeater {
        model: root.fp.ws
        Column {
          id: g
          required property var modelData
          objectName: "wsGroup"
          visible: g.modelData.wins.length > 0 || !root.fp.empty
          width: col.width
          spacing: 0
          Item {
            objectName: "wsHead"
            width: parent.width
            height: 26
            Row {
              x: Theme.space.m
              anchors.verticalCenter: parent.verticalCenter
              spacing: Theme.space.m
              DText { text: g.modelData.label; role: "bodyS"; font.weight: g.modelData.active ? Font.DemiBold : Font.Normal; dim: !g.modelData.active }
              Cap { objectName: "activeTag"; visible: g.modelData.active; text: "ACTIVE"; color: Theme.color.accent }
            }
            Cap { x: parent.width - width - Theme.space.m; anchors.verticalCenter: parent.verticalCenter; text: g.modelData.n }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.wsFocus(g.modelData.id) }
          }
          Repeater {
            model: g.modelData.wins
            WinRow {
              required property var modelData
              width: g.width
              w: modelData
              targets: root.m.targets || []
              hints: root.m.rowHints || []
              dim: false
              onPicked: addr => root.picked(addr)
              onMove: name => root.move(modelData.addr, name)
              onRetry: addr => root.retry(addr)
              onSuggested: name => root.move(modelData.addr, name)
            }
          }
        }
      }
    }
  }
}
