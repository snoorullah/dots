import QtQuick
import qs.modules.theme
import qs.modules.common

// Logo, NOW caption, the task in focus, the next one. The gear opens the system slot.
Item {
    id: h

    property string title: ""
    property string next: ""
    property bool stale: false
    property bool systemOpen: false
    signal systemToggled()

    implicitHeight: col.implicitHeight + Theme.space.xxl * 2
    objectName: "sideHeader"

    Column {
        id: col
        x: Theme.space.xxl
        y: Theme.space.xxl
        width: parent.width - Theme.space.xxl * 2
        spacing: 0

        Item {
            width: parent.width
            height: 24 + Theme.space.m + 2
            Icon {
                name: "moon-stars"
                size: 24
                color: Theme.color.accent
            }
            StatusMark {
                objectName: "staleMark"
                visible: h.stale
                level: "unknown"
                size: 16
                anchors.right: gear.left
                anchors.rightMargin: Theme.space.m
                y: 4
            }
            SideButton {
                id: gear
                objectName: "systemToggle"
                anchors.right: parent.right
                y: -2
                width: 28
                hpad: 6
                icon: "gear"
                variant: h.systemOpen ? "tab" : "outline"
                selected: h.systemOpen
                tip: "System"
                Accessible.name: "System"
                onClicked: h.systemToggled()
            }
        }
        Text {
            text: "NOW"
            color: Theme.color.fgDim
            font.family: Theme.font.mono
            font.pixelSize: Theme.font.size.caption
            font.weight: Theme.font.weight.label
            font.letterSpacing: Theme.font.size.caption * Theme.font.track.label
            lineHeightMode: Text.FixedHeight
            lineHeight: Theme.font.line.caption
            renderType: Text.NativeRendering
        }
        DText {
            objectName: "nowTitle"
            width: parent.width
            text: h.title !== "" ? h.title : "Nothing in focus"
            role: "title"
            elide: Text.ElideRight
            maximumLineCount: 1
            color: h.title !== "" ? Theme.color.fg : Theme.color.fgDim
        }
        DText {
            objectName: "nextLine"
            visible: h.next !== ""
            width: parent.width
            text: "next: " + h.next
            role: "bodyS"
            dim: true
            elide: Text.ElideRight
            maximumLineCount: 1
        }
    }
    Rectangle {
        anchors.bottom: parent.bottom
        width: parent.width
        height: 1
        color: Theme.color.outlineVariant
    }
}
