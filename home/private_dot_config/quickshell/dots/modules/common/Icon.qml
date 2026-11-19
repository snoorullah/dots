import QtQuick
import "../theme"

// Phosphor Regular through the `dots Icons` font, which has NO ligatures: a glyph is
// addressed by name and resolved to a codepoint by PhosphorIcons. Bare name = regular
// weight; set `active` for the filled weight. Icons say what a thing is, not how urgent it is.
Item {
  id: root

  property string name: ""
  property bool active: false
  property int size: Theme.font.size.title
  property alias color: glyph.color

  // Deprecated alias for `name`, kept so call sites migrate one at a time.
  property alias text: root.name

  implicitWidth: glyph.implicitWidth
  implicitHeight: glyph.implicitHeight

  Text {
    id: glyph
    anchors.fill: parent
    text: PhosphorIcons.cp(root.name, root.active)
    font.family: Theme.font.icon
    font.pixelSize: root.size
    color: Theme.color.fg
    verticalAlignment: Text.AlignVCenter
    horizontalAlignment: Text.AlignHCenter
    renderType: Text.NativeRendering
  }
}
