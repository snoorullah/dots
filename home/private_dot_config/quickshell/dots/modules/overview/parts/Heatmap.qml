pragma ComponentBehavior: Bound
import QtQuick
import qs.modules.overview
import "../js/Fmt.js" as Fmt
import "../js/Ledger.js" as Ledger

// 17 columns x 7 rows of square cells with a gap, radius 2.
// Compact (the default, used in the card): 11 px cells, gap 3, exactly 235 x 95, no labels.
// Large (the panel page): set cellSize/gap and labels, and the weekday column and the month
// row are drawn around the grid; size is then labelW + grid wide, monthH + grid tall.
// Cell colour is accent at a fixed alpha per T1's score (0..4); the score is never
// computed here. Score 0 is alpha 0 by spec, i.e. an empty slot.
Item {
    id: h
    property var days: []
    property bool dim: false
    property int hovered: -1
    property int cellSize: Look.cell
    property int gap: Look.cellGap
    property bool labels: false
    readonly property int labelW: labels ? Look.sXxxl + Look.sXl : 0
    readonly property int monthH: labels ? Look.fCaption + Look.sL : 0
    readonly property var cells: Ledger.heatCells(days, Look.heatCols, Look.heatRows)
    readonly property var hoverCell: hovered >= 0 ? cells[hovered] : null
    readonly property string hoverText: (hoverCell && !hoverCell.empty)
        ? Fmt.dayLabel(hoverCell.d) + "  " + hoverCell.d + "  " + Fmt.hm(hoverCell.workedSec) : ""
    readonly property int step: cellSize + gap
    objectName: "heatmap"

    implicitWidth: labelW + Look.heatCols * cellSize + (Look.heatCols - 1) * gap
    implicitHeight: monthH + Look.heatRows * cellSize + (Look.heatRows - 1) * gap
    width: implicitWidth
    height: implicitHeight

    Item {
        id: grid
        x: h.labelW
        y: h.monthH
        width: Look.heatCols * h.cellSize + (Look.heatCols - 1) * h.gap
        height: Look.heatRows * h.cellSize + (Look.heatRows - 1) * h.gap

        Repeater {
            model: h.cells
            delegate: Rectangle {
                id: cell
                required property var modelData
                objectName: "cell"
                x: cell.modelData.col * h.step
                y: cell.modelData.row * h.step
                width: h.cellSize
                height: h.cellSize
                radius: Look.rCell
                color: Look.withAlpha(h.dim ? Look.fgFaint : Look.accent, Look.heatRamp[cell.modelData.score])
                border.width: h.hovered === cell.modelData.i ? 1 : 0
                border.color: Look.fgDim
            }
        }

        // One hover area for the whole grid: maps the pointer to a cell, so the
        // tooltip costs one item instead of 119.
        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.NoButton
            onPositionChanged: function (e) {
                var c = Math.floor(e.x / h.step), r = Math.floor(e.y / h.step)
                var inCell = (e.x - c * h.step) < h.cellSize && (e.y - r * h.step) < h.cellSize
                h.hovered = (inCell && c >= 0 && c < Look.heatCols && r >= 0 && r < Look.heatRows)
                    ? c * Look.heatRows + r : -1
            }
            onExited: h.hovered = -1
        }
    }

    // weekday names down the left, one per row
    Repeater {
        model: h.labels ? Ledger.rowWeekdays(h.cells, Look.heatRows) : []
        delegate: Txt {
            required property string modelData
            required property int index
            objectName: "weekdayLabel"
            x: 0
            y: h.monthH + index * h.step + (h.cellSize - implicitHeight) / 2
            width: h.labelW - Look.sL
            text: modelData
            role: "caption"
            faint: true
            dim: h.dim
        }
    }

    // month names along the top, at the column where a month opens
    Repeater {
        model: h.labels ? Ledger.monthMarks(h.cells, Look.heatRows) : []
        delegate: Txt {
            required property var modelData
            objectName: "monthLabel"
            x: h.labelW + modelData.col * h.step
            y: 0
            text: modelData.label
            role: "caption"
            faint: true
            dim: h.dim
            elide: Text.ElideNone
        }
    }
}
