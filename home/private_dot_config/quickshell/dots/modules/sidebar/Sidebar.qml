pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.modules.theme
import qs.modules.common
import "../../services"
import "js/SideModel.js" as S

// The edge sidebar: a right-edge overlay window shown while Ui.sidebar. It slides in over
// motion.base (no bounce); Escape or an outside click closes it. Content lives in
// SidebarBody; this file only places it.
PanelWindow {
    id: win

    readonly property bool wanted: Ui.sidebar
    readonly property int gap: Theme.space.m

    screen: {
        for (var i = 0; i < Quickshell.screens.length; i++)
            if (Quickshell.screens[i].name === Ui.screenName) return Quickshell.screens[i];
        return Quickshell.screens.length > 0 ? Quickshell.screens[0] : null;
    }
    anchors { top: true; right: true; bottom: true }
    // margins is real but Quickshell does not export it to qmllint
    // qmllint disable unqualified unresolved-type
    margins.top: Theme.bar.height + win.gap
    margins.bottom: win.gap
    margins.right: win.gap
    implicitWidth: body.panelWidth
    visible: wanted || body.x < body.panelWidth
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "qs-sidebar"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: wanted ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    mask: Region { item: body }

    DismissGrab {
        windows: [win]
        armed: win.wanted
        onDismissed: Ui.sidebar = false
    }

    SidebarBody {
        id: body
        height: parent.height
        x: win.wanted ? 0 : panelWidth
        focus: win.wanted
        onExpandRequested: function (tab) { Ui.toggleCc(S.ccTab(tab)) }
        onCloseRequested: Ui.sidebar = false
        Behavior on x {
            NumberAnimation {
                duration: Theme.motion.base
                easing.type: Theme.motion.easeOut
            }
        }
    }
}
