pragma ComponentBehavior: Bound
import QtQuick
import qs.modules.overview
import "../js/Fmt.js" as Fmt

// Time by work item: ref, title, hm. rows: [{ ref, sec, title }]
Column {
    id: t
    property var rows: []
    property bool dim: false
    property int maxRows: 8
    spacing: Look.sS

    Repeater {
        model: (t.rows || []).slice(0, t.maxRows)
        delegate: Item {
            id: row
            required property var modelData
            width: t.width
            height: 22
            Txt {
                id: rf
                width: 104
                text: row.modelData.ref
                role: "monoS"
                faint: true
                dim: t.dim
            }
            Txt {
                anchors.left: rf.right
                anchors.right: tm.left
                anchors.leftMargin: Look.sL
                anchors.rightMargin: Look.sL
                text: row.modelData.title || ""
                role: "bodyS"
                dim: t.dim
            }
            Txt {
                id: tm
                anchors.right: parent.right
                text: Fmt.hm(row.modelData.sec)
                role: "monoS"
                dim: t.dim
                elide: Text.ElideNone
            }
        }
    }
}
