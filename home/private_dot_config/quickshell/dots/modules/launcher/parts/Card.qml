import QtQuick
import "../../theme"
import "../../common"

// The launcher card (board `Launcher`): 1080 x 620, search row, mode chips, results | preview, footer.
// Pure presentation of a LauncherState; the window (Launcher.qml) and the test scene both host it.
Item {
  id: root

  required property var st
  property string shortcut: "Super + Space"
  property alias field: bar.field

  implicitWidth: 1080
  implicitHeight: 620
  width: implicitWidth
  height: implicitHeight

  readonly property color rule: Qt.alpha(Theme.color.outline, Theme.alpha.divider)

  Surface { anchors.fill: parent; corner: 20 }   // board radius 20

  ClosedCard { visible: root.st.blocked !== ""; anchors.fill: parent; why: root.st.blocked }

  Item {
    anchors.fill: parent
    visible: root.st.blocked === ""

    SearchBar { id: bar; objectName: "searchBar"; st: root.st; shortcut: root.shortcut; width: parent.width; height: 56 }
    Rectangle { id: r1; y: 56; width: parent.width; height: 1; color: root.rule }
    ModeTabs { id: tabs; objectName: "tabs"; st: root.st; y: 57; width: parent.width; height: 40 }
    Rectangle { id: r2; y: 97; width: parent.width; height: 1; color: root.rule }

    Item {
      id: body
      y: 98
      width: parent.width
      height: parent.height - 98 - 33
      ResultList { objectName: "results"; st: root.st; width: Math.round(parent.width * 5 / 11); height: parent.height }
      Rectangle { x: Math.round(parent.width * 5 / 11) - 1; width: 1; height: parent.height; color: root.rule }
      PreviewPane { objectName: "preview"; st: root.st; x: Math.round(parent.width * 5 / 11); width: parent.width - x; height: parent.height }
    }

    Rectangle { y: parent.height - 33; width: parent.width; height: 1; color: root.rule }
    FooterBar { objectName: "footer"; st: root.st; y: parent.height - 32; width: parent.width; height: 32 }

    ConfirmCard {
      objectName: "confirm"
      anchors.fill: body
      spec: root.st.confirm
      onConfirmed: root.st.doConfirm()
      onCancelled: root.st.cancelConfirm()
    }
  }
}
