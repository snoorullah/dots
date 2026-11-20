pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.modules.theme
import qs.modules.common
import qs.modules.overview
import qs.modules.cc.parts
import qs.modules.cc.pages
import "js/Queue.js" as Q

// The whole control centre as one Item: header, nav, the page for the current tab, footer.
// ControlCentre wraps it in a full-screen window; the tests render it on a plain stage.
FocusScope {
  id: v
  // the logout countdown ticks each second, only while the control centre is on screen
  property real tickNow: Date.now() / 1000
  Timer { interval: 1000; repeat: true; triggeredOnStart: true; running: v.visible; onTriggered: v.tickNow = Date.now() / 1000 }
  objectName: "ccView"
  signal closeRequested()

  readonly property bool dim: Feed.dim
  readonly property bool listTab: CcState.tab === "queue" || CcState.tab === "inbox"

  Rectangle { anchors.fill: parent; color: Theme.color.bg }

  // ---- header -----------------------------------------------------------------
  Item {
    id: header
    objectName: "ccHeader"
    width: parent.width
    height: 72
    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.color.outlineVariant }
    RowLayout {
      anchors.fill: parent
      anchors.leftMargin: 24
      anchors.rightMargin: 24
      spacing: 24
      Icon { name: "squares-four"; active: true; size: 28; color: Theme.color.accent; Layout.alignment: Qt.AlignVCenter }
      ColumnLayout {
        Layout.fillWidth: true
        spacing: 0
        Cap { text: "NOW" }
        DText {
          Layout.fillWidth: true
          role: "headline"
          elide: Text.ElideRight
          opacity: v.dim ? 0.6 : 1
          objectName: "ccNowText"
          text: Feed.task ? (Q.label(Feed.task.ticket, Feed.task.ref, Feed.task.desc) || "Untitled") : "No task in hand"
        }
      }
      Btn { objectName: "backBtn"; text: "Back to task"; icon: "arrow-u-down-left"; keyHint: "Esc"; onClicked: v.closeRequested() }
      Column {
        objectName: "logoutBlock"
        Layout.alignment: Qt.AlignVCenter
        visible: logoutText.text !== ""
        DText { anchors.right: parent.right; text: "Logout in"; role: "caption"; font.capitalization: Font.MixedCase; font.letterSpacing: 0 }
        DText {
          id: logoutText
          anchors.right: parent.right
          role: "headline"
          mono: true
          font.weight: Font.Medium
          text: Q.logoutLeft(Feed.today ? Feed.today.workedSec : undefined, Feed.actDoc ? Feed.actDoc.ts : 0, v.tickNow)
        }
      }
      Column {
        Layout.alignment: Qt.AlignVCenter
        DText { anchors.right: parent.right; text: "Day so far"; role: "caption"; font.capitalization: Font.MixedCase; font.letterSpacing: 0 }
        DText {
          anchors.right: parent.right
          role: "headline"
          font.weight: Font.Medium
          text: (CcState.loginTs > 0) ? Q.hm(Math.max(0, Feed.nowTs - CcState.loginTs)) : "--:--"
        }
      }
    }
  }

  // ---- nav --------------------------------------------------------------------
  Item {
    id: nav
    objectName: "ccNav"
    y: header.height
    width: 208
    height: parent.height - header.height - footer.height
    Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: Theme.color.outlineVariant }
    Column {
      x: 12
      y: 16
      width: parent.width - 24
      spacing: 4
      Repeater {
        model: [
          { id: "queue", label: "Queue", icon: "stack", n: CcState.counts.queue },
          { id: "inbox", label: "Inbox", icon: "tray", n: CcState.counts.inbox },
          { id: "agents", label: "Agents", icon: "sparkle", n: CcState.agents.length },
          { id: "work", label: "Tasks", icon: "briefcase", n: CcState.nextTasks.length },
          { id: "time", label: "Time", icon: "clock", n: 0 }
        ]
        Item {
          id: tab
          required property var modelData
          objectName: "navTab"
          readonly property bool on: CcState.tab === modelData.id
          width: parent.width
          height: 32
          Rectangle { anchors.fill: parent; radius: Theme.radius.row; color: tab.on ? Theme.color.surfaceContainer : (tma.containsMouse ? Qt.alpha(Theme.color.fg, Theme.alpha.hover) : "transparent") }
          Row {
            x: 10
            anchors.verticalCenter: parent.verticalCenter
            spacing: 10
            Icon { name: tab.modelData.icon; active: tab.on; size: 18; color: tab.on ? Theme.color.fg : Theme.color.fgDim; anchors.verticalCenter: parent.verticalCenter }
            DText { text: tab.modelData.label; role: "bodyS"; font.weight: tab.on ? Font.DemiBold : Font.Normal; color: tab.on ? Theme.color.fg : Theme.color.fgDim; anchors.verticalCenter: parent.verticalCenter }
          }
          DText { anchors.right: parent.right; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter; visible: tab.modelData.n > 0; text: tab.modelData.n; role: "caption"; font.capitalization: Font.MixedCase; font.letterSpacing: 0 }
          MouseArea { id: tma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: CcState.setTab(tab.modelData.id) }
        }
      }

      Cap { topPadding: 20; leftPadding: 12; bottomPadding: 8; text: "SAVED VIEWS" }
      Repeater {
        model: [["VIPs", "star"], ["Overdue", "clock-countdown"], ["Snoozed", "alarm"], ["Infra only", "hard-drives"]]
        Item {
          id: sv
          required property var modelData
          objectName: "savedView"
          readonly property bool on: CcState.view === modelData[0]
          width: parent.width
          height: 28
          Rectangle { anchors.fill: parent; radius: Theme.radius.chip + 2; color: sv.on ? Theme.color.surfaceContainer : (sma.containsMouse ? Qt.alpha(Theme.color.fg, Theme.alpha.hover) : "transparent") }
          Row {
            x: 10
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8
            Icon { name: sv.modelData[1]; size: 16; color: sv.on ? Theme.color.fg : Theme.color.fgDim; anchors.verticalCenter: parent.verticalCenter }
            DText { text: sv.modelData[0]; role: "bodyS"; color: sv.on ? Theme.color.fg : Theme.color.fgDim; anchors.verticalCenter: parent.verticalCenter }
          }
          MouseArea { id: sma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { CcState.view = sv.on ? "" : sv.modelData[0]; CcState.setTab("queue") } }
        }
      }

      Row {
        spacing: 8
        Cap { topPadding: 20; leftPadding: 12; bottomPadding: 8; text: "SOURCES" }
        StatusMark { objectName: "staleMark"; visible: v.dim; level: "unknown"; size: 14; anchors.bottom: parent.bottom; anchors.bottomMargin: 6 }
      }
      Repeater {
        model: CcState.sourceRows
        Item {
          id: sr
          required property var modelData
          objectName: "sourceRow"
          width: parent.width
          height: 22
          Row {
            x: 10
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8
            // a source that cannot be reached is the grey `?`, never a fine-looking dot
            Item {
              width: 10
              height: 10
              anchors.verticalCenter: parent.verticalCenter
              Rectangle { visible: sr.modelData.tone === ""; anchors.centerIn: parent; width: 6; height: 6; radius: 3; color: Qt.alpha(Theme.color.accent, 0.55) }
              Rectangle { visible: sr.modelData.tone === "off"; anchors.centerIn: parent; width: 6; height: 6; radius: 3; color: "transparent"; border.width: 1; border.color: Theme.color.fgFaint }
              StatusMark { visible: sr.modelData.tone === "unknown"; anchors.centerIn: parent; level: "unknown"; size: 10 }
            }
            DText { text: sr.modelData.name; role: "caption"; font.capitalization: Font.MixedCase; font.letterSpacing: 0; color: Theme.color.fg; anchors.verticalCenter: parent.verticalCenter }
          }
          DText { anchors.right: parent.right; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter; text: sr.modelData.label; role: "caption"; font.capitalization: Font.MixedCase; font.letterSpacing: 0 }
        }
      }
    }
  }

  // ---- page -------------------------------------------------------------------
  Item {
    id: page
    objectName: "ccPage"
    x: nav.width
    y: header.height
    width: parent.width - nav.width
    height: nav.height

    QueuePage { anchors.fill: parent; visible: v.listTab; dim: v.dim }
    AgentsPage { anchors.fill: parent; visible: CcState.tab === "agents"; dim: v.dim }
    WorkPage { anchors.fill: parent; visible: CcState.tab === "work"; dim: v.dim }
    TimePage { anchors.fill: parent; visible: CcState.tab === "time"; dim: v.dim }
  }

  // ---- footer -----------------------------------------------------------------
  Item {
    id: footer
    objectName: "ccFooter"
    y: parent.height - height
    width: parent.width
    height: 40
    Rectangle { width: parent.width; height: 1; color: Theme.color.outlineVariant }
    RowLayout {
      anchors.fill: parent
      anchors.leftMargin: 24
      anchors.rightMargin: 24
      spacing: 20
      DText { objectName: "statusLine"; Layout.fillWidth: true; text: CcState.status; role: "bodyS"; dim: true; elide: Text.ElideRight }
      Btn { objectName: "undoBtn"; visible: CcState.canUndo; small: true; text: "Undo"; icon: "arrow-counter-clockwise"; onClicked: CcState.undo() }
      DText { text: "n/e move · r reply · g agent · q queue · s snooze · c comment · o open"; role: "caption"; font.capitalization: Font.MixedCase; font.letterSpacing: 0 }
    }
  }

  // ---- keys -------------------------------------------------------------------
  focus: true
  Keys.onPressed: function (e) {
    if (e.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) return
    if (e.key === Qt.Key_Escape) {
      if (CcState.mode !== "") CcState.mode = ""
      else v.closeRequested()
      e.accepted = true
      return
    }
    if (!v.listTab) return
    if (e.key === Qt.Key_Down || e.text === "n") { CcState.step(1); e.accepted = true }
    else if (e.key === Qt.Key_Up || e.text === "e") { CcState.step(-1); e.accepted = true }
    else if (e.text.length === 1 && CcState.runKey(e.text)) e.accepted = true
  }
}
