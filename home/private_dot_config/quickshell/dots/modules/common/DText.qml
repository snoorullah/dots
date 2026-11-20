import QtQuick
import "../theme"

// Body text. `role` is the type scale shared with the overview's Txt:
// caption | bodyS | body | title | headline | page | display.
// Mono (JetBrains Mono) is the body font. Bricolage (sans) is only for display,
// headline and page. caption is a section label: caps, tracked, 600, dim.
// Numerals that change in a column (counters, percentages) set mono: true so a
// changing digit never jitters the layout, even at a sans role.
Text {
  property string role: "body"
  property bool mono: false
  property bool dim: false

  readonly property bool isSans: role === "display" || role === "headline" || role === "page"
  readonly property bool isLabel: role === "caption"

  font.family: (mono || !isSans) ? Theme.font.mono : Theme.font.sans
  font.pixelSize: role === "caption" ? Theme.font.size.caption
    : role === "bodyS" ? Theme.font.size.bodyS
    : role === "title" ? Theme.font.size.title
    : role === "headline" ? Theme.font.size.headline
    : role === "page" ? Theme.font.size.page
    : role === "display" ? Theme.font.size.display
    : Theme.font.size.body
  font.weight: role === "display" ? Theme.font.weight.display
    : role === "page" ? Theme.font.weight.page
    : role === "headline" || role === "title" ? Theme.font.weight.title
    : isLabel ? Theme.font.weight.label
    : Theme.font.weight.body
  font.capitalization: isLabel ? Font.AllUppercase : Font.MixedCase
  font.letterSpacing: isLabel ? font.pixelSize * Theme.font.track.label : 0
  color: (dim || isLabel) ? Theme.color.fgDim : Theme.color.fg
  verticalAlignment: Text.AlignVCenter
  // fixed line box from the font.line tokens; it centres the glyphs, so no padding trick
  lineHeightMode: Text.FixedHeight
  lineHeight: role === "caption" ? Theme.font.line.caption
    : role === "bodyS" ? Theme.font.line.bodyS
    : role === "title" ? Theme.font.line.title
    : role === "headline" ? Theme.font.line.headline
    : role === "page" ? Theme.font.line.page
    : role === "display" ? Theme.font.line.display
    : Theme.font.line.body
  renderType: Text.NativeRendering
}
