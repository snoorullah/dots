import QtQuick
import qs.modules.overview
import qs.modules.overview.parts
import "../js/Fmt.js" as Fmt

// Focus timer. T3 does not own the clock: Start/Stop/Break exec dots-overview and
// the state comes back through now.json. The ring is the only moving thing, and it
// moves once a second, only while this page is visible and a block is running.
FocusScope {
    id: pg
    readonly property bool dim: Feed.dim
    readonly property string st: Feed.focus ? Feed.focus.state : "idle"
    readonly property real remaining: Math.max(0, Feed.focusTarget - Feed.focusElapsed)
    objectName: "focusPage"

    Column {
        anchors.centerIn: parent
        spacing: Look.sXxl

        Ring {
            id: ring
            anchors.horizontalCenter: parent.horizontalCenter
            diameter: 180
            elapsed: Feed.focusElapsed
            target: Feed.focusTarget
            dim: pg.dim
            Txt {
                anchors.centerIn: parent
                text: pg.st === "idle" ? "--:--" : Fmt.mmss(pg.remaining)
                role: "display"
                font.family: Look.mono
                dim: pg.dim || pg.st === "idle"
                elide: Text.ElideNone
            }
        }
        Txt {
            anchors.horizontalCenter: parent.horizontalCenter
            text: pg.st === "running" ? "focus" : (pg.st === "break" ? "break" : "idle")
            role: "title"
            dim: pg.dim
        }
        Txt {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: Feed.focusZone !== ""
            text: Feed.focusZone
            role: "bodyS"
            faint: true
            dim: pg.dim
        }
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Look.sL
            Button {
                objectName: "focusStart"
                visible: pg.st !== "running"
                primary: true
                text: "Start"
                icon: "play_arrow"
                dim: pg.dim
                onClicked: Actions.focus("start")
            }
            Button {
                objectName: "focusStop"
                visible: pg.st !== "idle"
                text: "Stop"
                icon: "stop"
                dim: pg.dim
                onClicked: Actions.focus("stop")
            }
            Button {
                objectName: "focusBreak"
                visible: pg.st === "running"
                text: "Break"
                icon: "coffee"
                dim: pg.dim
                onClicked: Actions.focus("break")
            }
        }
    }

    Timer {
        running: pg.visible && pg.st !== "idle"
        interval: 1000
        repeat: true
        onTriggered: Feed.bump()
    }
}
