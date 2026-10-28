pragma ComponentBehavior: Bound
import QtQuick
import qs.modules.overview
import qs.modules.overview.parts

// The full panel: 920x640, padding 24, a nav column and the page, gap 12. Pages are
// loaded one at a time and freed when you leave them. Pure Item (no window).
Item {
    id: panel
    property string page: "today"        // today | week | attention | focus | heatmap | item
    property bool shown: false
    property bool animate: true
    signal closeRequested()

    readonly property var pages: [
        { id: "today",     label: "Today",     icon: "today" },
        { id: "week",      label: "Week",      icon: "date_range" },
        { id: "attention", label: "Attention", icon: "notifications" },
        { id: "focus",     label: "Focus",     icon: "timer" },
        { id: "heatmap",   label: "Heatmap",   icon: "grid_view" }
    ]
    readonly property var files: ({ today: "Today", week: "Week", attention: "Attention",
                                    focus: "Focus", heatmap: "Heatmap", item: "Item" })

    width: Look.panelWidth
    height: Look.panelHeight
    objectName: "overviewPanel"

    // enter 240 OutExpo (the only slow surface), exit 120 OutCubic
    property real prog: shown ? 1 : 0
    Behavior on prog {
        enabled: panel.animate
        NumberAnimation {
            duration: panel.shown ? Look.mSlow : Look.mFast
            easing.type: panel.shown ? Look.easeIn : Look.easeOut
        }
    }
    opacity: prog
    scale: 0.92 + 0.08 * prog

    focus: true
    Keys.onEscapePressed: panel.closeRequested()

    Connections {
        target: Feed
        function onItemRequestsChanged() { panel.page = "item" }
    }

    Rectangle {
        anchors.fill: parent
        radius: Look.rPanel
        color: Look.withAlpha(Look.surface, Look.aPanel)
        border.width: 1
        border.color: Look.withAlpha(Look.outline, Look.aDivider)
    }

    Row {
        anchors.fill: parent
        anchors.margins: Look.sXxxl
        spacing: Look.sXl

        Column {
            id: nav
            width: 148
            spacing: Look.sS
            Repeater {
                model: panel.pages
                delegate: Item {
                    id: navItem
                    required property var modelData
                    readonly property bool on: panel.page === modelData.id
                    width: nav.width
                    height: 32
                    Rectangle {
                        anchors.fill: parent
                        radius: Look.rChip
                        color: Look.withAlpha(Look.fg, navItem.on ? Look.aHover * 1.5 : (ma.containsMouse ? Look.aHover : 0))
                    }
                    Glyph { x: Look.sL; anchors.verticalCenter: parent.verticalCenter; name: navItem.modelData.icon; dim: Feed.dim }
                    Txt {
                        x: Look.sL * 2 + Look.sXxl
                        anchors.verticalCenter: parent.verticalCenter
                        text: navItem.modelData.label
                        role: "body"
                        font.weight: navItem.on ? Font.DemiBold : Font.Normal
                        dim: Feed.dim
                    }
                    // attention counts ride on the nav row, in the same two accents
                    Row {
                        visible: navItem.modelData.id === "attention"
                        anchors.right: parent.right
                        anchors.rightMargin: Look.sL
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Look.sM
                        Txt {
                            visible: Feed.failed > 0
                            text: Feed.failed
                            role: "monoS"
                            color: Feed.dim ? Look.fgFaint : Look.legible(Look.red)
                            elide: Text.ElideNone
                        }
                        Txt {
                            visible: Feed.waiting > 0
                            text: Feed.waiting
                            role: "monoS"
                            color: Feed.dim ? Look.fgFaint : Look.legible(Look.amber)
                            elide: Text.ElideNone
                        }
                    }
                    MouseArea {
                        id: ma
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: panel.page = navItem.modelData.id
                    }
                }
            }
        }

        Rectangle {
            width: 1
            height: parent.height
            color: Look.withAlpha(Look.outline, Look.aDivider)
        }

        Loader {
            id: pageLoader
            width: parent.width - nav.width - 1 - Look.sXl * 2
            height: parent.height
            // Freed on every page change: only the visible page exists.
            source: "pages/" + (panel.files[panel.page] || "Today") + ".qml"
        }
    }
}
