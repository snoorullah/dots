import QtQuick
import qs.modules.overview
import qs.modules.common

// The data layer is stale, wrong version or unreadable: the shared unknown mark (Phosphor
// "question", via StatusMark) in the unknown status colour. Same glyph as the bar's Stale.
// Never animated.
Item {
    id: m
    property int size: Look.iconSize
    implicitWidth: size
    implicitHeight: size
    objectName: "staleMark"

    StatusMark {
        anchors.fill: parent
        level: "unknown"
        size: m.size
    }
}
