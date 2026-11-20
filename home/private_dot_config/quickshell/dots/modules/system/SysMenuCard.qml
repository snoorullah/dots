pragma ComponentBehavior: Bound
import QtQuick
import "../theme"
import "../common"
import "js/Menus.js" as Menus

// One drill-in menu: header (icon, name, back) and the rows of js/Menus.js. Draws the
// model only. A click emits activated(act); a slider emits moved(act, fraction).
Item {
  id: root

  property var model: null          // {id, name, icon, rows[]}
  property real maxBody: 640
  signal activated(var act)
  signal moved(var act, real fraction)
  signal closed()

  readonly property var rows: model ? model.rows : []
  implicitHeight: header.height + Theme.space.xl - 2 + Math.min(maxBody, flick.contentHeight)

  Row {
    id: header
    width: parent.width
    height: 28
    spacing: Theme.space.xl - 2
    SIcon { key: root.model ? root.model.icon : ""; boardSize: 20; anchors.verticalCenter: parent.verticalCenter }
    DText {
      width: parent.width - 20 - 28 - 2 * parent.spacing
      anchors.verticalCenter: parent.verticalCenter
      text: root.model ? root.model.name : ""
      role: "headline"
      elide: Text.ElideRight
    }
    Item {
      width: 28; height: 28
      objectName: "menuBack"
      Rectangle { anchors.fill: parent; radius: 8; color: Qt.alpha(Theme.color.fg, backArea.containsMouse ? 0.10 : 0) }
      SIcon { anchors.centerIn: parent; key: "x"; boardSize: 16; color: Theme.color.fgDim }
      MouseArea { id: backArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.closed() }
    }
  }

  Flickable {
    id: flick
    // 8 px of spare room each side so a row's wash can bleed past the text column, as on the board
    x: -8
    y: header.height + Theme.space.xl - 2
    width: parent.width + 16
    height: Math.min(root.maxBody, contentHeight)
    contentWidth: width
    contentHeight: col.height
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    interactive: contentHeight > height

    Column {
      id: col
      x: 8
      width: flick.width - 16
      spacing: Theme.space.xl - 2

      Repeater {
        model: root.rows
        Loader {
          id: ld
          required property var modelData
          width: col.width
          objectName: "row-" + modelData.k
          sourceComponent: ({ head: headC, toggle: toggleC, item: itemC, choice: choiceC, slider: sliderC,
                              actions: actionsC, note: noteC, swatches: swatchC, monitors: monitorC })[modelData.k]
        }
      }
    }
  }

  // ---- row types --------------------------------------------------------------------
  Component {
    id: headC
    DText {
      readonly property var host: parent
      topPadding: 6; role: "caption"; text: host.modelData.t; width: parent ? parent.width : 0
    }
  }

  Component {
    id: toggleC
    Item {
      id: tg
      readonly property var host: parent
      readonly property var r: host.modelData
      readonly property bool live: !Menus.disabled(r.act)
      width: parent ? parent.width : 0
      height: Math.max(36, texts.height)
      opacity: live ? 1 : 0.5
      Column {
        id: texts
        anchors { left: parent.left; right: sw.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
        DText { width: parent.width; text: tg.r.t; role: "bodyS"; elide: Text.ElideRight }
        SText { width: parent.width; text: tg.r.sub; dim: true; visible: tg.r.sub !== ""; wrapMode: Text.WordWrap }
      }
      Rectangle {
        id: sw
        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
        width: 36; height: 20; radius: 10
        color: tg.r.on ? Theme.color.accent : Qt.alpha(Theme.color.fg, 0.18)
        Rectangle {
          y: 3; x: tg.r.on ? 19 : 3
          width: 14; height: 14; radius: 7
          color: tg.r.on ? Theme.color.accentFg : Theme.color.fg
        }
      }
      MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: tg.live ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: if (tg.live) root.activated(tg.r.act)
      }
      Tip { anchors.right: parent.right; y: -height; text: tg.r.act.why || ""; shown: ma.containsMouse && !tg.live }
    }
  }

  Component {
    id: itemC
    Item {
      id: it
      readonly property var host: parent
      readonly property var r: host.modelData
      readonly property bool rowLive: !Menus.disabled(r.act)
      readonly property bool rightLive: r.rightAct ? !Menus.disabled(r.rightAct) : false
      width: parent ? parent.width : 0
      height: Math.max(38, itemTexts.height + 8)
      // the wash bleeds 8 px past the text column, as on the board (margin 0 -8px)
      Rectangle {
        x: -8
        width: parent.width + 16
        height: parent.height
        radius: 10
        color: it.r.cur ? Qt.alpha(Theme.color.accent, 0.10) : (rowArea.containsMouse && it.rowLive ? Qt.alpha(Theme.color.fg, 0.05) : "transparent")
        MouseArea {
          id: rowArea
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: it.rowLive ? Qt.PointingHandCursor : Qt.ArrowCursor
          onClicked: if (it.rowLive) root.activated(it.r.act)
        }
      }
      Rectangle {
        id: dot
        anchors.verticalCenter: parent.verticalCenter
        width: 6; height: 6; radius: 3
        color: it.r.cur ? Theme.color.accent : Qt.alpha(Theme.color.fg, 0.25)
      }
      Column {
        id: itemTexts
        anchors { left: dot.right; leftMargin: 10; right: tail.left; rightMargin: 10; verticalCenter: parent.verticalCenter }
        DText { width: parent.width; text: it.r.t; role: "bodyS"; elide: Text.ElideRight }
        SText { width: parent.width; text: it.r.sub; dim: true; elide: Text.ElideRight; visible: it.r.sub !== "" }
      }
      Row {
        id: tail
        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
        spacing: 10
        SIcon { visible: it.r.lock; key: "secure"; boardSize: 13; color: Theme.color.fgDim; anchors.verticalCenter: parent.verticalCenter }
        SysButton {
          visible: it.r.right !== ""
          text: it.r.right
          live: it.rightLive
          why: it.r.rightAct && it.r.rightAct.why ? it.r.rightAct.why : ""
          implicitHeight: 26
          onClicked: root.activated(it.r.rightAct)
        }
      }
    }
  }

  Component {
    id: choiceC
    Column {
      id: ch
      readonly property var host: parent
      readonly property var r: host.modelData
      width: parent ? parent.width : 0
      spacing: 6
      SText { text: ch.r.t; dim: true }
      Flow {
        width: parent.width
        spacing: 6
        Repeater {
          model: ch.r.opts
          Item {
            id: chip
            required property var modelData
            readonly property bool live: !Menus.disabled(modelData.act)
            width: chipLabel.implicitWidth + 20
            height: 28
            opacity: live || modelData.on ? 1 : 0.45
            Rectangle {
              anchors.fill: parent
              radius: 14
              color: chip.modelData.on ? Theme.color.accent : "transparent"
              border.width: 1
              border.color: chip.modelData.on ? Theme.color.accent : Theme.color.outlineVariant
            }
            SText { id: chipLabel; anchors.centerIn: parent; text: chip.modelData.t; color: chip.modelData.on ? Theme.color.accentFg : Theme.color.fg }
            MouseArea {
              id: cma
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: chip.live ? Qt.PointingHandCursor : Qt.ArrowCursor
              onClicked: if (chip.live) root.activated(chip.modelData.act)
            }
            Tip { y: -height - 2; text: chip.modelData.act.why || ""; shown: cma.containsMouse && !chip.live }
          }
        }
      }
    }
  }

  Component {
    id: sliderC
    Column {
      id: sl
      readonly property var host: parent
      readonly property var r: host.modelData
      readonly property bool live: !Menus.disabled(r.act)
      width: parent ? parent.width : 0
      spacing: 6
      opacity: live ? 1 : 0.6
      Row {
        width: parent.width
        DText { width: parent.width - rightLabel.implicitWidth; text: sl.r.t; role: "bodyS"; opacity: 0.85 }
        SText { id: rightLabel; text: sl.r.right; dim: true }
      }
      Item {
        width: parent.width
        height: 16
        Rectangle {
          anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
          height: 8; radius: 4
          color: Qt.alpha(Theme.color.fg, 0.10)
          Rectangle {
            width: parent.width * sl.r.v / 100
            height: parent.height; radius: 4
            color: Qt.alpha(Theme.color.accent, 0.55)
          }
        }
        Rectangle {
          x: (parent.width - 16) * sl.r.v / 100
          anchors.verticalCenter: parent.verticalCenter
          width: 16; height: 16; radius: 8
          color: Theme.color.fg
        }
        MouseArea {
          anchors.fill: parent
          enabled: sl.live
          onPressed: mouse => root.moved(sl.r.act, Math.max(0, Math.min(1, mouse.x / width)))
          onPositionChanged: mouse => { if (pressed) root.moved(sl.r.act, Math.max(0, Math.min(1, mouse.x / width))); }
        }
      }
    }
  }

  Component {
    id: actionsC
    Item {
      id: ac
      readonly property var host: parent
      readonly property var r: host.modelData
      width: parent ? parent.width : 0
      height: flow.height + 17
      Rectangle { y: 6; width: parent.width; height: 1; color: Qt.alpha(Theme.color.fg, 0.10) }
      Flow {
        id: flow
        y: 17
        width: parent.width
        spacing: 6
        Repeater {
          model: ac.r.btns
          SysButton {
            id: ab
            required property var modelData
            required property int index
            text: modelData.t
            quiet: index === ac.r.btns.length - 1
            live: !Menus.disabled(modelData.act)
            why: modelData.act.why || ""
            implicitHeight: 30
            onClicked: root.activated(modelData.act)
          }
        }
      }
    }
  }

  Component {
    id: noteC
    SText {
      readonly property var host: parent
      text: host.modelData.t; dim: true; wrapMode: Text.WordWrap; width: parent ? parent.width : 0
    }
  }

  Component {
    id: swatchC
    Grid {
      id: sg
      readonly property var host: parent
      readonly property var r: host.modelData
      width: parent ? parent.width : 0
      columns: 3
      spacing: 6
      Repeater {
        model: sg.r.sw
        Rectangle {
          id: swc
          required property var modelData
          required property int index
          width: (sg.width - 12) / 3
          height: 56
          radius: 10
          border.width: 2
          border.color: index === 0 ? Theme.color.accent : "transparent"
          gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: swc.modelData }
            GradientStop { position: 1; color: Theme.color.bg }
          }
        }
      }
    }
  }

  Component {
    id: monitorC
    Item {
      id: mc
      readonly property var host: parent
      readonly property var r: host.modelData
      width: parent ? parent.width : 0
      height: 90
      Row {
        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom }
        spacing: 8
        Repeater {
          model: mc.r.screens
          Item {
            id: mon
            required property var modelData
            required property int index
            anchors.bottom: parent.bottom
            width: index === 0 ? 150 : 96
            height: index === 0 ? 84 : 60
            Rectangle {
              anchors.fill: parent
              radius: 6
              color: "transparent"
              border.width: mon.index === 0 ? 2 : 1
              border.color: mon.index === 0 ? Theme.color.accent : Qt.alpha(Theme.color.fg, 0.3)
            }
            SText { anchors.centerIn: parent; text: mon.modelData.label; dim: mon.index !== 0 }
          }
        }
      }
    }
  }
}
