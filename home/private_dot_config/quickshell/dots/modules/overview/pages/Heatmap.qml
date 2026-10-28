pragma ComponentBehavior: Bound
import QtQuick
import qs.modules.overview
import qs.modules.overview.parts
import qs.modules.overview.parts as Parts
import "../js/Fmt.js" as Fmt
import "../js/Ledger.js" as Ledger

// 119 days of work, five-step ramp from T1's score. Hover a cell for date and time.
// The grid takes the space the page has: cells are sized to fit its width and the height
// left once the title, legend and figures are placed, with weekday and month labels, then
// streak and best-week figures under it. The compact 11 px variant of the same part is the
// one the card uses.
FocusScope {
    id: pg
    readonly property bool dim: Feed.dim
    readonly property var days: Feed.heatDoc ? Feed.heatDoc.days : []
    readonly property real total: days.reduce(function (a, d) { return a + (+d.workedSec || 0) }, 0)
    readonly property int active: days.filter(function (d) { return (+d.workedSec || 0) > 0 }).length
    readonly property real best: days.reduce(function (a, d) { return Math.max(a, +d.workedSec || 0) }, 0)
    readonly property var streak: Ledger.streaks(days)
    readonly property var week: Ledger.bestWeek(days)

    readonly property int gap: Look.sS
    readonly property int legendH: 18
    readonly property int labelW: Look.sXxxl + Look.sXl          // Heatmap part's weekday column
    readonly property int monthH: Look.fCaption + Look.sL        // and its month row
    readonly property int fitW: Math.floor((width - labelW - (Look.heatCols - 1) * gap) / Look.heatCols)
    readonly property int fitH: Math.floor((height - head.height - legendH - tiles.height - Look.sXl * 3
                                            - monthH - (Look.heatRows - 1) * gap) / Look.heatRows)
    readonly property int cellSize: Math.max(Look.cell, Math.min(fitW, fitH))

    Column {
        anchors.left: parent.left
        anchors.top: parent.top
        width: parent.width
        spacing: Look.sXl

        Row {
            id: head
            spacing: Look.sL
            Txt { text: "Last 119 days"; role: "title"; dim: pg.dim }
            StaleMark { visible: pg.dim; anchors.verticalCenter: parent.verticalCenter }
        }
        Parts.Heatmap {
            id: hm
            days: pg.days
            dim: pg.dim
            labels: true
            cellSize: pg.cellSize
            gap: pg.gap
        }
        Item {
            width: parent.width
            height: pg.legendH
            Txt {
                anchors.verticalCenter: parent.verticalCenter
                text: hm.hoverText
                role: "monoS"
                faint: true
                dim: pg.dim
                elide: Text.ElideNone
            }
            Row {
                x: hm.width - width
                anchors.verticalCenter: parent.verticalCenter
                spacing: Look.sS
                Txt { text: "less"; role: "caption"; faint: true; dim: pg.dim; anchors.verticalCenter: parent.verticalCenter }
                Repeater {
                    model: Look.heatRamp
                    delegate: Rectangle {
                        required property real modelData
                        width: Look.cell; height: Look.cell; radius: Look.rCell
                        anchors.verticalCenter: parent.verticalCenter
                        color: Look.withAlpha(pg.dim ? Look.fgFaint : Look.accent, modelData)
                        border.width: modelData === 0 ? 1 : 0
                        border.color: Look.withAlpha(Look.outline, Look.aDivider)
                    }
                }
                Txt { text: "more"; role: "caption"; faint: true; dim: pg.dim; anchors.verticalCenter: parent.verticalCenter }
            }
        }
        Grid {
            id: tiles
            width: parent.width
            columns: 3
            spacing: Look.sXl
            readonly property real tileW: (width - spacing * (columns - 1)) / columns
            StatTile { width: tiles.tileW; label: "Total"; value: Fmt.hm(pg.total); note: "last 119 days"; dim: pg.dim }
            StatTile { width: tiles.tileW; label: "Days worked"; value: String(pg.active); note: "of " + pg.days.length; dim: pg.dim }
            StatTile { width: tiles.tileW; label: "Best day"; value: Fmt.hm(pg.best); dim: pg.dim }
            StatTile {
                width: tiles.tileW; label: "Streak"; value: pg.streak.current + (pg.streak.current === 1 ? " day" : " days")
                note: "longest " + pg.streak.best; dim: pg.dim
            }
            StatTile {
                width: tiles.tileW; label: "Best week"; value: Fmt.hm(pg.week.sec)
                note: pg.week.from !== "" ? Fmt.dayLabel(pg.week.from) + " to " + Fmt.dayLabel(pg.week.to) : ""; dim: pg.dim
            }
            StatTile {
                width: tiles.tileW; label: "Daily average"; value: Fmt.hm(pg.active > 0 ? pg.total / pg.active : 0)
                note: "on worked days"; dim: pg.dim
            }
        }
        Empty { visible: pg.days.length === 0 }
    }
}
