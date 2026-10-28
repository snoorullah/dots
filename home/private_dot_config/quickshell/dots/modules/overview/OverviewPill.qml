pragma ComponentBehavior: Bound
import QtQuick
import qs.modules.overview
import qs.modules.overview.parts
import "js/Fmt.js" as Fmt
import "js/Model.js" as Model

// The bar's overview module. Nominal = zero width AND zero height: no items, no
// focus, fresh data. Anything else enters from width 0 over motion.base and never
// recolours, pulses or loops. Amber = someone waits on me, red = failed and nobody
// waits, a hollow ? = the data layer is stale, a ring = a focus block is running.
// Left click asks for the card, right click for the panel. The keybind twin is
// `qs ipc call dots.overview toggle`, because a zero-width module has no click target.
Item {
    id: pill

    // Contract with the bar (T2 may bind these; the defaults read the state files).
    property int attnWaiting: Feed.waiting
    property int attnFailed: Feed.failed
    property bool stale: Feed.degraded
    property string screenName: ""
    signal cardRequested()
    signal panelRequested(string page)

    readonly property bool lampOn: Feed.lamp
    property real lastOnsetMs: 0
    property bool ready: false

    implicitWidth: row.implicitWidth
    implicitHeight: row.implicitWidth > 0 ? Look.chipHeight : 0
    visible: implicitWidth > 0      // a positioner must not reserve a chip gap for nothing
    objectName: "overviewPill"

    // Onset policy lives in Model.onset: at most one entry animation per 10 minutes.
    function enter(chip) {
        var o = Model.onset(lastOnsetMs, Date.now())
        lastOnsetMs = o.last
        if (o.fire && ready) chip.runEnter()
        else chip.reveal = 1
    }

    function publishAnchor() {
        var p = pill.mapToItem(null, pill.width / 2, pill.height)
        Feed.anchorScreen = pill.screenName
        Feed.anchorX = p.x
        Feed.anchorBottom = Look.barHeight
    }
    onXChanged: publishAnchor()
    onWidthChanged: publishAnchor()
    Component.onCompleted: { publishAnchor(); Qt.callLater(function () { pill.ready = true }) }

    component Chip: Item {
        id: c
        required property var owner
        property bool want: false
        property string label: ""
        property color tone: Look.fg
        property bool ring: false
        property bool mark: false
        property real reveal: 0
        readonly property real full: body.implicitWidth + ((ring || mark) ? 0 : Look.sL * 2)

        width: full * reveal
        height: Look.chipHeight
        visible: reveal > 0
        clip: true

        function runEnter() { reveal = 0; enterAnim.restart() }
        onWantChanged: {
            if (want) owner.enter(c)
            else { enterAnim.stop(); reveal = 0 }
        }
        Component.onCompleted: reveal = want ? 1 : 0

        NumberAnimation {
            id: enterAnim
            target: c
            property: "reveal"
            from: 0
            to: 1
            duration: Look.mBase
            easing.type: Look.easeIn
        }

        // chip wash: the tone at alpha.wash behind its own text. Dropped when stale.
        Rectangle {
            anchors.fill: parent
            radius: Look.rChip
            color: Look.wash(c.tone)
            visible: !c.ring && !c.mark && !Feed.dim
        }
        Row {
            id: body
            x: (c.ring || c.mark) ? 0 : Look.sL
            anchors.verticalCenter: parent.verticalCenter
            spacing: Look.sM
            Ring {
                visible: c.ring
                anchors.verticalCenter: parent.verticalCenter
                diameter: Look.ringDiameter
                elapsed: Feed.focusElapsed
                target: Feed.focusTarget
                dim: Feed.dim
            }
            StaleMark {
                visible: c.mark
                size: Look.iconSize
                anchors.verticalCenter: parent.verticalCenter
            }
            Txt {
                visible: !c.mark
                anchors.verticalCenter: parent.verticalCenter
                text: c.label
                role: "monoS"
                color: Feed.dim ? Look.fgFaint : Look.legible(c.tone)
                elide: Text.ElideNone
            }
        }
    }

    Row {
        id: row
        anchors.verticalCenter: parent.verticalCenter
        spacing: Look.sM

        Chip {
            id: focusChip
            objectName: "focusChip"
            owner: pill
            ring: true
            want: Feed.focusRunning || pill.lampOn
            tone: Look.fg
            label: Fmt.mmss(Math.max(0, Feed.focusTarget - Feed.focusElapsed))
        }
        Chip {
            id: failedChip
            objectName: "failedChip"
            owner: pill
            want: pill.attnFailed > 0 || pill.lampOn
            tone: Look.red
            label: Fmt.badge(Math.max(pill.attnFailed, pill.lampOn ? 1 : 0))
        }
        Chip {
            id: waitingChip
            objectName: "waitingChip"
            owner: pill
            want: pill.attnWaiting > 0 || pill.lampOn
            tone: Look.amber
            label: Fmt.badge(Math.max(pill.attnWaiting, pill.lampOn ? 1 : 0))
        }
        Chip {
            id: staleChip
            objectName: "staleChip"
            owner: pill
            mark: true
            want: pill.stale
        }
    }

    // Seconds tick only while a ring is on screen.
    Timer {
        running: focusChip.visible && Feed.focusRunning
        interval: 1000
        repeat: true
        onTriggered: Feed.bump()
    }

    MouseArea {
        anchors.fill: parent
        enabled: pill.width > 0
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: function (e) {
            pill.publishAnchor()
            if (e.button === Qt.RightButton) pill.panelRequested("today")
            else pill.cardRequested()
        }
        // hover lifts, never recolours
        Rectangle {
            anchors.fill: parent
            radius: Look.rChip
            color: Look.withAlpha(Look.fg, Look.aHover)
            visible: parent.containsMouse
            z: -1
        }
    }
}
