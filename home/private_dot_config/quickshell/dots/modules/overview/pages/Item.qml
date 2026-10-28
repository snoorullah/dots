import QtQuick
import qs.modules.overview
import qs.modules.overview.parts
import "../js/Fmt.js" as Fmt

// One attention item in full. The item is looked up by Feed.selectedId so the page
// keeps working when the files change underneath it (and says so when it is gone).
FocusScope {
    id: pg
    readonly property var it: Feed.itemById(Feed.selectedId)
    readonly property bool dim: Feed.dim

    Column {
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Look.sXl

        Txt { text: pg.it ? pg.it.title : "This item is gone"; role: "headline"; wrapMode: Text.Wrap; width: parent.width; maximumLineCount: 3; dim: pg.dim || !pg.it }
        Column {
            visible: !!pg.it
            width: Math.min(parent.width, 420)   // label and value stay within one glance
            spacing: Look.sS
            StatRow { width: parent.width; label: "Ref"; value: pg.it && pg.it.ref ? pg.it.ref : "-"; valueRole: "monoS"; dim: pg.dim }
            StatRow { width: parent.width; label: "Source"; value: pg.it && pg.it.src ? pg.it.src : "-"; valueRole: "monoS"; dim: pg.dim }
            StatRow { width: parent.width; label: "Kind"; value: pg.it ? pg.it.kind : "-"; valueRole: "monoS"; dim: pg.dim }
            StatRow { width: parent.width; label: "Urgency"; value: pg.it ? pg.it.urgency : "-"; valueRole: "monoS"; dim: pg.dim }
            StatRow { width: parent.width; label: "From"; value: pg.it && pg.it.actor ? pg.it.actor : "-"; valueRole: "monoS"; dim: pg.dim }
            StatRow { width: parent.width; label: "Age"; value: pg.it ? Fmt.age(pg.it.ageSec) : "-"; valueRole: "monoS"; dim: pg.dim }
            StatRow { width: parent.width; label: "Feed"; value: pg.it ? (pg.it.waiting ? "waiting on you" : (pg.it.kind === "alert" ? "failed" : "open")) : "-"; valueRole: "monoS"; dim: pg.dim }
        }
        Row {
            spacing: Look.sL
            visible: !!pg.it
            Button {
                objectName: "itemJump"
                visible: !!pg.it && (!!pg.it.jump || !!pg.it.url)
                text: "Jump"
                icon: "open_in_new"
                dim: pg.dim
                onClicked: Actions.jump(pg.it)
            }
            Button {
                objectName: "itemBreakdown"
                visible: !!pg.it && !!pg.it.canBreakdown
                text: "Break down & start"
                icon: "play_arrow"
                dim: pg.dim
                onClicked: Actions.breakdown(pg.it)
            }
        }
    }
}
