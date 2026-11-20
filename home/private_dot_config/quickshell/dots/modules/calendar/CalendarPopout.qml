import QtQuick
import "../common"
import "../barpop"
import "js/Cal.js" as Cal

// The clock and calendar popup. Events come from the optional calendar.json next to
// attention.json, prayers from the prayer file. Nothing is written anywhere: the work
// calendar is a mirror, and Join, Open calendar and Add event are disabled stubs.
Popout {
  id: win

  name: "calendar"
  panelWidth: 400

  property string openId: ""
  property string view: "day"
  property date shownMonth: new Date()
  onWantedChanged: if (wanted) { openId = ""; view = "day"; shownMonth = new Date(); src.now = new Date(); }

  SalahSource { id: src }
  CalendarDoc { id: cal }

  function step(delta) { shownMonth = new Date(shownMonth.getFullYear(), shownMonth.getMonth() + delta, 1); }

  readonly property var built: Cal.build(cal.doc, src.parsed, src.now, { openId: openId, month: shownMonth })

  CalendarPanel {
    width: parent.width
    model: win.built
    view: win.view
    onToggleOpen: id => win.openId = (win.openId === id ? "" : id)
    onToggleView: win.view = (win.view === "day" ? "month" : "day")
    onStepMonth: delta => win.step(delta)
  }
}
