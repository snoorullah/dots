pragma ComponentBehavior: Bound
import QtQuick
import qs.modules.theme
import "../js/SideModel.js" as S

// Queue | Inbox | Agents | Work | Time. One selected.
Item {
    id: t
    property string current: "queue"
    signal picked(string key)

    readonly property var icons: ({ queue: "stack", inbox: "tray", agents: "sparkle", work: "briefcase", time: "clock" })

    implicitHeight: 28 + Theme.space.m * 2
    objectName: "sideTabs"

    Row {
        x: Theme.space.xl
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.space.s
        Repeater {
            model: S.TABS
            SideButton {
                required property var modelData
                text: modelData.label
                icon: t.icons[modelData.key]
                variant: "tab"
                selected: t.current === modelData.key
                objectName: "tab-" + modelData.key
                onClicked: t.picked(modelData.key)
            }
        }
    }
    Rectangle {
        anchors.bottom: parent.bottom
        width: parent.width
        height: 1
        color: Theme.color.outlineVariant
    }
}
