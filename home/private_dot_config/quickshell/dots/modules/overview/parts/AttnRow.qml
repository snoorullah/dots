pragma ComponentBehavior: Bound
import QtQuick
import qs.modules.overview
import "../js/Fmt.js" as Fmt

// One attention item. Amber wash on the status chip when someone waits on me, red
// when it failed and nobody waits; everything else is neutral. The row is a button
// that opens the Item page; "Break down & start" only appears when T1 says it can.
Item {
    id: r
    property var item: ({})
    property bool dim: false
    property bool showBreakdown: true
    signal openRequested(var item)

    readonly property bool failed: item.kind === "alert" && !item.waiting
    readonly property color tone: item.waiting ? Look.amber : (failed ? Look.red : Look.fgDim)
    readonly property bool flagged: !!item.waiting || failed
    readonly property var icons: ({ blocker: "block", review: "rate_review", alert: "error",
                                    dm: "chat", task: "task_alt", erp: "receipt_long" })
    readonly property string metaText: [item.ref, item.actor, Fmt.age(item.ageSec)]
        .filter(function (s) { return s !== undefined && s !== null && String(s) !== "" }).join("  ")
    readonly property bool hasButton: showBreakdown && !!item.canBreakdown

    implicitWidth: 300
    objectName: "attnRow"

    Rectangle {
        anchors.fill: parent
        radius: Look.rChip
        color: Look.withAlpha(Look.fg, Look.aHover)
        visible: ma.containsMouse
    }
    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: r.openRequested(r.item)
    }

    Glyph {
        id: ic
        x: Look.sS
        y: Look.sM + 1
        name: r.icons[r.item.kind] || "circle"
        dim: r.dim
    }
    Column {
        id: col
        anchors.left: ic.right
        anchors.leftMargin: Look.sL
        anchors.right: parent.right
        anchors.rightMargin: Look.sS
        anchors.top: parent.top
        anchors.topMargin: Look.sM
        spacing: Look.sS

        Txt {
            width: parent.width
            text: Fmt.clip(r.item.title, 120)
            maximumLineCount: 2
            wrapMode: Text.Wrap
            elide: Text.ElideRight
            dim: r.dim
        }
        Row {
            spacing: Look.sM
            // chip wash: tone at alpha.wash behind tone text, only when it needs me
            Rectangle {
                visible: r.flagged
                height: chipTxt.implicitHeight + 2
                width: chipTxt.implicitWidth + Look.sL * 2
                radius: Look.rChip
                color: r.dim ? "transparent" : Look.wash(r.tone)
                Txt {
                    id: chipTxt
                    anchors.centerIn: parent
                    text: r.item.waiting ? "waiting" : "failed"
                    role: "caption"
                    color: r.dim ? Look.fgFaint : Look.legible(r.tone)
                    elide: Text.ElideNone
                }
            }
            Txt {
                text: r.metaText
                role: "caption"
                faint: true
                dim: r.dim
                anchors.verticalCenter: parent.verticalCenter
            }
        }
        Button {
            visible: r.hasButton
            objectName: "breakdownButton"
            text: "Break down & start"
            icon: "play_arrow"
            dim: r.dim
            onClicked: Actions.breakdown(r.item)
        }
    }
    implicitHeight: col.implicitHeight + Look.sM * 2
}
