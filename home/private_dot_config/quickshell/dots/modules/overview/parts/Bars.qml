pragma ComponentBehavior: Bound
import QtQuick
import qs.modules.overview
import "../js/Fmt.js" as Fmt
import "../js/Ledger.js" as Ledger

// Horizontal bars, one per row: name, bar scaled to the largest, hm + percent.
// rows: [{ name, sec }]. The bar is accent on a faint track: colour is reserved for
// "someone waits" and "failed", so a chart stays quiet.
Column {
    id: b
    property var rows: []
    property bool dim: false
    property int maxRows: 8

    readonly property var shown: (rows || []).slice(0, maxRows)
    readonly property var pcts: Ledger.shares(shown.map(function (r) { return r.sec }))
    readonly property real peak: Ledger.maxSec(shown.map(function (r) { return { sec: r.sec } }))
    spacing: Look.sM

    Repeater {
        model: b.shown
        delegate: Item {
            id: row
            required property var modelData
            required property int index
            width: b.width
            height: 30

            Txt {
                id: nm
                anchors.left: parent.left
                anchors.right: tm.left
                anchors.rightMargin: Look.sL
                text: row.modelData.name
                role: "bodyS"
                dim: b.dim
            }
            Txt {
                id: tm
                anchors.right: parent.right
                text: Fmt.hm(row.modelData.sec) + "  " + b.pcts[row.index] + "%"
                role: "monoS"
                faint: true
                dim: b.dim
                elide: Text.ElideNone
            }
            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 4
                radius: Look.rCell
                color: Look.withAlpha(Look.fg, Look.aTrack)
                Rectangle {
                    width: b.peak > 0 ? Math.max(2, parent.width * row.modelData.sec / b.peak) : 0
                    height: parent.height
                    radius: Look.rCell
                    color: b.dim ? Look.fgFaint : Look.accent
                }
            }
        }
    }
}
