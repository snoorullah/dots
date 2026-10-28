import QtQuick
import "../theme"

// Body text. `role` is the type scale shared with the overview's Txt:
// caption | bodyS | body | title | headline | display. title and up are DemiBold.
// Numerals that change (counters, clocks, percentages) set mono: true so a changing
// digit never jitters the layout.
Text {
  property string role: "body"
  property bool mono: false
  property bool dim: false

  readonly property bool heavy: role === "title" || role === "headline" || role === "display"

  font.family: mono ? Theme.font.mono : Theme.font.sans
  font.pixelSize: role === "caption" ? Theme.font.size.caption
    : role === "bodyS" ? Theme.font.size.bodyS
    : role === "title" ? Theme.font.size.title
    : role === "headline" ? Theme.font.size.headline
    : role === "display" ? Theme.font.size.display
    : Theme.font.size.body
  font.weight: heavy ? Font.DemiBold : Font.Normal
  color: dim ? Theme.color.fgDim : Theme.color.fg
  verticalAlignment: Text.AlignVCenter
  // 1.35 leading, but a single line gets it as padding above AND below: Qt adds the
  // leading under the glyphs, which sits every boxed label (chip, button, nav row) ~2 px high
  readonly property bool multiLine: wrapMode !== Text.NoWrap
  lineHeight: multiLine ? 1.35 : 1.0
  topPadding: multiLine ? 0 : Math.round(font.pixelSize * 0.175)
  bottomPadding: multiLine ? 0 : Math.round(font.pixelSize * 0.175)
  renderType: Text.NativeRendering
}
