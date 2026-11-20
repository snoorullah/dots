import QtQuick
import "../theme"
import "../common"
import "../../services"

// Notification history (newest first, scrolls past 520 px) and the do-not-disturb switch,
// as a popout under the bell. Each row is a NotifCard: click opens the source, × dismisses.
Popout {
  id: win

  property var notifs: null

  name: "center"
  panelWidth: 380

  Column {
    width: parent.width
    spacing: Theme.space.l

    Row {
      width: parent.width
      spacing: Theme.space.l

      DText {
        id: title
        text: "Notifications"
        role: "title"
        width: parent.width - clear.width - dndBtn.width - 2 * Theme.space.l
      }
      MouseArea {
        id: dndBtn
        width: dndLabel.implicitWidth + Theme.space.xl
        height: 24
        onClicked: if (win.notifs) win.notifs.dnd = !win.notifs.dnd
        Rectangle {
          anchors.fill: parent
          radius: Theme.radius.chip
          color: win.notifs && win.notifs.dnd ? Qt.alpha(Theme.color.accent, Theme.alpha.wash) : Qt.alpha(Theme.color.fg, Theme.alpha.hover)
        }
        DText {
          id: dndLabel
          anchors.centerIn: parent
          text: "Do not disturb"
          role: "bodyS"
        }
      }
      MouseArea {
        id: clear
        width: clearLabel.implicitWidth + Theme.space.xl
        height: 24
        onClicked: if (win.notifs) win.notifs.clearAll()
        Rectangle {
          anchors.fill: parent
          radius: Theme.radius.chip
          color: Qt.alpha(Theme.color.fg, Theme.alpha.hover)
        }
        DText {
          id: clearLabel
          anchors.centerIn: parent
          text: "Clear"
          role: "bodyS"
        }
      }
    }

    DText {
      visible: !win.notifs || win.notifs.count === 0
      text: win.notifs && win.notifs.held ? "another daemon owns notifications" : "nothing new"
      dim: true
    }

    Flickable {
      id: list
      width: parent.width
      height: Math.min(contentHeight, 520)
      contentHeight: rows.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      visible: win.notifs !== null && win.notifs.count > 0

      Column {
        id: rows
        width: list.width
        spacing: Theme.space.l

        Repeater {
          // newest first
          model: win.notifs && win.notifs.model ? win.notifs.model.values.slice().reverse() : []

          Rectangle {
            id: row
            required property var modelData
            width: rows.width
            height: card.implicitHeight + 2 * Theme.space.l
            radius: Theme.radius.chip
            color: hov.hovered ? Qt.alpha(Theme.color.fg, Theme.alpha.hover) : "transparent"

            HoverHandler { id: hov }

            NotifCard {
              id: card
              x: Theme.space.l
              y: Theme.space.l
              width: parent.width - 2 * Theme.space.l
              notification: row.modelData
              summaryLines: 2
              bodyLines: 3
              onOpened: Ui.close()
            }
          }
        }
      }
    }
  }
}
