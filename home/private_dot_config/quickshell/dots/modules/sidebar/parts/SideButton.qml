import QtQuick
import QtQuick.Controls
import qs.modules.theme
import qs.modules.common

// One button for the sidebar: `primary` (accent fill), `outline` (raised, hairline border)
// or `tab` (flat; raised when `selected`). A button whose real action would write to a remote
// service is built with enabled: false and tip "read-only for now".
Rectangle {
    id: b

    property string text: ""
    property string icon: ""
    property string variant: "outline"   // primary | outline | tab
    property bool selected: false
    property string tip: ""
    property int hpad: variant === "tab" ? 8 : 10
    signal clicked()

    readonly property bool primary: variant === "primary"
    readonly property bool tab: variant === "tab"
    readonly property color ink: primary ? Theme.color.accentFg
        : (tab && !selected ? Theme.color.fgDim : Theme.color.fg)

    implicitHeight: 28
    implicitWidth: row.implicitWidth + hpad * 2
    radius: Theme.radius.row - 2
    color: primary ? Theme.color.accent
        : (tab ? (selected ? Theme.color.surfaceContainer : "transparent") : Theme.color.surfaceContainer)
    border.width: variant === "outline" ? 1 : 0
    border.color: Theme.color.outlineVariant
    opacity: enabled ? 1 : 0.45
    objectName: "sideButton"
    Accessible.role: Accessible.Button
    Accessible.name: text

    Rectangle {
        anchors.fill: parent
        radius: parent.radius
        color: Qt.alpha(Theme.color.fg, ma.pressed ? Theme.alpha.pressed : Theme.alpha.hover)
        visible: b.enabled && (ma.containsMouse || ma.pressed) && !b.selected
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 6
        Icon {
            visible: b.icon !== ""
            name: b.icon
            size: 16
            color: b.ink
            anchors.verticalCenter: parent.verticalCenter
        }
        DText {
            text: b.text
            role: "bodyS"
            color: b.ink
            font.weight: b.primary ? Font.DemiBold : Font.Normal
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: b.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: if (b.enabled) b.clicked()
    }
    ToolTip.visible: ma.containsMouse && b.tip !== ""
    ToolTip.text: b.tip
    ToolTip.delay: 400
}
