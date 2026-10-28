import QtQuick
import "../theme"
import "../common"

// A month grid. No sync, no events: it answers "what date is the 14th". Weeks start on
// Monday. Today gets the neutral lift, never a colour.
Popout {
  id: win

  property date shownMonth: new Date()
  readonly property date today: new Date()

  function step(delta) {
    var d = new Date(shownMonth.getFullYear(), shownMonth.getMonth() + delta, 1);
    shownMonth = d;
  }
  // the 42 cells of the grid: { day, inMonth }
  readonly property var cells: {
    var y = shownMonth.getFullYear(), m = shownMonth.getMonth();
    var first = new Date(y, m, 1);
    var lead = (first.getDay() + 6) % 7;
    var out = [];
    for (var i = 0; i < 42; i++) {
      var d = new Date(y, m, 1 - lead + i);
      out.push({ day: d.getDate(), inMonth: d.getMonth() === m,
                 isToday: d.getFullYear() === today.getFullYear() && d.getMonth() === today.getMonth() && d.getDate() === today.getDate() });
    }
    return out;
  }

  name: "calendar"
  panelWidth: 300
  onWantedChanged: if (wanted) shownMonth = new Date()

  Column {
    width: parent.width
    spacing: Theme.space.l

    Row {
      width: parent.width

      MouseArea {
        width: 28; height: 28
        onClicked: win.step(-1)
        Icon { anchors.centerIn: parent; text: "chevron_left" }
      }
      DText {
        width: parent.width - 56
        height: 28
        horizontalAlignment: Text.AlignHCenter
        text: Qt.formatDate(win.shownMonth, "MMMM yyyy")
        role: "title"
      }
      MouseArea {
        width: 28; height: 28
        onClicked: win.step(1)
        Icon { anchors.centerIn: parent; text: "chevron_right" }
      }
    }

    Grid {
      columns: 7
      width: parent.width

      Repeater {
        model: ["M", "T", "W", "T", "F", "S", "S"]
        DText {
          required property string modelData
          width: parent.width / 7
          height: 22
          horizontalAlignment: Text.AlignHCenter
          text: modelData
          dim: true
          role: "caption"
        }
      }
      Repeater {
        model: win.cells
        Item {
          id: cell
          required property var modelData
          width: parent.width / 7
          height: 28
          Rectangle {
            anchors.centerIn: parent
            width: 26
            height: 26
            radius: Theme.radius.chip
            color: Qt.alpha(Theme.color.fg, Theme.alpha.hover)
            visible: cell.modelData.isToday
          }
          DText {
            anchors.centerIn: parent
            mono: true
            text: cell.modelData.day
            color: cell.modelData.inMonth ? Theme.color.fg : Theme.color.fgFaint
            role: "bodyS"
          }
        }
      }
    }
  }
}
