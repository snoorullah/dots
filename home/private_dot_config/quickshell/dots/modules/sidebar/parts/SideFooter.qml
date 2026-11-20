import QtQuick
import qs.modules.theme
import qs.modules.common

// The selected item's title and its five actions. Reply, Agent, Queue and Snooze would write
// to a remote service or to state nobody reads yet, so they render disabled. Expand is local.
Rectangle {
    id: f

    property string title: "Pick an item"
    property bool hasSelection: false
    signal expand()

    readonly property string readOnly: "read-only for now"

    implicitHeight: col.implicitHeight + Theme.space.xl * 2
    color: Qt.alpha(Theme.color.surface, 0.6)
    objectName: "sideFooter"

    Rectangle {
        width: parent.width
        height: 1
        color: Theme.color.outlineVariant
    }
    Column {
        id: col
        x: Theme.space.xl
        y: Theme.space.xl
        width: parent.width - Theme.space.xl * 2
        spacing: Theme.space.m
        DText {
            objectName: "footTitle"
            width: parent.width
            text: f.title
            role: "bodyS"
            font.weight: Font.Medium
            elide: Text.ElideRight
            maximumLineCount: 1
            color: f.hasSelection ? Theme.color.fg : Theme.color.fgDim
        }
        Flow {
            width: parent.width
            spacing: 6
            SideButton { objectName: "actReply"; text: "Reply"; icon: "arrow-bend-up-left"; variant: "primary"; enabled: false; tip: f.readOnly }
            SideButton { objectName: "actAgent"; text: "Agent"; icon: "paper-plane-tilt"; enabled: false; tip: f.readOnly }
            SideButton { objectName: "actQueue"; text: "Queue"; icon: "list-plus"; enabled: false; tip: f.readOnly }
            SideButton { objectName: "actSnooze"; text: "Snooze"; icon: "alarm"; enabled: false; tip: f.readOnly }
            SideButton { objectName: "actExpand"; text: "Expand"; icon: "arrows-out-simple"; onClicked: f.expand() }
        }
    }
}
