import QtQuick
import qs.modules.overview

// A boxed figure: caption on top, mono value under it, optional faint note.
Rectangle {
    id: t
    property string label: ""
    property string value: ""
    property string note: ""
    property bool dim: false
    objectName: "statTile"

    implicitHeight: Look.sXl * 2 + col.implicitHeight
    radius: Look.rChip
    color: Look.withAlpha(Look.fg, Look.aHover * 0.5)
    border.width: 1
    border.color: Look.withAlpha(Look.outline, Look.aDivider)

    Column {
        id: col
        x: Look.sXl
        y: Look.sXl
        width: parent.width - Look.sXl * 2
        spacing: Look.sXs
        Txt { text: t.label; role: "caption"; faint: true; dim: t.dim; width: parent.width }
        Txt { text: t.value; role: "headline"; font.family: Look.mono; dim: t.dim; elide: Text.ElideNone }
        Txt { text: t.note; role: "caption"; faint: true; dim: t.dim; width: parent.width }
    }
}
