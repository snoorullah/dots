import QtQuick
import "../common"

// The salah popup, hung under the bar chip. Times come from the prayer file via
// SalahSource; opening does not log anything.
Popout {
  id: win

  name: "salah"
  panelWidth: 360

  SalahSource { id: src }
  onWantedChanged: if (wanted) src.now = new Date()

  readonly property var days: ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
  readonly property var months: ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

  SalahPanel {
    width: parent.width
    model: src.model
    dateText: win.days[src.now.getDay()] + " " + src.now.getDate() + " " + win.months[src.now.getMonth()] + " " + src.now.getFullYear()
  }
}
