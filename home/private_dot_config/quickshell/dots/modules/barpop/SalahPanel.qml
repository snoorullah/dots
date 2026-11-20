pragma ComponentBehavior: Bound
import QtQuick
import "../theme"
import "../common"

// Body of the salah popup. `model` is js/Salah.js build(); nothing else is read.
Item {
  id: root

  property var model: ({ ok: false, rows: [], hero: ({}), stale: false, sunrise: "" })
  property string dateText: ""

  implicitWidth: 328
  implicitHeight: col.implicitHeight
  width: implicitWidth

  readonly property bool soon: !!model.hero && model.hero.soon === true
  readonly property color accentC: model.stale ? Theme.color.fgDim : (soon ? Theme.color.waiting : Theme.color.accent)

  Column {
    id: col
    width: parent.width
    spacing: Theme.space.l

    Row {
      width: parent.width
      height: 46
      spacing: Theme.space.l

      Column {
        width: parent.width - gear.width - (badge.visible ? badge.width + Theme.space.l : 0) - 2 * Theme.space.l
        anchors.verticalCenter: parent.verticalCenter
        DText { objectName: "dateText"; role: "headline"; text: root.dateText; elide: Text.ElideRight; width: parent.width }
        Cap { text: "Calculated on this machine"; dim: true; elide: Text.ElideRight; width: parent.width }
      }
      Pill {
        id: badge
        objectName: "cachedBadge"
        anchors.verticalCenter: parent.verticalCenter
        visible: root.model.stale === true
        text: "CACHED"
        tone: "amber"
        bordered: true
      }
      Item {
        id: gear
        width: 32; height: 32
        anchors.verticalCenter: parent.verticalCenter
        opacity: 0.45
        Gly { anchors.centerIn: parent; name: "gear"; box: 18; color: Theme.color.fgDim }
        MouseArea { id: gearMa; anchors.fill: parent; hoverEnabled: true }
        Rectangle {
          visible: gearMa.containsMouse
          objectName: "stubTip"
          z: 50
          anchors.right: parent.right
          anchors.top: parent.bottom
          anchors.topMargin: Theme.space.s
          width: gtip.implicitWidth + 2 * Theme.space.m
          height: 24
          radius: Theme.radius.chip
          color: Theme.color.surfaceContainerHigh
          border.width: 1
          border.color: Theme.color.outlineVariant
          Cap { id: gtip; anchors.centerIn: parent; text: "read-only for now"; dim: false }
        }
      }
    }

    // nothing to say: no prayer file yet
    DText {
      objectName: "noTimes"
      visible: !root.model.ok
      width: parent.width
      wrapMode: Text.WordWrap
      text: "No prayer times yet. The daily timer writes them; nothing is guessed here."
      dim: true
      role: "bodyS"
    }

    Rectangle {
      id: hero
      objectName: "hero"
      visible: root.model.ok === true
      width: parent.width
      height: heroCol.implicitHeight + Theme.space.xl + Theme.space.l
      radius: Theme.radius.row + 2
      color: Theme.color.surfaceContainer
      border.width: 1
      border.color: Theme.color.outlineVariant

      Column {
        id: heroCol
        x: Theme.space.xl
        y: Theme.space.l
        width: parent.width - 2 * Theme.space.xl
        spacing: Theme.space.s

        Item {
          width: parent.width
          height: Theme.font.line.caption
          Lbl { text: root.model.hero.label || ""; color: root.accentC; anchors.left: parent.left }
          DText {
            anchors.right: parent.right
            text: root.model.hero.cd || ""
            role: "bodyS"
            color: root.model.stale ? Theme.color.fgDim : (root.soon ? Theme.color.waiting : Theme.color.fg)
          }
        }
        DText {
          objectName: "heroName"
          width: parent.width
          text: root.model.hero.name || ""
          role: "page"
          mono: false
          elide: Text.ElideRight
          color: root.model.stale ? Theme.color.fgDim : Theme.color.fg
        }
        Rectangle {
          width: parent.width; height: 4; radius: 2
          color: Qt.alpha(Theme.color.fg, 0.1)
          Rectangle {
            objectName: "heroBar"
            width: parent.width * (root.model.hero.pct || 0); height: 4; radius: 2
            color: root.accentC
          }
        }
      }
    }

    Column {
      id: list
      visible: root.model.ok === true
      width: parent.width
      opacity: root.model.stale ? 0.5 : 1

      Repeater {
        model: root.model.rows
        Column {
          id: rowWrap
          required property var modelData
          required property int index
          width: list.width

          Rectangle {
            objectName: "prayerRow"
            width: parent.width
            height: 32
            radius: rowWrap.modelData.focus ? Theme.radius.chip : 0
            color: rowWrap.modelData.focus ? Qt.alpha(Theme.color.accent, 0.10) : "transparent"

            Rectangle {
              visible: !rowWrap.modelData.focus
              anchors.bottom: parent.bottom
              width: parent.width; height: 1
              color: Qt.alpha(Theme.color.fg, 0.06)
            }
            Row {
              anchors.fill: parent
              anchors.leftMargin: Theme.space.l
              anchors.rightMargin: Theme.space.l
              spacing: Theme.space.l
              opacity: rowWrap.modelData.past ? 0.55 : 1
              DText {
                width: parent.width - 40 - 54 - 2 * Theme.space.l
                height: parent.height
                text: rowWrap.modelData.name
                role: "body"
                font.weight: rowWrap.modelData.focus ? Font.DemiBold : Font.Medium
              }
              DText { width: 40; height: parent.height; text: rowWrap.modelData.iq; role: "bodyS"; dim: true; horizontalAlignment: Text.AlignRight; mono: true }
              DText {
                objectName: "prayerTime"
                width: 54; height: parent.height
                text: rowWrap.modelData.time
                role: "title"
                mono: true
                horizontalAlignment: Text.AlignRight
                color: rowWrap.modelData.focus && root.soon ? Theme.color.waiting : Theme.color.fg
              }
            }
          }
          Item {
            visible: rowWrap.index === 0
            width: parent.width
            height: visible ? 16 : 0
            opacity: 0.55
            Rectangle { anchors.verticalCenter: parent.verticalCenter; x: 0; width: (parent.width - sr.implicitWidth) / 2 - Theme.space.l; height: 1; color: Qt.alpha(Theme.color.fg, 0.25) }
            Lbl { id: sr; objectName: "sunrise"; anchors.centerIn: parent; text: "SUNRISE " + root.model.sunrise }
            Rectangle { anchors.verticalCenter: parent.verticalCenter; anchors.right: parent.right; width: (parent.width - sr.implicitWidth) / 2 - Theme.space.l; height: 1; color: Qt.alpha(Theme.color.fg, 0.25) }
          }
        }
      }
    }

    Item {
      visible: root.model.ok === true
      width: parent.width
      height: 32
      Row {
        spacing: Theme.space.m
        Btn { label: "Salah mode"; stub: true }
        Btn { label: "Snooze 10 m"; stub: true }
      }
      Btn { anchors.right: parent.right; label: "Tomorrow"; stub: true }
    }
  }
}
