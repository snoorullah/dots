import QtQuick
import "../theme"
import "../common"

// The panel's 12 px body: DText at the caption size without the caps and tracking.
DText {
  role: "bodyS"
  font.pixelSize: Theme.font.size.caption
  lineHeight: Theme.font.line.caption
}
