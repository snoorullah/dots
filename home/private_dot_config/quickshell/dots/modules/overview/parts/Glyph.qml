import QtQuick
import qs.modules.overview
import qs.modules.common

// One renderer: delegates to common/Icon (Phosphor via PhosphorIcons). `name` is a
// Phosphor glyph name; an unknown name shows as plain text, ugly but never tofu.
Item {
    id: root
    property string name: ""
    property int size: Look.iconSize
    property bool dim: false
    property bool active: false
    property alias color: icon.color

    width: size
    height: size
    // The glyph must never spill past its box if a name falls back to wide text.
    clip: true

    Icon {
        id: icon
        anchors.fill: parent
        name: root.name
        active: root.active
        size: root.size
        color: root.dim ? Look.fgFaint : Look.fgDim
    }
}
