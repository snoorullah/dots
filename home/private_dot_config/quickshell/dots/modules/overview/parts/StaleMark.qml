import QtQuick
import qs.modules.overview

// Hollow "?": the data layer is stale, wrong version or unreadable. Outline only,
// at fgFaint, so it claims no attention. Never animated.
// This is the canonical stale glyph: T2's bar chip adopts this exact shape (outlined
// circle, 1px stroke, centred "?" at 0.62 of the size).
Item {
    id: m
    property int size: Look.iconSize
    implicitWidth: size
    implicitHeight: size
    objectName: "staleMark"

    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: "transparent"
        border.width: 1
        border.color: Look.fgFaint
    }
    Text {
        anchors.centerIn: parent
        text: "?"
        color: Look.fgFaint
        font.family: Look.mono
        font.pixelSize: Math.round(m.size * 0.62)
        renderType: Text.NativeRendering
    }
}
