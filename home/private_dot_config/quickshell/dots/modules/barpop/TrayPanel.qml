pragma ComponentBehavior: Bound
import QtQuick
import "../theme"
import "../common"

// Body of the tray popover. `model` is js/Tray.js build(); `drill` is null for the list or
// { name, status, items: [{label, sep, enabled, sub}] } for one app's menu. Pin and Hide
// keep no rules yet, so they render disabled.
Item {
  id: root

  property var model: ({ groups: [], total: 0, empty: true, noMatch: false })
  property var drill: null
  property string selId: ""
  property alias query: filter.text

  // fallback glyphs for apps whose tray icon is missing; listed so the icon registry keeps them
  readonly property var usedIcons: ({ chat: "chat-circle", vpn: "lock", sync: "cloud-arrow-up", backup: "shield-check", other: "squares-four" })

  signal rowPicked(string id)
  signal activate(string id)
  signal openMenu(string id)
  signal back()
  signal trigger(int index)

  implicitWidth: 328
  implicitHeight: Math.min(col.implicitHeight, 420)
  width: implicitWidth

  Column {
    id: col
    width: parent.width
    spacing: Theme.space.m

    // ---- list ----------------------------------------------------------
    Rectangle {
      objectName: "filterBox"
      visible: root.drill === null && !root.model.empty
      width: parent.width
      height: visible ? 36 : 0
      radius: Theme.radius.row
      color: Theme.color.surfaceContainer
      border.width: 1
      border.color: filter.activeFocus ? Theme.color.accent : Theme.color.outlineVariant
      Row {
        anchors.fill: parent
        anchors.leftMargin: Theme.space.xl
        spacing: Theme.space.l
        Gly { anchors.verticalCenter: parent.verticalCenter; name: "magnifying-glass"; box: 16; color: Theme.color.fgDim }
        TextInput {
          id: filter
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width - 16 - Theme.space.xl - Theme.space.l
          color: Theme.color.fg
          font.family: Theme.font.mono
          font.pixelSize: Theme.font.size.bodyS
          clip: true
          DText { visible: filter.text === ""; text: "Type to filter"; role: "bodyS"; dim: true; anchors.verticalCenter: parent.verticalCenter }
        }
      }
    }

    DText {
      objectName: "noMatch"
      visible: root.drill === null && root.model.noMatch
      width: parent.width
      text: "No match for “" + filter.text + "”"
      role: "bodyS"; dim: true
      topPadding: Theme.space.xl
      bottomPadding: Theme.space.xl
    }

    Column {
      objectName: "emptyState"
      visible: root.drill === null && root.model.empty
      width: parent.width
      spacing: Theme.space.m
      topPadding: Theme.space.xxxl
      bottomPadding: Theme.space.xxxl
      Gly { anchors.horizontalCenter: parent.horizontalCenter; name: "squares-four"; box: 40; color: Theme.color.outline }
      DText { anchors.horizontalCenter: parent.horizontalCenter; text: "Nothing in the tray"; role: "body"; font.weight: Font.DemiBold }
      Cap { anchors.horizontalCenter: parent.horizontalCenter; text: "Apps appear here when they ask for a tray icon"; dim: true }
    }

    Column {
      visible: root.drill === null
      width: parent.width
      spacing: Theme.space.s
      Repeater {
        model: root.model.groups
        Column {
          id: grp
          required property var modelData
          width: col.width
          spacing: 2
          Lbl { height: 24; text: grp.modelData.label; leftPadding: Theme.space.m }
          Repeater {
            model: grp.modelData.rows
            Rectangle {
              id: row
              objectName: "trayRow"
              required property var modelData
              readonly property bool sel: root.selId === modelData.id
              width: col.width
              height: 48
              radius: Theme.radius.row
              color: sel ? Theme.color.surfaceContainer : "transparent"
              border.width: sel ? 2 : 0
              border.color: Theme.color.accent
              MouseArea { anchors.fill: parent; onClicked: root.rowPicked(row.modelData.id) }
              Row {
                anchors.fill: parent
                anchors.leftMargin: Theme.space.l
                anchors.rightMargin: Theme.space.l
                spacing: Theme.space.xl
                Item {
                  anchors.verticalCenter: parent.verticalCenter
                  width: 24; height: 24
                  Image {
                    id: appIcon
                    anchors.fill: parent
                    source: row.modelData.icon
                    visible: row.modelData.icon !== "" && status === Image.Ready
                    sourceSize: Qt.size(48, 48)
                    fillMode: Image.PreserveAspectFit
                  }
                  Gly { anchors.centerIn: parent; visible: !appIcon.visible; name: row.modelData.glyph; box: 22; color: Theme.color.fg }
                }
                Column {
                  anchors.verticalCenter: parent.verticalCenter
                  width: parent.width - 24 - (row.sel ? actionRow.width + Theme.space.xl : 0) - Theme.space.xl
                  DText { objectName: "appName"; width: parent.width; text: row.modelData.name; role: "bodyS"; font.weight: Font.DemiBold; elide: Text.ElideRight }
                  Row {
                    spacing: Theme.space.s
                    StatusMark { visible: row.modelData.tone === "waiting"; anchors.verticalCenter: parent.verticalCenter; level: "waiting"; size: 10 }
                    Cap { text: row.modelData.status; dim: true }
                  }
                }
                Row {
                  id: actionRow
                  visible: row.sel
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Theme.space.s
                  Btn { objectName: "actOpen"; label: "Open"; kind: "primary"; pad: Theme.space.l; onClicked: root.activate(row.modelData.id) }
                  Btn { objectName: "actMenu"; label: "Menu"; pad: Theme.space.l; stub: !row.modelData.hasMenu; tip: "this app has no menu"; onClicked: root.openMenu(row.modelData.id) }
                  Btn { objectName: "actPin"; label: ""; pad: Theme.space.m; stub: true; implicitWidth: 32
                    Gly { anchors.centerIn: parent; name: "push-pin"; box: 16; color: Theme.color.fg } }
                  Btn { objectName: "actHide"; label: ""; pad: Theme.space.m; stub: true; implicitWidth: 32
                    Gly { anchors.centerIn: parent; name: "eye-closed"; box: 16; color: Theme.color.fg } }
                }
              }
            }
          }
        }
      }
    }

    // ---- drill: one app's own menu --------------------------------------
    Item {
      objectName: "drillBack"
      visible: root.drill !== null
      width: parent.width
      height: visible ? 34 : 0
      Row {
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.space.l
        leftPadding: Theme.space.m
        Gly { anchors.verticalCenter: parent.verticalCenter; name: "caret-left"; box: 16 }
        DText { anchors.verticalCenter: parent.verticalCenter; text: root.drill ? root.drill.name : ""; role: "bodyS"; font.weight: Font.DemiBold }
      }
      Cap { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; text: "Esc"; dim: true }
      MouseArea { anchors.fill: parent; onClicked: root.back() }
    }
    Rectangle { visible: root.drill !== null; width: parent.width; height: 1; color: Theme.color.outlineVariant }
    Cap { visible: root.drill !== null; text: root.drill ? root.drill.status : ""; dim: true; leftPadding: Theme.space.m }
    Column {
      visible: root.drill !== null
      width: parent.width
      spacing: 2
      Repeater {
        model: root.drill ? root.drill.items : []
        Item {
          id: mi
          objectName: "menuItem"
          required property var modelData
          required property int index
          width: col.width
          height: modelData.sep ? 9 : 34
          Rectangle { visible: mi.modelData.sep; anchors.verticalCenter: parent.verticalCenter; x: Theme.space.l; width: parent.width - 2 * Theme.space.l; height: 1; color: Theme.color.outlineVariant }
          Rectangle {
            visible: !mi.modelData.sep
            anchors.fill: parent
            radius: Theme.radius.chip
            color: hov.containsMouse && mi.modelData.enabled ? Theme.color.surfaceContainer : "transparent"
            DText {
              anchors.verticalCenter: parent.verticalCenter
              x: Theme.space.l
              width: parent.width - 2 * Theme.space.l - (mi.modelData.sub ? 20 : 0)
              text: mi.modelData.label
              role: "bodyS"
              elide: Text.ElideRight
              color: mi.modelData.enabled ? Theme.color.fg : Theme.color.fgFaint
            }
            Gly { visible: mi.modelData.sub; anchors.right: parent.right; anchors.rightMargin: Theme.space.l; anchors.verticalCenter: parent.verticalCenter; name: "caret-right"; box: 14; color: Theme.color.fgDim }
            MouseArea { id: hov; anchors.fill: parent; hoverEnabled: true; onClicked: if (mi.modelData.enabled && !mi.modelData.sub) root.trigger(mi.index) }
          }
        }
      }
    }
  }
}
