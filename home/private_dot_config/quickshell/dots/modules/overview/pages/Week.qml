pragma ComponentBehavior: Bound
import QtQuick
import qs.modules.overview
import qs.modules.overview.parts
import "../js/Fmt.js" as Fmt
import "../js/Ledger.js" as Ledger

// Week: the last seven days as a strip, then week / month / quarter totals.
// Month and quarter are totals here, not pages of their own.
FocusScope {
    id: pg
    readonly property var buckets: (Feed.actDoc && Feed.actDoc.buckets) ? Feed.actDoc.buckets : ({})
    readonly property var wk: buckets.week || null
    readonly property bool dim: Feed.dim
    readonly property var days: Feed.heatDoc ? Feed.heatDoc.days : []
    readonly property string endKey: days.length > 0 ? days[days.length - 1].d : ""
    readonly property var strip: endKey !== "" ? Ledger.lastN(days, 7, endKey) : []

    function asBars(list, key) {
        return (list || []).map(function (r) { return { name: r[key], sec: r.sec } })
    }

    Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: col.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: col
            width: parent.width
            spacing: Look.sXl

            // the caption shares the display number's baseline (different faces and sizes)
            Item {
                width: parent.width
                height: big.implicitHeight
                Txt { id: big; text: Fmt.hm(pg.wk ? pg.wk.workedSec : 0); role: "display"; font.family: Look.mono; dim: pg.dim; elide: Text.ElideNone }
                Txt {
                    id: cap
                    anchors.left: big.right
                    anchors.leftMargin: Look.sL
                    anchors.baseline: big.baseline
                    text: "this week"; role: "bodyS"; faint: true; dim: pg.dim
                }
                StaleMark { visible: pg.dim; anchors.left: cap.right; anchors.leftMargin: Look.sL; anchors.verticalCenter: parent.verticalCenter }
            }
            Sparkline {
                width: parent.width
                visible: pg.strip.length > 0
                values: pg.strip.map(function (e) { return e.workedSec })
                dim: pg.dim
            }
            Row {
                width: parent.width
                visible: pg.strip.length > 0
                Repeater {
                    model: pg.strip
                    delegate: Txt {
                        required property var modelData
                        width: col.width / pg.strip.length
                        text: Fmt.dayLabel(modelData.d).split(" ")[0]
                        role: "caption"
                        faint: true
                        dim: pg.dim
                        horizontalAlignment: Text.AlignHCenter
                    }
                }
            }

            Column {
                width: parent.width
                spacing: Look.sS
                StatRow { width: parent.width; label: "Week"; value: Fmt.hm(pg.wk ? pg.wk.workedSec : 0) + "  " + (pg.wk ? pg.wk.tasksDone : 0) + " done"; dim: pg.dim }
                StatRow { width: parent.width; label: "Month"; value: Fmt.hm(pg.buckets.month ? pg.buckets.month.workedSec : 0) + "  " + (pg.buckets.month ? pg.buckets.month.tasksDone : 0) + " done"; dim: pg.dim }
                StatRow { width: parent.width; label: "Quarter"; value: Fmt.hm(pg.buckets.quarter ? pg.buckets.quarter.workedSec : 0) + "  " + (pg.buckets.quarter ? pg.buckets.quarter.tasksDone : 0) + " done"; dim: pg.dim }
            }

            Txt { text: "By project"; role: "caption"; faint: true; dim: pg.dim }
            Bars { width: parent.width; rows: pg.asBars(pg.wk ? pg.wk.byProject : [], "project"); dim: pg.dim }
            Txt { text: "By item"; role: "caption"; faint: true; dim: pg.dim }
            RefTable { width: parent.width; rows: pg.wk ? pg.wk.byRef : []; dim: pg.dim }
            Empty { visible: !pg.wk }
        }
    }
}
