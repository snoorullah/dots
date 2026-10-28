import QtQuick
import "../theme"

// Material Symbols Rounded, referenced by LIGATURE NAME ("settings"), never by a
// private-use codepoint. Icons say what a thing is, not how urgent it is.
Text {
  property int size: Theme.font.size.title

  font.family: Theme.font.icon
  font.pixelSize: size
  color: Theme.color.fg
  verticalAlignment: Text.AlignVCenter
  horizontalAlignment: Text.AlignHCenter
  renderType: Text.NativeRendering
}
