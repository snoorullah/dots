import QtQuick
import "../theme"

// A translucent panel. The compositor blurs it (layer rule per namespace), which is
// why it is translucent rather than merely dark.
Rectangle {
  property real fill: Theme.alpha.panel
  property real corner: Theme.radius.panel   // popouts and toasts pass Theme.radius.card

  color: Qt.alpha(Theme.color.surface, fill)
  radius: corner
  border.width: 1
  border.color: Qt.alpha(Theme.color.outline, Theme.alpha.divider)
}
