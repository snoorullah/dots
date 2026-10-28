pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.modules.overview
import "../common" as Common

// Instantiated once in the shell root. Owns the two overview windows and the
// `dots.overview` IPC target. Both windows are created only while open (LazyLoader)
// and freed shortly after close, so an idle shell holds neither.
Item {
    id: host

    // Where the card hangs from. Set by the pill (through Feed) at click time;
    // T2 may also set them directly.
    property string anchorScreen: Feed.anchorScreen
    property real anchorX: Feed.anchorX
    property real anchorBottom: Feed.anchorBottom

    property bool cardOpen: false
    property bool cardShown: false
    property bool panelOpen: false
    property bool panelShown: false
    property string panelPage: "today"

    readonly property var screenObj: {
        var list = Quickshell.screens
        for (var i = 0; i < list.length; i++) if (list[i].name === anchorScreen) return list[i]
        return list.length > 0 ? list[0] : null
    }

    function toggleCard() {
        if (cardOpen && cardShown) { close(); return }
        closePanel()
        cardOpen = true
        cardShown = true
    }

    function openPanel(page) {
        var p = page || "today"
        closeCard()
        panelPage = p
        panelOpen = true
        panelShown = true
    }

    function close() { closeCard(); closePanel() }

    function lamp(ms) { Feed.lampFor(ms) }

    function closeCard() {
        if (!cardOpen) return
        cardShown = false
        cardFree.restart()
    }
    function closePanel() {
        if (!panelOpen) return
        panelShown = false
        panelFree.restart()
    }

    // free the windows once the exit animation (120 ms) has played
    Timer { id: cardFree; interval: Look.mFast + 40; onTriggered: if (!host.cardShown) host.cardOpen = false }
    Timer { id: panelFree; interval: Look.mFast + 40; onTriggered: if (!host.panelShown) host.panelOpen = false }

    IpcHandler {
        target: "dots.overview"
        function toggle(): void { host.toggleCard() }
        function panel(page: string): void { host.openPanel(page) }
        function focus(action: string): void { Actions.focus(action) }
    }

    LazyLoader {
        active: host.cardOpen

        PanelWindow {
            id: cw
            screen: host.screenObj
            color: "transparent"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "qs-overview"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
            exclusionMode: ExclusionMode.Ignore
            anchors { top: true; left: true }

            readonly property real screenW: screen ? screen.width : 1920
            readonly property real leftMargin: Math.max(8, Math.min(host.anchorX - Look.cardWidth / 2, screenW - Look.cardWidth - 8))

            margins { top: Math.round(host.anchorBottom); left: Math.round(cw.leftMargin) }
            implicitWidth: Look.cardWidth
            implicitHeight: card.height
            mask: Region { item: card }

            Common.DismissGrab {
                windows: [cw]
                armed: host.cardOpen && host.cardShown
                onDismissed: host.close()
            }

            OverviewCard {
                id: card
                notchX: host.anchorX - cw.leftMargin
                shown: host.cardShown
                onCloseRequested: host.close()
                onPanelRequested: function (page) { host.openPanel(page) }
            }
        }
    }

    LazyLoader {
        active: host.panelOpen

        PanelWindow {
            id: pw
            screen: host.screenObj
            color: "transparent"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "qs-overview"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
            exclusionMode: ExclusionMode.Ignore
            implicitWidth: Look.panelWidth
            implicitHeight: Look.panelHeight

            Common.DismissGrab {
                windows: [pw]
                armed: host.panelOpen && host.panelShown
                onDismissed: host.close()
            }

            OverviewPanel {
                page: host.panelPage
                shown: host.panelShown
                onCloseRequested: host.close()
            }
        }
    }
}
