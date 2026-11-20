import QtQuick
import qs.modules.theme
import qs.modules.common
import "../js/SideModel.js" as S

// One compact queue row. Grid: age 44 | mark 14 | text. Amber circle waiting, red diamond
// failed, nothing otherwise. The row is a button: click selects, double click jumps.
Item {
    id: r

    property var item: ({})
    property bool selected: false
    property bool dim: false
    property bool animate: true
    signal picked()
    signal jumped()

    readonly property string markKind: S.mark(item)
    readonly property color tone: dim ? Theme.color.fgFaint
        : (markKind === "waiting" ? Theme.color.waiting
        : (markKind === "failed" ? Theme.color.failed : Theme.color.fgDim))
    readonly property var srcIcons: ({ github: "git-pull-request", slack: "chat-circle", erp: "ticket",
                                      mail: "envelope", agent: "sparkle", you: "note-pencil", alert: "bell-ringing" })
    readonly property string srcName: S.srcLabel(item)
    readonly property string whoText: S.who(item)

    implicitHeight: 52
    objectName: "sideRow"
    Accessible.role: Accessible.Button
    Accessible.name: item.title || ""

    opacity: 1
    Component.onCompleted: {
        if (!animate) return;
        opacity = 0;
        fadeIn.start();
    }
    NumberAnimation on opacity {
        id: fadeIn
        running: false
        to: 1
        duration: Theme.motion.fade
        easing.type: Theme.motion.easeOut
    }

    Rectangle {
        anchors.fill: parent
        radius: Theme.radius.row
        color: r.selected ? Theme.color.surfaceContainer : Qt.alpha(Theme.color.fg, Theme.alpha.hover)
        visible: r.selected || ma.containsMouse
    }

    Text {
        id: age
        objectName: "rowAge"
        x: Theme.space.m
        width: 44
        anchors.verticalCenter: parent.verticalCenter
        horizontalAlignment: Text.AlignRight
        text: S.age(r.item)
        color: r.tone
        font.family: Theme.font.mono
        font.pixelSize: Theme.font.size.caption
        renderType: Text.NativeRendering
    }
    Item {
        id: markBox
        objectName: "rowMark"
        x: age.x + age.width + 6
        width: 14
        height: 14
        anchors.verticalCenter: parent.verticalCenter
        Icon {
            anchors.fill: parent
            visible: r.markKind !== ""
            size: 14
            name: r.markKind === "failed" ? "diamond" : "circle"
            active: true
            color: r.tone
        }
    }
    Column {
        id: col
        objectName: "rowText"
        x: markBox.x + markBox.width + 6
        width: parent.width - x - Theme.space.m
        anchors.verticalCenter: parent.verticalCenter
        DText {
            objectName: "rowTitle"
            width: parent.width
            text: r.item.title || ""
            role: "bodyS"
            font.weight: Font.Medium
            elide: Text.ElideRight
            maximumLineCount: 1
            color: r.dim ? Theme.color.fgFaint : Theme.color.fg
        }
        Row {
            id: sub
            objectName: "rowSub"
            width: parent.width
            height: 16
            spacing: 0
            clip: true
            DText {
                text: r.whoText + (r.whoText !== "" && r.srcName !== "" ? " · " : "")
                visible: text !== ""
                role: "caption"
                font.capitalization: Font.MixedCase
                font.letterSpacing: 0
                font.weight: Font.Normal
                dim: true
                color: r.dim ? Theme.color.fgFaint : Theme.color.fgDim
            }
            Icon {
                visible: S.srcKey(r.item) !== ""
                name: r.srcIcons[S.srcKey(r.item)] || ""
                size: 12
                color: r.dim ? Theme.color.fgFaint : Theme.color.fgDim
                anchors.verticalCenter: parent.verticalCenter
            }
            Item { width: 3; height: 1; visible: r.srcName !== "" }
            Text {
                text: r.srcName
                visible: text !== ""
                color: r.dim ? Theme.color.fgFaint : Theme.color.fgDim
                font.family: Theme.font.mono
                font.pixelSize: Theme.font.size.caption
                lineHeightMode: Text.FixedHeight
                lineHeight: Theme.font.line.caption
                renderType: Text.NativeRendering
            }
        }
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: r.picked()
        onDoubleClicked: r.jumped()
    }
}
