pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Shapes
import qs.modules.overview
import qs.modules.overview.parts
import "js/Fmt.js" as Fmt

// The dropdown under the pill: 380 wide, at most 520 tall, padding 16, radius 16,
// with an 8x4 notch whose centre is notchX. Pure Item (no window), so the host wraps
// it in a layer-shell window and the tests can render it directly.
Item {
    id: card

    property real notchX: width / 2
    property bool shown: false           // host flips this true after creation, false to close
    property bool animate: true          // tests switch it off so frames are settled
    signal closeRequested()
    signal panelRequested(string page)

    readonly property real p: shown ? 1 : 0
    readonly property bool dim: Feed.dim
    readonly property int pad: Look.sXxl
    readonly property var nextRows: Feed.nextItems.slice(0, 3)
    readonly property var attnRows: Feed.attentionItems.slice(0, 5)
    readonly property int moreCount: Math.max(0, Feed.attentionItems.length - 5)
    readonly property bool nothing: !Feed.task && nextRows.length === 0 && attnRows.length === 0

    width: Look.cardWidth
    height: Look.notchH + wrap.height
    objectName: "overviewCard"

    // open/close: scale 0.92 -> 1 and opacity, transform origin at the notch
    property real prog: shown ? 1 : 0
    Behavior on prog {
        enabled: card.animate
        NumberAnimation {
            duration: card.shown ? Look.mBase : Look.mFast
            easing.type: card.shown ? Look.easeIn : Look.easeOut
        }
    }
    opacity: prog
    transform: Scale {
        origin.x: card.notchX
        origin.y: 0
        xScale: 0.92 + 0.08 * card.prog
        yScale: 0.92 + 0.08 * card.prog
    }

    focus: true
    Keys.onEscapePressed: card.closeRequested()

    // notch: apex up, sitting on the card's top edge
    Shape {
        id: notch
        objectName: "notch"
        x: card.notchX - Look.notchW / 2
        y: 0
        width: Look.notchW
        height: Look.notchH
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            fillColor: Look.withAlpha(Look.surface, Look.aPanel)
            strokeColor: "transparent"
            strokeWidth: 0
            startX: 0; startY: Look.notchH
            PathLine { x: Look.notchW / 2; y: 0 }
            PathLine { x: Look.notchW; y: Look.notchH }
            PathLine { x: 0; y: Look.notchH }
        }
    }

    Rectangle {
        id: wrap
        objectName: "cardWrap"
        y: Look.notchH
        width: parent.width
        height: Math.min(Look.cardMaxHeight, body.implicitHeight + foot.height + Look.sXl + card.pad * 2)
        radius: Look.rCard
        color: Look.withAlpha(Look.surface, Look.aPanel)
        border.width: 1
        border.color: Look.withAlpha(Look.outline, Look.aDivider)

        Flickable {
            id: scroller
            objectName: "cardScroll"
            x: card.pad
            y: card.pad
            width: parent.width - card.pad * 2
            height: parent.height - card.pad * 2 - foot.height - Look.sXl
            contentWidth: width
            contentHeight: body.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            interactive: contentHeight > height

            Column {
                id: body
                width: parent.width
                spacing: Look.sXl

                // today: the three texts share one baseline (Lato, JetBrains Mono and the
                // caption have different metrics, so centring boxes would stagger them)
                Item {
                    width: parent.width
                    height: Math.max(hd.implicitHeight, worked.implicitHeight)
                    Txt {
                        id: worked
                        objectName: "workedToday"
                        anchors.right: doneTxt.visible ? doneTxt.left : parent.right
                        anchors.rightMargin: doneTxt.visible ? Look.sL : 0
                        anchors.verticalCenter: parent.verticalCenter
                        text: Fmt.hm(Feed.today ? Feed.today.workedSec : 0)
                        role: "title"
                        dim: card.dim
                        elide: Text.ElideNone
                        font.family: Look.mono
                    }
                    Txt {
                        id: doneTxt
                        visible: !!Feed.today && Feed.today.tasksDone > 0
                        anchors.right: parent.right
                        anchors.baseline: worked.baseline
                        text: (Feed.today ? Feed.today.tasksDone : 0) + " done"
                        role: "caption"
                        faint: true
                        dim: card.dim
                        elide: Text.ElideNone
                    }
                    Txt {
                        id: hd
                        text: "Today"
                        role: "title"
                        dim: card.dim
                        anchors.left: parent.left
                        anchors.baseline: worked.baseline
                    }
                    StaleMark {
                        visible: card.dim
                        anchors.left: hd.right
                        anchors.leftMargin: Look.sL
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                // current task
                Column {
                    width: parent.width
                    spacing: Look.sS
                    visible: !!Feed.task
                    Txt { text: "Now"; role: "caption"; faint: true; dim: card.dim }
                    Txt {
                        objectName: "taskTitle"
                        width: parent.width
                        text: Feed.task ? Fmt.clip(Feed.task.desc, 120) : ""
                        wrapMode: Text.Wrap
                        maximumLineCount: 2
                        dim: card.dim
                    }
                    Txt {
                        width: parent.width
                        text: Feed.task ? [Feed.task.ref, Feed.task.project].filter(function (s) { return !!s }).join("  ") : ""
                        role: "caption"
                        faint: true
                        dim: card.dim
                    }
                }

                // next up
                Column {
                    width: parent.width
                    spacing: Look.sS
                    visible: card.nextRows.length > 0
                    Txt { text: "Next up"; role: "caption"; faint: true; dim: card.dim }
                    Repeater {
                        model: card.nextRows
                        delegate: AttnRow {
                            required property var modelData
                            width: parent.width
                            item: modelData
                            dim: card.dim
                            onOpenRequested: function (it) { Feed.selectedId = it.id; card.panelRequested("item") }
                        }
                    }
                }

                // attention
                Column {
                    width: parent.width
                    spacing: Look.sS
                    visible: card.attnRows.length > 0
                    Txt { text: "Needs you"; role: "caption"; faint: true; dim: card.dim }
                    Repeater {
                        model: card.attnRows
                        delegate: AttnRow {
                            required property var modelData
                            width: parent.width
                            item: modelData
                            dim: card.dim
                            onOpenRequested: function (it) { Feed.selectedId = it.id; card.panelRequested("item") }
                        }
                    }
                    Button {
                        visible: card.moreCount > 0
                        text: "+" + card.moreCount + " more"
                        dim: card.dim
                        onClicked: card.panelRequested("attention")
                    }
                }

                Empty { visible: card.nothing }
            }
        }

        // Bottom fade: only while there is more below the fold.
        Rectangle {
            id: fade
            objectName: "cardFade"
            x: scroller.x
            y: scroller.y + scroller.height - height
            width: scroller.width
            height: Look.sXxxl
            visible: scroller.contentHeight > scroller.height + 1 && !scroller.atYEnd
            gradient: Gradient {
                GradientStop { position: 0; color: Look.withAlpha(Look.surface, 0) }
                GradientStop { position: 1; color: Look.surface }
            }
        }

        // Footer is pinned outside the Flickable: always on screen, whatever scrolls.
        Row {
            id: foot
            objectName: "cardFooter"
            x: card.pad
            y: parent.height - card.pad - height
            spacing: Look.sL
            Button {
                objectName: "openPanel"
                text: "Open panel"
                icon: "open_in_full"
                dim: card.dim
                onClicked: card.panelRequested("today")
            }
            Button {
                objectName: "focusToggle"
                text: Feed.focusRunning ? "Stop focus" : "Start focus"
                icon: Feed.focusRunning ? "stop" : "timer"
                dim: card.dim
                onClicked: Actions.focus(Feed.focusRunning ? "stop" : "start")
            }
        }
    }
}
