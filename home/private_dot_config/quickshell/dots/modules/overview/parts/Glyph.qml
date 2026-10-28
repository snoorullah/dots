import QtQuick
import qs.modules.overview

// Material Symbols Rounded, referenced by LIGATURE NAME ("task_alt"), never by a
// codepoint. Falls back to the plain name text if the font is absent, which is
// ugly but readable and never tofu.
Text {
    property string name: ""
    property int size: Look.iconSize
    property bool dim: false

    text: name
    color: dim ? Look.fgFaint : Look.fgDim
    font.family: Look.iconFont
    font.pixelSize: size
    width: size
    height: size
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
    renderType: Text.NativeRendering
    // The ligature name must never show as wide text if the font is missing.
    clip: true
}
