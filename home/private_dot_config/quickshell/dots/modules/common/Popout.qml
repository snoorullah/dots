import Quickshell
import Quickshell.Wayland
import QtQuick
import "../theme"
import "../../services"

// A dropdown that hangs under the bar with an 8x4 notch pointing at what opened it.
// Opens with scale 0.92 -> 1 and opacity from the notch (motion.base), closes over
// motion.fast. Dismisses on an outside click.
PanelWindow {
  id: win

  property string name: ""
  property int panelWidth: 320
  readonly property int notchW: 8      // spec pixel table; the card draws the same 8x4
  readonly property int notchH: 4
  default property alias content: body.data
  readonly property bool wanted: Ui.open === name
  readonly property real notchX: Math.max(Theme.radius.card + notchW / 2,
    Math.min(width - Theme.radius.card - notchW / 2, Ui.anchorX - marginLeft))
  property real marginLeft: 0

  screen: {
    for (var i = 0; i < Quickshell.screens.length; i++)
      if (Quickshell.screens[i].name === Ui.screenName) return Quickshell.screens[i];
    return Quickshell.screens.length > 0 ? Quickshell.screens[0] : null;
  }
  anchors { top: true; left: true }
// PanelWindow.margins is real but Quickshell does not export it to qmllint
  // qmllint disable unqualified unresolved-type
  margins.top: Theme.bar.height + 2
  margins.left: win.marginLeft
  implicitWidth: panelWidth
  implicitHeight: card.height + notch.height
  visible: wanted || card.opacity > 0.01
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.namespace: "qs-panel"
  WlrLayershell.layer: WlrLayer.Overlay

  onWantedChanged: {
    if (wanted && screen)
      marginLeft = Math.max(Theme.space.l, Math.min(screen.width - panelWidth - Theme.space.l, Ui.anchorX - panelWidth / 2));
  }

  DismissGrab {
    windows: [win]
    armed: win.wanted
    onDismissed: Ui.close()
  }

  Canvas {
    id: notch
    x: win.notchX - win.notchW / 2
    width: win.notchW
    height: win.notchH
    opacity: card.opacity
    property color fill: Qt.alpha(Theme.color.surface, Theme.alpha.panel)
    onFillChanged: requestPaint()
    onPaint: {
      var c = getContext("2d");
      c.reset();
      c.fillStyle = Qt.rgba(fill.r, fill.g, fill.b, fill.a);
      c.beginPath();
      c.moveTo(0, height);
      c.lineTo(width / 2, 0);
      c.lineTo(width, height);
      c.closePath();
      c.fill();
    }
  }

  Surface {
    id: card
    corner: Theme.radius.card
    y: notch.height
    width: parent.width
    height: body.implicitHeight + 2 * Theme.space.xxl
    opacity: win.wanted ? 1 : 0
    transform: Scale {
      origin.x: win.notchX
      origin.y: 0
      xScale: win.wanted ? 1 : 0.92
      yScale: win.wanted ? 1 : 0.92
      Behavior on xScale { Anim { duration: win.wanted ? Theme.motion.base : Theme.motion.fast } }
      Behavior on yScale { Anim { duration: win.wanted ? Theme.motion.base : Theme.motion.fast } }
    }
    Behavior on opacity { Anim { duration: win.wanted ? Theme.motion.base : Theme.motion.fast } }

    Item {
      id: body
      x: Theme.space.xxl
      y: Theme.space.xxl
      width: parent.width - 2 * Theme.space.xxl
      implicitHeight: childrenRect.height
    }
  }
}
