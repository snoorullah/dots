import QtQuick
import qs.modules.theme

// Section caption: 12 px, caps, tracked, 600, dim. Same look as DText's caption role, but the
// tracking is computed from the token directly (DText's reads its own font and loops).
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
