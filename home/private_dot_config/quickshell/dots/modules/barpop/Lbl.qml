import QtQuick
import "../theme"

// A section label: caps, tracked, semibold, dim. The same look as DText role "caption",
// without the self-referencing letterSpacing binding.
Text {
  font.family: Theme.font.mono
  font.pixelSize: Theme.font.size.caption
  font.weight: Theme.font.weight.label
  font.capitalization: Font.AllUppercase
  font.letterSpacing: Theme.font.size.caption * Theme.font.track.label
  color: Theme.color.fgDim
  verticalAlignment: Text.AlignVCenter
  lineHeightMode: Text.FixedHeight
  lineHeight: Theme.font.line.caption
  renderType: Text.NativeRendering
}
