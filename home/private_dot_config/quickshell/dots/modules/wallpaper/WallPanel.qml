pragma ComponentBehavior: Bound
import QtQuick
import "../theme"
import "../common"
import "../barpop"
import "parts"

// The picker's card (960 x 640), driven entirely by `m` from js/Wall.js build(). Nothing here
// talks to the compositor or a process: the window (WallpaperPicker) and the test scene feed it.
Item {
  id: root

  property var m: ({ mode: "grid", tiles: [], notice: null, folder: { name: "", count: "0", skipped: 0 }, search: { query: "", show: false, text: "" },
                     contrast: { show: false }, swatches: [], modes: [], target: { label: "", list: [] }, shuffle: { label: "", mid: "hint" }, legend: [] })
  property bool readOnly: false
  property alias search: input

  signal picked(string path)
  signal favourite(string path)
  signal applied(bool stay)
  signal closed()
  signal edited(string q)
  signal keyed(var event)
  signal folderAsked()
  signal untuneToggled()
  signal paletteChosen(int index)
  signal targetCycled()
  signal shuffleToggled()
  signal lockToggled()
  signal undone()
  signal suggestionDismissed()

  function url(p) { return p ? "file://" + p : "" }

  readonly property int noticeH: m.notice ? 40 : 0
  width: 960
  height: 640

  Surface { id: card; objectName: "card"; anchors.fill: parent; corner: Theme.radius.panel; fill: Theme.alpha.panel }

  // ---- top row ---------------------------------------------------------------------------
  Item {
    id: top
    x: 16; y: 16
    width: parent.width - 32
    height: 44

    Rectangle {
      id: sbox
      objectName: "searchBox"
      width: parent.width - folderBtn.width - closeBtn.width - 20
      height: 44
      radius: Theme.radius.row
      color: Theme.color.bg
      border.width: 1
      border.color: input.activeFocus ? Theme.color.accent : Theme.color.outlineVariant
      Gly { x: 14; anchors.verticalCenter: parent.verticalCenter; name: "magnifying-glass"; box: 18; color: Theme.color.fgDim }
      TextInput {
        id: input
        x: 42
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - 42 - (root.m.search.show ? 110 : 14)
        readOnly: root.readOnly
        text: root.m.search.query
        color: Theme.color.fg
        font.family: Theme.font.mono
        font.pixelSize: Theme.font.size.bodyS
        clip: true
        onTextEdited: root.edited(text)
        Keys.onPressed: event => root.keyed(event)
        DText { visible: input.text === ""; anchors.verticalCenter: parent.verticalCenter; text: root.m.search.placeholder || ""; role: "bodyS"; dim: true }
      }
      Cap { objectName: "searchCount"; visible: root.m.search.show; anchors.right: parent.right; anchors.rightMargin: 14; anchors.verticalCenter: parent.verticalCenter; text: root.m.search.text }
    }
    Rectangle {
      id: folderBtn
      objectName: "folderBtn"
      x: sbox.width + 10
      width: frow.implicitWidth + 28; height: 44
      radius: Theme.radius.row
      color: Theme.color.bg
      border.width: 1; border.color: Theme.color.outlineVariant
      Row {
        id: frow
        anchors.centerIn: parent
        spacing: Theme.space.m
        Gly { anchors.verticalCenter: parent.verticalCenter; name: "stack"; box: 16; color: Theme.color.fg }
        DText { anchors.verticalCenter: parent.verticalCenter; text: root.m.folder.name; role: "bodyS" }
        Cap { anchors.verticalCenter: parent.verticalCenter; text: root.m.folder.count }
        Cap { visible: root.m.folder.skipped > 0; anchors.verticalCenter: parent.verticalCenter; text: root.m.folder.skippedText; dim: false; color: Theme.color.waiting }
      }
      MouseArea { anchors.fill: parent; onClicked: root.folderAsked() }
    }
    Rectangle {
      id: closeBtn
      x: parent.width - width
      width: 44; height: 44; radius: Theme.radius.row
      color: "transparent"
      border.width: 1; border.color: Theme.color.outlineVariant
      Gly { anchors.centerIn: parent; name: "x"; box: 18; color: Theme.color.fgDim }
      MouseArea { anchors.fill: parent; onClicked: root.closed() }
    }
  }

  // ---- notice ----------------------------------------------------------------------------
  Rectangle {
    id: notice
    objectName: "notice"
    visible: !!root.m.notice
    x: 16; y: 60
    width: parent.width - 32; height: 32
    radius: Theme.radius.chip + 2
    readonly property color tone: root.m.notice && root.m.notice.tone === "warn" ? Theme.color.waiting : (root.m.notice && root.m.notice.tone === "accent" ? Theme.color.accent : Theme.color.fgDim)
    property string text: root.m.notice ? root.m.notice.text : ""
    color: Qt.alpha(tone, 0.1)
    border.width: 1; border.color: Qt.alpha(tone, 0.4)
    Row {
      anchors.fill: parent
      anchors.leftMargin: Theme.space.xl
      spacing: Theme.space.l
      Gly { anchors.verticalCenter: parent.verticalCenter; name: root.m.notice ? root.m.notice.icon : "moon"; box: 16; color: notice.tone }
      Cap { anchors.verticalCenter: parent.verticalCenter; text: notice.text; dim: false; color: notice.tone === Theme.color.fgDim ? Theme.color.fg : notice.tone }
    }
  }

  // ---- body ------------------------------------------------------------------------------
  Item {
    id: bodyArea
    y: 76 + root.noticeH
    width: parent.width
    height: parent.height - y - 72

    // left: the grid
    Item {
      id: leftPane
      x: 0; width: 596; height: parent.height
      GridView {
        id: grid
        objectName: "grid"
        visible: root.m.mode !== "empty"
        x: 16; width: 580
        height: parent.height
        cellWidth: 145; cellHeight: 138
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: root.m.mode === "loading" ? 16 : root.m.tiles
        currentIndex: root.m.sel
        onCurrentIndexChanged: positionViewAtIndex(currentIndex, GridView.Contain)
        delegate: Item {
          id: cell
          required property var modelData
          required property int index
          width: 145; height: 138
          WallTile {
            objectName: "tile"
            t: root.m.mode === "loading" ? ({ loading: true, ring: "none", name: "", isCur: false }) : cell.modelData
            src: root.m.mode === "loading" ? "" : root.url(cell.modelData.path)
            onPicked: if (root.m.mode !== "loading" && !cell.modelData.isBroken) root.picked(cell.modelData.path)
            onFavourite: root.favourite(cell.modelData.path)
            onDismissed: root.suggestionDismissed()
          }
        }
      }
      // a slim scroll position mark for large folders
      Rectangle {
        objectName: "scrollMark"
        visible: grid.visible && grid.contentHeight > grid.height
        x: leftPane.width - 7; y: 8 + (grid.height - 60) * (grid.contentY / Math.max(1, grid.contentHeight - grid.height))
        width: 4; height: 52; radius: 2; color: Theme.color.unknown
      }
      Column {
        objectName: "emptyState"
        visible: root.m.mode === "empty"
        anchors.centerIn: parent
        spacing: 10
        Gly { anchors.horizontalCenter: parent.horizontalCenter; name: "image"; box: 40; color: Theme.color.fgDim }
        DText { anchors.horizontalCenter: parent.horizontalCenter; text: "No wallpaper folder yet."; role: "body" }
        Cap { anchors.horizontalCenter: parent.horizontalCenter; text: "Local files only. Nothing is fetched." }
        Rectangle {
          anchors.horizontalCenter: parent.horizontalCenter
          width: chooseRow.implicitWidth + 44; height: 44; radius: Theme.radius.row; color: Theme.color.accent
          Row { id: chooseRow; anchors.centerIn: parent; spacing: 8; Gly { anchors.verticalCenter: parent.verticalCenter; name: "stack"; box: 16; color: Theme.color.accentFg } DText { anchors.verticalCenter: parent.verticalCenter; text: "Choose folder"; role: "bodyS"; font.weight: Font.DemiBold; color: Theme.color.accentFg } }
          MouseArea { anchors.fill: parent; onClicked: root.folderAsked() }
        }
        Cap { anchors.horizontalCenter: parent.horizontalCenter; text: "Or drop a file here, or paste a path." }
      }
      // the key legend, on demand
      Rectangle {
        objectName: "legend"
        visible: !!root.m.keys
        x: 16; y: 0; width: 568; height: legendCol.implicitHeight + 2 * Theme.space.xxl
        radius: Theme.radius.card
        color: Theme.color.surfaceContainer
        border.width: 1; border.color: Theme.color.outlineVariant
        Grid {
          id: legendCol
          x: Theme.space.xxl; y: Theme.space.xxl
          columns: 2; columnSpacing: 40; rowSpacing: 8
          Repeater {
            model: root.m.legend
            Row {
              id: lg
              required property var modelData
              spacing: 10
              Rectangle { width: kk.implicitWidth + 12; height: 20; radius: 6; color: "transparent"; border.width: 1; border.color: Theme.color.outlineVariant; Cap { id: kk; anchors.centerIn: parent; text: lg.modelData.k; dim: false } }
              Cap { anchors.verticalCenter: parent ? parent.verticalCenter : undefined; text: lg.modelData.t }
            }
          }
        }
      }
    }

    // right: preview, palette, contrast
    Column {
      id: right
      visible: root.m.mode !== "empty"
      x: 600; width: root.width - 600 - 16
      spacing: 8

      Rectangle {
        objectName: "preview"
        width: parent.width; height: root.m.notice ? 90 : 130; radius: Theme.radius.row
        color: Theme.color.surfaceContainer; clip: true
        border.width: 1; border.color: Theme.color.outlineVariant
        Image { anchors.fill: parent; source: root.url(root.m.selPath); asynchronous: true; fillMode: Image.PreserveAspectCrop; sourceSize.width: 700; sourceSize.height: 260 }
        Rectangle {
          id: ptagBox
          objectName: "previewTag"
          property string text: root.m.previewing ? "Previewing" : "Current"
          x: 8; y: 8; width: ptag.implicitWidth + 20; height: 24; radius: 12; color: Qt.alpha(Theme.color.bg, 0.82)
          Row { id: ptag; anchors.centerIn: parent; spacing: 6; Gly { visible: root.m.previewing; anchors.verticalCenter: parent.verticalCenter; name: "image"; box: 14; color: Theme.color.accent } Cap { anchors.verticalCenter: parent.verticalCenter; text: ptagBox.text; dim: false; color: root.m.previewing ? Theme.color.accent : Theme.color.fg } }
        }
        Rectangle { x: parent.width - width - 8; y: parent.height - height - 6; width: pn.implicitWidth + 16; height: 20; radius: 6; color: Qt.alpha(Theme.color.bg, 0.82); Cap { id: pn; objectName: "previewName"; anchors.centerIn: parent; text: root.m.selName; dim: false } }
      }

      MiniShell {
        objectName: "miniShell"
        width: parent.width
        src: root.url(root.m.selPath)
        surface: root.m.pal && root.m.pal.surface ? root.m.pal.surface : ""
        text: root.m.pal && root.m.pal.text ? root.m.pal.text : ""
      }

      Row {
        objectName: "swatches"
        width: parent.width
        spacing: 6
        Repeater {
          model: root.m.swatches
          Column {
            id: sw
            required property var modelData
            width: (parent.width - 24) / 5
            spacing: 3
            Rectangle {
              objectName: "swatch"
              width: parent.width; height: 22; radius: 6
              color: sw.modelData.src === "pal" ? sw.modelData.c : Theme.color[sw.modelData.k]
              border.width: 1; border.color: Qt.alpha(Theme.color.fg, 0.2)
            }
            Cap { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: sw.modelData.n }
          }
        }
      }

      Row {
        objectName: "contrastRow"
        visible: !!root.m.contrast.show
        width: parent.width; height: 32
        spacing: 8
        Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 10; height: 10; radius: 5; color: root.m.contrast.pass ? Theme.color.accent : Theme.color.failed }
        Cap { objectName: "contrastText"; anchors.verticalCenter: parent.verticalCenter; text: root.m.contrast.text; dim: false; color: root.m.contrast.pass ? Theme.color.fg : Theme.color.failed }
        Rectangle {
          visible: !!root.m.contrast.tuned
          objectName: "tunedTag"
          anchors.verticalCenter: parent.verticalCenter
          width: tt.implicitWidth + 16; height: 20; radius: 10; color: "transparent"; border.width: 1; border.color: Theme.color.waiting
          Cap { id: tt; anchors.centerIn: parent; text: "tuned"; dim: false; color: Theme.color.waiting }
        }
        Item { visible: !!root.m.contrast.canUntune; width: Math.max(0, parent.width - 220 - ub.width); height: 1 }
        Rectangle {
          id: ub
          objectName: "untuneBtn"
          visible: !!root.m.contrast.canUntune
          anchors.verticalCenter: parent.verticalCenter
          width: ubt.implicitWidth + 20; height: 32; radius: 8; color: "transparent"; border.width: 1; border.color: Theme.color.outlineVariant
          Cap { id: ubt; anchors.centerIn: parent; text: root.m.contrast.untuneLabel; dim: false }
          MouseArea { anchors.fill: parent; onClicked: root.untuneToggled() }
        }
      }

      Row {
        objectName: "tagRow"
        visible: root.m.tags.length > 0 && !!root.m.suggestion !== undefined && root.m.tags.length > 0
        width: parent.width; height: 32
        spacing: 8
        Gly { anchors.verticalCenter: parent.verticalCenter; name: "sparkle"; box: 16; color: Theme.color.accent }
        Repeater {
          model: root.m.tags
          Rectangle {
            required property string modelData
            anchors.verticalCenter: parent.verticalCenter
            width: tg.implicitWidth + 16; height: 20; radius: 10; color: Theme.color.surfaceContainer
            Cap { id: tg; anchors.centerIn: parent; text: parent.modelData; dim: false }
          }
        }
        Cap { anchors.verticalCenter: parent.verticalCenter; text: "computed locally" }
      }
    }

    // palette source, pinned to the bottom of the right pane
    Column {
      visible: root.m.mode !== "empty"
      x: 600; width: root.width - 600 - 16
      y: parent.height - height - 12
      spacing: 4
      Cap { text: "Palette from" }
      Rectangle {
        width: parent.width; height: 44; radius: Theme.radius.row
        color: Theme.color.bg; border.width: 1; border.color: Theme.color.outlineVariant
        Row {
          anchors.fill: parent; anchors.margins: 3; spacing: 3
          Repeater {
            model: root.m.modes
            Rectangle {
              id: seg
              required property var modelData
              required property int index
              objectName: "paletteSeg"
              property string text: modelData.name
              width: (parent.width - 6) / 3; height: parent.height
              radius: 8
              color: modelData.on ? Theme.color.surfaceContainer : "transparent"
              Row { anchors.centerIn: parent; spacing: 4
                Cap { text: seg.modelData.key; color: Theme.color.unknown; dim: false }
                Cap { text: seg.modelData.name; dim: false; color: seg.modelData.on ? Theme.color.accent : Theme.color.fg; font.weight: seg.modelData.on ? Font.DemiBold : Font.Normal }
              }
              MouseArea { anchors.fill: parent; onClicked: root.paletteChosen(seg.index) }
            }
          }
        }
      }
    }

    Column {
      objectName: "emptyPane"
      visible: root.m.mode === "empty"
      x: 600; width: root.width - 600 - 16; height: parent.height - 12
      Rectangle {
        width: parent.width; height: parent.height; radius: Theme.radius.row
        color: "transparent"; border.width: 1; border.color: Theme.color.outlineVariant
        Column {
          anchors.centerIn: parent; width: parent.width - 48; spacing: 8
          Gly { anchors.horizontalCenter: parent.horizontalCenter; name: "image"; box: 28; color: Theme.color.fgDim }
          Cap { width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap; text: "Hover or arrow over a wallpaper to preview it live. Esc puts it back." }
        }
      }
    }
  }

  // ---- bottom bar ------------------------------------------------------------------------
  Rectangle {
    id: bar
    y: parent.height - 72
    width: parent.width; height: 72
    color: Theme.color.surface
    radius: Theme.radius.panel
    Rectangle { y: 0; width: parent.width; height: parent.radius; color: parent.color }
    Rectangle { y: 0; width: parent.width; height: 1; color: Theme.color.outlineVariant }

    Row {
      id: leftRow
      x: 16; height: parent.height
      spacing: 10
      Chip { objectName: "targetBtn"; anchors.verticalCenter: parent.verticalCenter; icon: "squares-four"; text: root.m.target.label; onClicked: root.targetCycled() }
      Chip { objectName: "shuffleBtn"; anchors.verticalCenter: parent.verticalCenter; icon: "arrow-clockwise"; text: root.m.shuffle.label; on: !!root.m.shuffle.on; onClicked: root.shuffleToggled() }
      Rectangle {
        objectName: "lockSwitch"
        anchors.verticalCenter: parent.verticalCenter
        width: lrow.implicitWidth + 18; height: 36; radius: Theme.radius.row
        color: Theme.color.bg; border.width: 1; border.color: Theme.color.outlineVariant
        Row {
          id: lrow
          anchors.centerIn: parent; spacing: 8
          Gly { anchors.verticalCenter: parent.verticalCenter; name: "lock"; box: 16; color: Theme.color.fg }
          Cap { anchors.verticalCenter: parent.verticalCenter; text: "Use for lock"; dim: false }
          Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 30; height: 16; radius: 8; color: root.m.lock ? Theme.color.accent : Theme.color.outlineVariant
            Rectangle { y: 2; x: root.m.lock ? 16 : 2; width: 12; height: 12; radius: 6; color: Theme.color.fg; Behavior on x { Anim { duration: Theme.motion.fast } } }
          }
        }
        MouseArea { anchors.fill: parent; onClicked: root.lockToggled() }
      }
    }

    // the middle: keys, or the next shuffle
    Row {
      objectName: "midHint"
      visible: root.m.shuffle.mid === "hint"
      x: leftRow.x + leftRow.width + 24
      height: parent.height; spacing: 8
      Cap { anchors.verticalCenter: parent.verticalCenter; text: "Enter set" }
      Cap { anchors.verticalCenter: parent.verticalCenter; text: "·" }
      Cap { anchors.verticalCenter: parent.verticalCenter; text: "Esc revert" }
      Cap { anchors.verticalCenter: parent.verticalCenter; text: "·" }
      Cap { anchors.verticalCenter: parent.verticalCenter; text: "? keys" }
    }
    Row {
      objectName: "midNext"
      visible: root.m.shuffle.mid === "next"
      x: leftRow.x + leftRow.width + 24
      height: parent.height; spacing: 8
      Gly { anchors.verticalCenter: parent.verticalCenter; name: "clock"; box: 14; color: Theme.color.fgDim }
      Cap { anchors.verticalCenter: parent.verticalCenter; text: "next " + root.m.shuffle.next }
    }
    Row {
      objectName: "midPaused"
      visible: root.m.shuffle.mid === "paused"
      x: leftRow.x + leftRow.width + 24
      height: parent.height; spacing: 8
      Gly { anchors.verticalCenter: parent.verticalCenter; name: "pause"; box: 14; color: Theme.color.waiting }
      Cap { anchors.verticalCenter: parent.verticalCenter; text: "Paused, focus mode"; dim: false; color: Theme.color.waiting }
    }

    Rectangle {
      id: setBtn
      objectName: "setBtn"
      property string text: "Set wallpaper"
      x: parent.width - width - 16
      anchors.verticalCenter: parent.verticalCenter
      width: srow.implicitWidth + 44; height: 44; radius: Theme.radius.row
      color: root.m.setEnabled ? Theme.color.accent : Theme.color.surfaceContainer
      Row {
        id: srow
        anchors.centerIn: parent; spacing: 10
        DText { anchors.verticalCenter: parent.verticalCenter; text: "Set wallpaper"; role: "bodyS"; font.weight: Font.DemiBold; color: root.m.setEnabled ? Theme.color.accentFg : Theme.color.fgDim }
        Rectangle { anchors.verticalCenter: parent.verticalCenter; width: ek.implicitWidth + 12; height: 20; radius: 6; color: "transparent"; border.width: 1; border.color: root.m.setEnabled ? Theme.color.accentFg : Theme.color.outlineVariant
          Cap { id: ek; anchors.centerIn: parent; text: "Enter"; dim: false; color: root.m.setEnabled ? Theme.color.accentFg : Theme.color.fgDim } }
      }
      MouseArea { anchors.fill: parent; enabled: root.m.setEnabled; onClicked: root.applied(false) }
    }
  }

  // ---- toast -----------------------------------------------------------------------------
  Rectangle {
    id: toast
    objectName: "toast"
    visible: !!root.m.toast
    x: 16; y: parent.height - 72 - 52
    width: trow.implicitWidth + 2 * Theme.space.xxl; height: 40
    radius: Theme.radius.card
    color: Theme.color.surfaceContainerHigh
    border.width: 1; border.color: Theme.color.outline
    property string text: "Wallpaper set."
    Row {
      id: trow
      anchors.centerIn: parent; spacing: 12
      Gly { anchors.verticalCenter: parent.verticalCenter; name: "check-circle"; box: 16; color: Theme.color.accent }
      DText { anchors.verticalCenter: parent.verticalCenter; text: "Wallpaper set."; role: "bodyS" }
      Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 20; height: 20; radius: 6; color: "transparent"; border.width: 1; border.color: Theme.color.outlineVariant; Cap { anchors.centerIn: parent; text: "u"; dim: false } }
      Cap { anchors.verticalCenter: parent.verticalCenter; text: "10s" }
    }
    MouseArea { anchors.fill: parent; onClicked: root.undone() }
  }
}
