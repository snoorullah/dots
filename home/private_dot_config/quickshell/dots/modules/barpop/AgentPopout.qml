import QtQuick
import "../common"
import "../../services"
import qs.modules.overview
import "js/Agents.js" as A

// The agents popup. Waiting asks come from the attention feed (items from herdr); the
// running list is the optional agents.json next to attention.json. Nothing here approves,
// denies or answers an agent. Jump to pane and the control centre are local.
Popout {
  id: win

  name: "agent"
  panelWidth: 420

  property string focusId: ""
  onWantedChanged: if (wanted) focusId = ""

  readonly property var built: A.build(Feed.attDoc ? Feed.attDoc.items : [], agents.doc, { focusId: focusId })

  AgentsDoc { id: agents }

  AgentPanel {
    width: parent.width
    model: win.built
    onCardPicked: id => win.focusId = id
    onJump: ref => Actions.jump({ ref: ref })
    onOpenCc: { Ui.close(); Ui.toggleCc("agents"); }
  }
}
