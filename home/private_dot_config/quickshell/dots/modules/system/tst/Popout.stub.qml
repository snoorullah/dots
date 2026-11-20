import QtQuick
import "../../services"

// Stand-in for common/Popout.qml in the wiring smoke test: Popout is a PanelWindow and
// there is no layer-shell backend offscreen. Same name, wanted and default-content contract.
Item {
  property string name: ""
  property int panelWidth: 320
  readonly property bool wanted: Ui.open === name
  default property alias content: body.data
  width: panelWidth
  Item { id: body; width: parent.width; implicitHeight: childrenRect.height }
}
