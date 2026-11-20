import QtQuick
import "../theme"

// A small mixed-case line (caption size): notes, ages, hints. Dim unless told otherwise.
// Built on Text, not DText: DText's caption role binds letterSpacing to its own pixelSize,
// which Qt reports as a binding loop.
Text {
  property bool dim: true
  font.family: Theme.font.mono
  font.pixelSize: Theme.font.size.caption
  font.weight: Theme.font.weight.body
  color: dim ? Theme.color.fgDim : Theme.color.fg
  verticalAlignment: Text.AlignVCenter
  lineHeightMode: Text.FixedHeight
  lineHeight: Theme.font.line.caption
  renderType: Text.NativeRendering
}
