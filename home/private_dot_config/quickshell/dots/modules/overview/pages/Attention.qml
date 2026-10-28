pragma ComponentBehavior: Bound
import QtQuick
import qs.modules.overview
import qs.modules.overview.parts

// Everything waiting on me, most urgent first, then where the data came from.
// Mail is never listed: that source is unavailable by decision.
FocusScope {
    id: pg
    readonly property bool dim: Feed.dim
    readonly property var names: Object.keys(Feed.sources).filter(function (n) { return n !== "mail" }).sort()

    Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: col.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: col
            width: parent.width
            spacing: Look.sS

            Row {
                spacing: Look.sL
                Txt { text: "Needs you"; role: "title"; dim: pg.dim }
                StaleMark { visible: pg.dim; anchors.verticalCenter: parent.verticalCenter }
            }
            Repeater {
                model: Feed.attentionItems
                delegate: AttnRow {
                    required property var modelData
                    width: col.width
                    item: modelData
                    dim: pg.dim
                    onOpenRequested: function (it) { Feed.openItem(it.id) }
                }
            }
            Empty { visible: Feed.attentionItems.length === 0 }

            Rectangle { width: 1; height: Look.sXl; color: "transparent" }
            Txt { text: "Sources"; role: "caption"; faint: true; dim: pg.dim; visible: pg.names.length > 0 }
            Repeater {
                model: pg.names
                delegate: StatRow {
                    required property string modelData
                    width: col.width
                    label: modelData
                    value: Feed.sources[modelData].state || "?"
                    valueRole: "monoS"
                    dim: pg.dim || Feed.sources[modelData].state === "off" || Feed.sources[modelData].state === "unavailable"
                }
            }
        }
    }
}
