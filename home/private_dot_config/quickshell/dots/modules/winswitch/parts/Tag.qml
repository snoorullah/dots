import QtQuick
import "../../theme"
import "../../barpop"

// A small rounded label on a card or in a caption. `tone`: dim | accent | warn | solid | light.
// Colour never stands alone: the caller always puts words in it.
Rectangle {
  id: root
  property string text: ""
  property string tone: "dim"
  property string icon: ""
  readonly property color fg: tone === "accent" ? Theme.color.accent
    : tone === "warn" ? Theme.color.waiting
    : tone === "solid" ? Theme.color.accentFg
    : tone === "light" ? Theme.color.bg
    : Theme.color.fgDim
  implicitWidth: row.implicitWidth + 2 * Theme.space.m
  implicitHeight: 20
  radius: 10
  color: tone === "solid" ? Theme.color.accent
    : tone === "light" ? Theme.color.fg
    : tone === "accent" ? Qt.alpha(Theme.color.accent, Theme.alpha.on)
    : Qt.alpha(Theme.color.bg, 0.85)
  border.width: tone === "dim" || tone === "warn" ? 1 : 0
  border.color: tone === "warn" ? Theme.color.waiting : Theme.color.outlineVariant
  Row {
    id: row
    anchors.centerIn: parent
    spacing: Theme.space.s
    Gly { visible: root.icon !== ""; anchors.verticalCenter: parent.verticalCenter; name: root.icon; box: 12; color: root.fg }
    Cap { anchors.verticalCenter: parent.verticalCenter; text: root.text; dim: false; color: root.fg; font.weight: root.tone === "solid" || root.tone === "light" ? Font.DemiBold : Font.Normal }
  }
}
