pragma ComponentBehavior: Bound
import QtQuick
import "../../theme"
import "../../common"
import "../../barpop"

// Variant B: the profiles as a 4 x 2 grid of cards, each listing its workspaces as app chips.
Item {
  id: root
  property var m: ({})
  signal pickedProfile(string name)
  signal pickedWin(string addr)
  signal move(string name)
  signal launcher(string query)
  signal backSet(string profile)

  readonly property int gap: 12
  readonly property real cardW: (width - 32 - 3 * gap) / 4

  Grid {
    x: 16; y: 14
    columns: 4
    spacing: root.gap
    Repeater {
      model: root.m.order || []
      Rectangle {
        id: c
        required property var modelData
        objectName: "card"
        width: root.cardW
        height: 214
        radius: Theme.radius.card
        clip: true
        opacity: c.modelData.dim ? 0.4 : 1
        color: c.modelData.on ? Qt.alpha(Theme.color.accent, Theme.alpha.hover) : Theme.color.bg
        border.width: 1
        border.color: c.modelData.on ? Theme.color.accent : Theme.color.outlineVariant

        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.pickedProfile(c.modelData.name) }

        Row {
          id: ch
          objectName: "cardHead"
          x: 10; y: 10
          width: parent.width - 20
          height: 36
          spacing: Theme.space.m
          Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 30; height: 30; radius: 9
            color: c.modelData.on ? Qt.alpha(Theme.color.accent, Theme.alpha.on) : Qt.alpha(Theme.color.fg, Theme.alpha.rest + 0.02)
            Gly { anchors.centerIn: parent; name: c.modelData.icon; box: 18; color: c.modelData.on ? Theme.color.accent : Theme.color.fgDim }
          }
          DText { objectName: "cardName"; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 30 - kc.implicitWidth - (nb.visible ? nb.width + Theme.space.m : 0) - 2 * Theme.space.m; text: c.modelData.name; role: "headline"; elide: Text.ElideRight }
          Badge { id: nb; anchors.verticalCenter: parent.verticalCenter; count: c.modelData.needs }
          Cap { id: kc; anchors.verticalCenter: parent.verticalCenter; text: c.modelData.key }
        }

        Column {
          x: 10; y: 50
          width: parent.width - 20
          spacing: Theme.space.s

          Rectangle {
            objectName: "emptyCard"
            visible: c.modelData.empty
            width: parent.width
            height: visible ? 88 : 0
            radius: 10
            color: "transparent"
            border.width: 1
            border.color: Theme.color.outlineVariant
            Column {
              anchors.centerIn: parent
              spacing: Theme.space.l
              Cap { anchors.horizontalCenter: parent.horizontalCenter; text: "Nothing open"; dim: false }
              Btn { anchors.horizontalCenter: parent.horizontalCenter; label: "Go to " + c.modelData.primary; kind: "primary"; pad: Theme.space.xl; onClicked: root.pickedProfile(c.modelData.name) }
            }
          }

          Repeater {
            model: c.modelData.empty ? [] : c.modelData.ws
            Column {
              id: wr
              required property var modelData
              width: c.width - 20
              Cap { width: wr.width; text: wr.modelData.label; elide: Text.ElideRight; dim: wr.modelData.active ? false : true }
              Row {
                spacing: 3
                Repeater {
                  model: wr.modelData.wins.slice(0, 4)
                  Item {
                    id: k
                    required property var modelData
                    objectName: "gridChip"
                    width: 32; height: 32
                    opacity: root.m.query && !k.modelData.hit ? 0.35 : 1
                    Chip { anchors.fill: parent; box: 32; icon: k.modelData.icon; tone: Theme.color.fgDim; lit: k.modelData.sel || (!!root.m.query && k.modelData.hit) }
                    Dot { x: parent.width - width; y: 0; kind: k.modelData.state; scale: 0.8 }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.pickedWin(k.modelData.addr) }
                  }
                }
                Cap { visible: wr.modelData.wins.length > 4; anchors.verticalCenter: parent.verticalCenter; text: "+" + (wr.modelData.wins.length - 4) }
              }
            }
          }
        }

        Item {
          objectName: "cardRet"
          visible: !!root.m.setsKnown && !footBtn.visible
          x: 10
          y: parent.height - 38
          width: parent.width - 20
          height: 28
          Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.space.m
            Gly { anchors.verticalCenter: parent.verticalCenter; name: "arrow-counter-clockwise"; box: 14; color: c.modelData.ret.has ? Theme.color.accent : Theme.color.fgFaint }
            Cap { anchors.verticalCenter: parent.verticalCenter; text: c.modelData.ret.has ? c.modelData.ret.text : "No saved set"; color: c.modelData.ret.has ? Theme.color.accent : Theme.color.fgDim; dim: false }
          }
          MouseArea { anchors.fill: parent; enabled: c.modelData.ret.has; cursorShape: Qt.PointingHandCursor; onClicked: root.backSet(c.modelData.name) }
        }

        Row {
          objectName: "cardFoot"
          visible: footBtn.visible
          x: 10
          y: parent.height - 42
          Btn {
            id: footBtn
            objectName: "moveHere"
            visible: !!root.m.sel && !c.modelData.dim && !(root.m.targets && root.m.targets[c.modelData.key - 1] && root.m.targets[c.modelData.key - 1].cur)
            label: "Move here  Shift+" + c.modelData.key
            kind: "ghost"
            pad: Theme.space.l
            onClicked: root.move(c.modelData.name)
          }
        }
      }
    }

    Rectangle {
      objectName: "launcherCard"
      visible: !!root.m.launcher
      width: root.cardW
      height: 214
      radius: Theme.radius.card
      color: lma.containsMouse ? Qt.alpha(Theme.color.fg, Theme.alpha.rest) : "transparent"
      border.width: 1
      border.color: Theme.color.outlineVariant
      Column {
        anchors.fill: parent
        anchors.margins: 14
        spacing: Theme.space.m
        Item { width: 1; height: 54 }
        Gly { name: "magnifying-glass"; box: 20; color: Theme.color.accent }
        DText { text: "Open in launcher"; role: "bodyS" }
        Cap { width: parent.width; text: "Enter on no match, or Super+Space."; wrapMode: Text.WordWrap }
      }
      MouseArea { id: lma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.launcher(root.m.launcher ? root.m.launcher.query : "") }
    }

    Rectangle {
      objectName: "hintCard"
      visible: (root.m.order || []).length === 7
      width: root.cardW
      height: 214
      radius: Theme.radius.card
      color: "transparent"
      border.width: 1
      border.color: Theme.color.outlineVariant
      Column {
        anchors.fill: parent
        anchors.margins: 14
        spacing: Theme.space.m
        Item { width: 1; height: 54 }
        Gly { name: "magnifying-glass"; box: 20; color: Theme.color.fgDim }
        DText { text: "Filter"; role: "bodyS" }
        Cap { width: parent.width; text: "Press / to filter windows across every profile."; wrapMode: Text.WordWrap }
      }
    }
  }

  Item {
    objectName: "noMatch"
    visible: !!root.m.noResults
    anchors.centerIn: parent
    width: 300; height: 60
    Column {
      anchors.centerIn: parent
      DText { anchors.horizontalCenter: parent.horizontalCenter; text: "No window matches."; role: "body" }
      Cap { anchors.horizontalCenter: parent.horizontalCenter; text: "Enter opens it in the launcher." }
    }
  }
}
