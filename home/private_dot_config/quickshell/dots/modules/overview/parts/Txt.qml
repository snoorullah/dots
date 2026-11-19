import QtQuick
import qs.modules.overview

// One text style entry point. role picks size and family. Mono (JetBrains Mono) is the
// body font; Bricolage (sans) is only display, headline and page. Table figures use
// role mono/monoS so a changing digit cannot jitter a column.
// dim drops the colour to fgFaint (stale data). caption is a section label.
Text {
    id: t
    property string role: "body"        // caption | bodyS | body | title | headline | page | display | mono | monoS
    property bool dim: false
    property bool faint: false          // secondary text that is not stale

    readonly property bool isSans: role === "display" || role === "headline" || role === "page"
    readonly property bool isLabel: role === "caption"
    property bool mono: false           // explicit override: a number in mono at a sans role
    readonly property bool isMono: mono || !isSans
    color: dim ? Look.fgFaint : ((faint || isLabel) ? Look.fgDim : Look.fg)
    font.family: isMono ? Look.mono : Look.sans
    font.pixelSize: role === "caption" ? Look.fCaption
        : role === "bodyS" || role === "monoS" ? Look.fBodyS
        : role === "title" ? Look.fTitle
        : role === "headline" ? Look.fHeadline
        : role === "page" ? Look.fPage
        : role === "display" ? Look.fDisplay
        : Look.fBody
    font.weight: role === "display" ? Look.wDisplay
        : role === "page" ? Look.wPage
        : role === "headline" || role === "title" ? Look.wTitle
        : isLabel ? Look.wLabel
        : Look.wBody
    font.capitalization: isLabel ? Font.AllUppercase : Font.MixedCase
    font.letterSpacing: isLabel ? font.pixelSize * Look.trackLabel : 0
    // fixed line box from the font.line tokens; it centres the glyphs, so no padding trick
    lineHeightMode: Text.FixedHeight
    lineHeight: role === "caption" ? Look.lCaption
        : role === "bodyS" || role === "monoS" ? Look.lBodyS
        : role === "title" ? Look.lTitle
        : role === "headline" ? Look.lHeadline
        : role === "page" ? Look.lPage
        : role === "display" ? Look.lDisplay
        : Look.lBody
    elide: Text.ElideRight
    renderType: Text.NativeRendering
}
