pragma ComponentBehavior: Bound
import QtQuick
import "../theme"
import "../common"
import "../barpop"

// Body of the clock and calendar popup. `model` is js/Cal.js build(). Read-only: the
// calendar is a mirror, so Join, Open calendar and Add event render disabled; opening an
// event row only expands its details inline.
Item {
  id: root

  property var model: ({ time: "", dateLine: "", today: true, stale: false, strip: ({ tone: "empty", icon: "calendar-blank", label: "", title: "", sub: "", btn: "" }),
                         banner: null, rows: [], week: [], foot: ({ t: "", stale: false }), month: [], monthLabel: "", weekLabel: "" })
  property string view: "day"       // day | month
  // names Cal.js hands to Icon; listed here so tools/gen-phosphor-qml.py keeps them in the registry
  readonly property var usedIcons: ({ meeting: "video", soon: "clock", prayer: "mosque", empty: "calendar-blank" })

  signal toggleOpen(string id)
  signal toggleView()
  signal stepMonth(int delta)

  implicitWidth: 368
  implicitHeight: col.implicitHeight
  width: implicitWidth

  function toneColor(t) {
    return t === "amber" ? Theme.color.waiting : ((t === "focus" || t === "empty") ? Theme.color.outline : Theme.color.accent)
  }

  Column {
    id: col
    width: parent.width
    spacing: Theme.space.l

    // clock header
    Item {
      width: parent.width
      height: 64
      Column {
        anchors.verticalCenter: parent.verticalCenter
        DText { objectName: "clock"; text: root.model.time; role: "display"; mono: true; font.letterSpacing: -0.4 }
        Cap { objectName: "dateLine"; text: root.model.dateLine; dim: true }
      }
      Pill {
        objectName: "todayChip"
        visible: root.model.today
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: "Today"
        tone: "accent"
        bordered: true
      }
      Row {
        objectName: "staleChip"
        visible: !root.model.today
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.space.s
        StatusMark { level: "unknown"; size: 18; anchors.verticalCenter: parent.verticalCenter }
        Cap { anchors.verticalCenter: parent.verticalCenter; text: root.model.foot.t; dim: true }
      }
    }

    // NEXT strip
    Rectangle {
      objectName: "strip"
      width: parent.width
      height: 72
      radius: Theme.radius.row + 2
      color: Qt.alpha(root.toneColor(root.model.strip.tone), root.model.strip.tone === "empty" ? 0.04 : 0.1)
      border.width: 1
      border.color: Qt.alpha(root.toneColor(root.model.strip.tone), 0.4)
      Row {
        anchors.fill: parent
        anchors.leftMargin: Theme.space.xl
        anchors.rightMargin: Theme.space.l
        spacing: Theme.space.l
        Rectangle {
          anchors.verticalCenter: parent.verticalCenter
          width: 32; height: 32; radius: 16
          color: "transparent"
          border.width: 1
          border.color: root.toneColor(root.model.strip.tone)
          Gly { anchors.centerIn: parent; name: root.model.strip.icon; box: 18; color: root.toneColor(root.model.strip.tone) }
        }
        Column {
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width - 32 - (stripBtn.visible ? stripBtn.width + Theme.space.l : 0) - Theme.space.l
          Lbl { text: root.model.strip.label; color: root.toneColor(root.model.strip.tone) }
          DText { objectName: "stripTitle"; width: parent.width; text: root.model.strip.title; role: "body"; font.weight: Font.DemiBold; elide: Text.ElideRight }
          Cap { width: parent.width; text: root.model.strip.sub; dim: true; elide: Text.ElideRight }
        }
        Btn {
          id: stripBtn
          objectName: "stripBtn"
          visible: root.model.strip.btn !== ""
          anchors.verticalCenter: parent.verticalCenter
          label: root.model.strip.btn
          kind: root.model.strip.kind === "amber" ? "amber" : "ghost"
          stub: true
        }
      }
    }

    Rectangle {
      objectName: "banner"
      visible: root.model.banner !== null && root.model.banner !== undefined
      width: parent.width
      height: visible ? 40 : 0
      radius: Theme.radius.row
      color: "transparent"
      border.width: 1
      border.color: Qt.alpha(Theme.color.unknown, 0.6)
      Row {
        anchors.verticalCenter: parent.verticalCenter
        x: Theme.space.l
        spacing: Theme.space.m
        StatusMark { anchors.verticalCenter: parent.verticalCenter; level: "unknown"; size: 16 }
        Cap {
          anchors.verticalCenter: parent.verticalCenter
          width: col.width - 16 - 3 * Theme.space.l
          text: root.model.banner ? root.model.banner.text : ""
          wrapMode: Text.WordWrap
          dim: true
        }
      }
    }

    // day timeline
    Flickable {
      id: flick
      objectName: "timeline"
      visible: root.view === "day"
      width: parent.width
      height: visible ? Math.min(tl.implicitHeight, 280) : 0
      contentHeight: tl.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds

      Column {
        id: tl
        width: flick.width
        Repeater {
          model: root.model.rows
          Item {
            id: tr
            objectName: "tlRow"
            required property var modelData
            width: tl.width
            height: Math.max(rowBody.implicitHeight + 2, tr.modelData.k === "now" ? 20 : 30)
            opacity: modelData.dim ? 0.4 : (modelData.past ? 0.55 : (modelData.unk ? 0.6 : 1))

            Cap {
              x: 0; y: tr.modelData.k === "ev" ? 7 : 4
              width: 40; horizontalAlignment: Text.AlignRight
              text: tr.modelData.t
              
              height: 20
              color: tr.modelData.k === "now" ? Theme.color.accent : ((tr.modelData.next || tr.modelData.active || tr.modelData.cur) ? Theme.color.fg : Theme.color.fgDim)
              font.weight: (tr.modelData.k === "now" || tr.modelData.next || tr.modelData.active || tr.modelData.cur) ? Font.DemiBold : Font.Normal
              dim: false
            }
            // spine and dot
            Rectangle { x: 48 + 6; width: 2; height: parent.height; color: Theme.color.outlineVariant }
            Rectangle {
              x: 48 + (tr.modelData.k === "now" ? 1 : 3)
              y: tr.modelData.k === "now" ? 4 : (tr.modelData.k === "ev" ? 12 : 9)
              width: tr.modelData.k === "now" ? 12 : (tr.modelData.k === "free" ? 6 : 8)
              height: width; radius: width / 2
              visible: tr.modelData.k !== "free"
              color: (tr.modelData.k === "now" || tr.modelData.next || tr.modelData.active || tr.modelData.k === "pr") && !tr.modelData.unv ? Theme.color.accent : Theme.color.surface
              border.width: 2
              border.color: tr.modelData.unv ? Theme.color.waiting : (tr.modelData.k === "held" ? Theme.color.outline : (tr.modelData.k === "ev" && !tr.modelData.next && !tr.modelData.active ? Theme.color.outline : Theme.color.accent))
            }

            Column {
              id: rowBody
              x: 48 + 14 + Theme.space.m
              width: parent.width - x
              spacing: 4

              // event
              Rectangle {
                objectName: "evRow"
                visible: tr.modelData.k === "ev"
                width: parent.width
                height: visible ? 34 : 0
                radius: Theme.radius.row
                color: tr.modelData.active ? Qt.alpha(Theme.color.accent, 0.14) : (tr.modelData.next ? Qt.alpha(Theme.color.accent, 0.1) : Theme.color.surface)
                border.width: 1
                border.color: (tr.modelData.active || tr.modelData.next) ? Theme.color.accent : Theme.color.outlineVariant
                clip: true
                Row {
                  anchors.fill: parent
                  anchors.leftMargin: Theme.space.xl
                  anchors.rightMargin: Theme.space.xl
                  spacing: Theme.space.m
                  DText { anchors.verticalCenter: parent.verticalCenter; width: parent.width - metaRow.width - Theme.space.m; text: tr.modelData.title || ""; role: "bodyS"; elide: Text.ElideRight }
                  Row {
                    id: metaRow
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.space.m
                    StatusMark { visible: tr.modelData.unk === true; level: "unknown"; size: 14; anchors.verticalCenter: parent.verticalCenter }
                    Cap { text: tr.modelData.dur || ""; dim: true; anchors.verticalCenter: parent.verticalCenter }
                    Gly { visible: tr.modelData.tick === true; name: "check-circle"; box: 14; color: Theme.color.accent; anchors.verticalCenter: parent.verticalCenter }
                    Gly { visible: tr.modelData.link === true; name: "video"; box: 15; color: Theme.color.fgDim; anchors.verticalCenter: parent.verticalCenter }
                  }
                }
                Rectangle { visible: tr.modelData.prog > 0; x: 0; y: parent.height - 2; height: 2; width: parent.width * (tr.modelData.prog || 0) / 100; color: Theme.color.accent }
                MouseArea { anchors.fill: parent; onClicked: root.toggleOpen(tr.modelData.id) }
              }
              Rectangle {
                objectName: "evDetail"
                visible: tr.modelData.k === "ev" && tr.modelData.open === true
                width: parent.width
                height: visible ? det.implicitHeight + 2 * Theme.space.m : 0
                radius: Theme.radius.row
                color: Theme.color.surfaceContainer
                border.width: 1
                border.color: Theme.color.outlineVariant
                Column {
                  id: det
                  x: Theme.space.xl; y: Theme.space.m
                  width: parent.width - 2 * Theme.space.xl
                  Cap { width: parent.width; text: tr.modelData.d1 || ""; dim: false }
                  Cap { width: parent.width; text: tr.modelData.d2 || ""; dim: true; visible: text !== "" }
                }
              }

              // prayer
              Rectangle {
                objectName: "prRow"
                visible: tr.modelData.k === "pr"
                width: parent.width
                height: visible ? 28 : 0
                radius: Theme.radius.row
                color: tr.modelData.cur ? Qt.alpha(Theme.color.accent, 0.16) : "transparent"
                border.width: tr.modelData.cur ? 1 : 0
                border.color: Theme.color.accent
                Row {
                  anchors.fill: parent
                  anchors.leftMargin: Theme.space.xl
                  anchors.rightMargin: Theme.space.xl
                  spacing: Theme.space.m
                  Gly { anchors.verticalCenter: parent.verticalCenter; name: "moon"; box: 14; color: tr.modelData.cur ? Theme.color.accent : Theme.color.fgDim }
                  Cap { anchors.verticalCenter: parent.verticalCenter; text: tr.modelData.name || ""; font.weight: Font.DemiBold; dim: false }
                  Cap { anchors.verticalCenter: parent.verticalCenter; width: parent.width - 14 - 2 * Theme.space.m - 90; text: tr.modelData.note || ""; dim: true; elide: Text.ElideRight }
                  Row {
                    visible: tr.modelData.unv === true
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.space.s
                    StatusMark { level: "unknown"; size: 13; anchors.verticalCenter: parent.verticalCenter }
                    Cap { text: "unverified"; dim: true }
                  }
                }
              }

              // held block: says Held and nothing else
              Rectangle {
                objectName: "heldRow"
                visible: tr.modelData.k === "held"
                width: parent.width
                height: visible ? 30 : 0
                radius: Theme.radius.row
                color: Qt.alpha(Theme.color.fg, tr.modelData.active ? 0.18 : 0.08)
                border.width: 1
                border.color: Theme.color.outline
                clip: true
                Row {
                  anchors.verticalCenter: parent.verticalCenter
                  x: Theme.space.xl
                  spacing: Theme.space.m
                  Gly { name: "lock"; box: 13; color: Theme.color.fgDim; anchors.verticalCenter: parent.verticalCenter }
                  Cap { text: "Held"; font.weight: Font.DemiBold; anchors.verticalCenter: parent.verticalCenter; dim: false }
                  Cap { text: tr.modelData.range || ""; dim: true; anchors.verticalCenter: parent.verticalCenter }
                }
              }

              Item {
                objectName: "nowRow"
                visible: tr.modelData.k === "now"
                width: parent.width
                height: visible ? 18 : 0
                Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width - nowLbl.implicitWidth - Theme.space.m; height: 2; radius: 1; color: Theme.color.accent }
                Lbl { id: nowLbl; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; text: "NOW"; color: Theme.color.accent }
              }
              Cap {
                visible: tr.modelData.k === "free"
                width: parent.width
                height: visible ? 20 : 0
                text: tr.modelData.title || ""
                dim: true
              }
              Column {
                objectName: "emptyRow"
                visible: tr.modelData.k === "empty"
                width: parent.width
                height: visible ? implicitHeight + 2 * Theme.space.l : 0
                padding: Theme.space.l
                Cap { width: parent.width - 2 * Theme.space.l; text: tr.modelData.title || ""; dim: false }
                Cap { width: parent.width - 2 * Theme.space.l; text: tr.modelData.sub || ""; dim: true; wrapMode: Text.WordWrap }
              }
            }
          }
        }
      }
    }

    // week strip
    Column {
      objectName: "weekStrip"
      visible: root.view === "day"
      width: parent.width
      spacing: Theme.space.s
      Item {
        width: parent.width
        height: 20
        Lbl { text: root.model.weekLabel; anchors.verticalCenter: parent.verticalCenter }
        Cap {
          dim: false
          anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
          text: "Month"; color: Theme.color.accent
          MouseArea { anchors.fill: parent; anchors.margins: -6; onClicked: root.toggleView() }
        }
      }
      Row {
        spacing: 4
        Repeater {
          model: root.model.week
          Rectangle {
            id: wd
            objectName: "weekDay"
            required property var modelData
            width: (col.width - 6 * 4) / 7
            height: 52
            radius: Theme.radius.row
            color: modelData.today ? Qt.alpha(Theme.color.accent, 0.14) : Theme.color.surface
            border.width: 1
            border.color: modelData.today ? Theme.color.accent : Theme.color.outlineVariant
            opacity: modelData.hollow ? 0.7 : 1
            Column {
              anchors.centerIn: parent
              spacing: 2
              Lbl { anchors.horizontalCenter: parent.horizontalCenter; text: wd.modelData.dow; font.pixelSize: 10 }
              DText { anchors.horizontalCenter: parent.horizontalCenter; text: String(wd.modelData.n); role: "bodyS"; mono: true; font.weight: wd.modelData.today ? Font.DemiBold : Font.Normal }
              Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 2
                height: 5
                Repeater {
                  model: wd.modelData.dots
                  Rectangle {
                    width: 5; height: 5; radius: 2.5
                    color: wd.modelData.hollow ? "transparent" : Theme.color.accent
                    border.width: 1
                    border.color: wd.modelData.hollow ? Theme.color.fgDim : Theme.color.accent
                  }
                }
              }
            }
          }
        }
      }
    }

    // month view
    Column {
      objectName: "monthView"
      visible: root.view === "month"
      width: parent.width
      spacing: Theme.space.s
      Item {
        width: parent.width
        height: 32
        DText { anchors.verticalCenter: parent.verticalCenter; text: root.model.monthLabel; role: "title" }
        Row {
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: Theme.space.s
          Item { width: 28; height: 28; Gly { anchors.centerIn: parent; name: "caret-left"; box: 14 } MouseArea { anchors.fill: parent; onClicked: root.stepMonth(-1) } }
          Item { width: 28; height: 28; Gly { anchors.centerIn: parent; name: "caret-right"; box: 14 } MouseArea { anchors.fill: parent; onClicked: root.stepMonth(1) } }
          Cap { dim: false; anchors.verticalCenter: parent.verticalCenter; text: "Week"; color: Theme.color.accent
            MouseArea { anchors.fill: parent; anchors.margins: -6; onClicked: root.toggleView() } }
        }
      }
      Grid {
        columns: 7
        columnSpacing: 3
        rowSpacing: 3
        Repeater {
          model: ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"]
          Lbl { required property string modelData; width: (col.width - 6 * 3) / 7; horizontalAlignment: Text.AlignHCenter; text: modelData; font.pixelSize: 10 }
        }
        Repeater {
          model: root.model.month
          Rectangle {
            id: mc
            objectName: "monthCell"
            required property var modelData
            width: (col.width - 6 * 3) / 7
            height: 38
            radius: Theme.radius.chip
            color: modelData.today ? Qt.alpha(Theme.color.accent, 0.14) : Theme.color.surface
            border.width: modelData.today ? 1 : 0
            border.color: Theme.color.accent
            Column {
              anchors.centerIn: parent
              spacing: 2
              DText { anchors.horizontalCenter: parent.horizontalCenter; text: String(mc.modelData.n); role: "bodyS"; mono: true; color: mc.modelData.inMonth ? Theme.color.fg : Theme.color.fgFaint }
              Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 2
                height: 5
                Repeater {
                  model: mc.modelData.dots
                  Rectangle { width: 5; height: 5; radius: 2.5; color: mc.modelData.hollow ? "transparent" : Theme.color.accent; border.width: 1; border.color: mc.modelData.hollow ? Theme.color.fgDim : Theme.color.accent }
                }
              }
            }
          }
        }
      }
    }

    // footer
    Item {
      width: parent.width
      height: 32
      Row {
        spacing: Theme.space.m
        Btn { objectName: "openCal"; label: "Open calendar"; kind: "quiet"; stub: true }
        Btn { objectName: "addEvent"; label: "Add event"; kind: "quiet"; stub: true }
      }
      Row {
        objectName: "foot"
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.space.m
        Rectangle {
          anchors.verticalCenter: parent.verticalCenter
          width: 6; height: 6; radius: 3
          color: root.model.foot.stale ? "transparent" : Theme.color.accent
          border.width: 1
          border.color: root.model.foot.stale ? Theme.color.fgDim : Theme.color.accent
        }
        Cap { text: root.model.foot.t; dim: true }
      }
    }
  }
}
