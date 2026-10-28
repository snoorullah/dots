import Quickshell
import Quickshell.Io
import QtQuick
import ".."
import "../../../services"

// Hosts the overview pill. The pill is a separate track's file and may not exist yet:
// a probe FileView decides, and the chip stays at zero width until the pill itself
// reports a width (nominal = 0). Its click goes to the overview host, never to us.
Chip {
  id: chip

  property bool pillExists: false
  readonly property bool pillReady: loader.item !== null && (loader.item as Item).implicitWidth > 0

  shown: pillReady
  hoverable: false

  FileView {
    path: Quickshell.shellPath("modules/overview/OverviewPill.qml")
    onLoaded: chip.pillExists = true
    onLoadFailed: chip.pillExists = false
  }

  Loader {
    id: loader
    anchors.verticalCenter: parent.verticalCenter
    asynchronous: true
    active: chip.pillExists
    source: Qt.resolvedUrl("../../overview/OverviewPill.qml")
    onLoaded: {
      // the pill is another track's type: untyped on purpose, the contract is docs/contracts/qml-api.md
      var pill = item;
      pill.screenName = Qt.binding(() => chip.screenName);
      pill.attnWaiting = Qt.binding(() => Attention.waiting);
      pill.attnFailed = Qt.binding(() => Attention.failed);
      pill.stale = Qt.binding(() => Attention.stale);
      // qmllint disable missing-property
      pill.cardRequested.connect(() => Overview.toggleCard());
      pill.panelRequested.connect(page => Overview.openPanel(page));
    }
  }
}
