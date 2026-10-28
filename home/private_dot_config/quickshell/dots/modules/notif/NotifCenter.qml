import QtQuick
import "../theme"
import "../common"

// Notification history and the do-not-disturb switch, as a popout under the bell.
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
          color: win.notifs && win.notifs.dnd ? Qt.alpha(Theme.color.amber, Theme.alpha.wash) : Qt.alpha(Theme.color.fg, Theme.alpha.hover)
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

    Repeater {
      model: win.notifs ? win.notifs.model : null

      Item {
        id: row
        required property var modelData
        width: parent.width
        height: item.implicitHeight + Theme.space.l

        Column {
          id: item
          width: parent.width
          spacing: Theme.space.xs
          DText {
            width: parent.width
            text: row.modelData.summary
            elide: Text.ElideRight
            font.weight: Font.DemiBold
          }
          DText {
            width: parent.width
            text: row.modelData.body
            dim: true
            role: "bodyS"
            wrapMode: Text.WordWrap
            maximumLineCount: 3
            elide: Text.ElideRight
            visible: text !== ""
          }
        }
        MouseArea {
          anchors.fill: parent
          onClicked: row.modelData.dismiss()
        }
      }
    }
  }
}
