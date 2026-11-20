import Quickshell
import QtQuick
import "../common"
import "../../services"
import qs.modules.overview
import "js/Waiting.js" as W

// The "waiting on you" popup. Rows are the attention feed's items someone waits on; every
// write (snooze, done, draft) is a disabled stub. Jump and Open are local.
Popout {
  id: win

  name: "waiting"
  panelWidth: 360

  property string filter: "all"
  property string focusId: ""

  SalahSource { id: salah }
  onWantedChanged: if (wanted) { filter = "all"; focusId = ""; salah.now = new Date(); }

  readonly property var built: W.build(Feed.attDoc ? Feed.attDoc.items : [], {
    filter: filter, focusId: focusId, focusFirst: true, stale: Feed.degraded,
    prayerIn: salah.minutesToNext >= 0 && salah.minutesToNext <= 30 ? salah.minutesToNext : -1 })

  WaitingPanel {
    width: parent.width
    model: win.built
    onChipPicked: key => { win.filter = key; win.focusId = ""; }
    onRowPicked: id => win.focusId = id
    onJump: ref => Actions.jump({ ref: ref })
    onOpenUrl: url => { if (/^https:\/\/[^\s]+$/.test(url)) Quickshell.execDetached(["xdg-open", url]); }
    onSidebar: { Ui.close(); Ui.toggleSidebar(); }
  }
}
