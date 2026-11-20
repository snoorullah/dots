import Quickshell
import Quickshell.Services.SystemTray
import QtQuick
import "../theme"
import "../common"
import "../../services"
import "js/Tray.js" as T

// The tray popover: every StatusNotifier app, grouped by status, filterable. Open calls the
// app's own activate(); Menu drills into the app's menu through QsMenuOpener. No rule
// (pin, hide) is persisted yet.
Popout {
  id: win

  name: "tray"
  panelWidth: 360

  property string selId: ""
  property string drillId: ""
  property string query: ""

  onWantedChanged: if (wanted) { selId = ""; drillId = ""; panel.query = ""; }

  function statusName(s) {
    return s === Status.NeedsAttention ? "NeedsAttention" : (s === Status.Active ? "Active" : "Passive");
  }
  function itemById(id) {
    var v = SystemTray.items.values;
    for (var i = 0; i < v.length; i++) if (v[i].id === id) return v[i];
    return null;
  }

  readonly property var list: SystemTray.items.values.map(function (it) {
    return { id: it.id, title: it.title || it.tooltipTitle, status: win.statusName(it.status), hasMenu: it.hasMenu, icon: it.icon };
  })
  readonly property var built: T.build(list, query)
  readonly property var drillItem: drillId === "" ? null : itemById(drillId)

  QsMenuOpener { id: opener; menu: win.drillItem ? win.drillItem.menu : null }

  readonly property var drillModel: {
    if (!win.drillItem) return null;
    var kids = opener.children ? opener.children.values : [];
    return {
      name: win.drillItem.title || win.drillItem.id,
      status: win.statusName(win.drillItem.status) === "NeedsAttention" ? "Needs attention" : "",
      items: kids.map(function (e) { return { label: e.text, sep: e.isSeparator, enabled: e.enabled, sub: e.hasChildren }; })
    };
  }

  TrayPanel {
    id: panel
    width: parent.width
    model: win.built
    drill: win.drillModel
    selId: win.selId
    onQueryChanged: win.query = query
    onRowPicked: id => win.selId = id
    onActivate: id => { var it = win.itemById(id); if (it) { it.activate(); Ui.close(); } }
    onOpenMenu: id => win.drillId = id
    onBack: win.drillId = ""
    onTrigger: index => {
      var kids = opener.children ? opener.children.values : [];
      if (kids[index]) { kids[index].triggered(); Ui.close(); }
    }
  }
}
