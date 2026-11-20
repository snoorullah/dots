import QtQuick
import "../../theme"
import "../../barpop"

// An app tile: a rounded square with the app's glyph. `box` is the tile, glyph is 14 or 16.
Rectangle {
  id: root
  property string icon: "squares-four"
  property int box: 24
  property int glyph: box >= 28 ? 16 : 14
  property color tone: Theme.color.fg
  property bool lit: false
  implicitWidth: box
  implicitHeight: box
  radius: box >= 28 ? 8 : 7
  color: lit ? Qt.alpha(Theme.color.accent, Theme.alpha.on) : Qt.alpha(Theme.color.fg, Theme.alpha.rest + 0.02)
  border.width: 1
  border.color: lit ? Theme.color.accent : Qt.alpha(Theme.color.fg, 0.1)
  Gly { anchors.centerIn: parent; name: root.icon; box: root.glyph; color: root.tone }
}
