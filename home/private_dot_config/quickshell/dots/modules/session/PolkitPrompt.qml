pragma ComponentBehavior: Bound
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Polkit
import QtQuick
import "../theme"
import "../common"
import "js/Session.js" as S

// The shell's polkit agent (Quickshell.Services.Polkit). Whenever a program asks for
// authorisation a card appears; Allow submits the password to polkit, Deny cancels. Only one
// polkit agent can own a session, so the compositor's own agent must not be started (see the
// wiring notes). Polkit does not say which command asked, so the card shows the action
// message and id, and notes when an agent pane is working (herdr), which makes Deny the default.
Scope {
  id: scope

  property string agentHint: ""
  readonly property var flow: agent.flow
  readonly property bool active: flow !== null && flow !== undefined && !flow.isCompleted

  PolkitAgent { id: agent }

  onActiveChanged: if (active) { scope.agentHint = ""; ask.running = true }

  Process {
    id: ask
    command: ["herdr", "pane", "list"]
    stdout: StdioCollector {
      onStreamFinished: {
        try { scope.agentHint = S.agentHint(JSON.parse(text).result.panes) } catch (e) { scope.agentHint = "" }
      }
    }
  }

  PanelWindow {
    id: win
    screen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
    implicitWidth: card.width
    implicitHeight: card.height
    visible: scope.active
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "qs-panel"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: scope.active ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    Surface {
      id: card
      corner: Theme.radius.card
      width: 440
      height: pc.implicitHeight + 2 * Theme.space.xxl
      PolkitCard {
        id: pc
        x: Theme.space.xxl
        y: Theme.space.xxl
        width: parent.width - 2 * Theme.space.xxl
        view: S.polkitView({
          message: scope.flow ? scope.flow.message : "",
          actionId: scope.flow ? scope.flow.actionId : "",
          inputPrompt: scope.flow ? scope.flow.inputPrompt : "",
          responseVisible: scope.flow ? scope.flow.responseVisible : false,
          supplementaryMessage: scope.flow ? scope.flow.supplementaryMessage : "",
          supplementaryIsError: scope.flow ? scope.flow.supplementaryIsError : false,
          responseRequired: scope.flow ? scope.flow.isResponseRequired : false,
          agentHint: scope.agentHint })
        onSubmitted: value => { if (scope.flow) scope.flow.submit(value) }
        onCancelled: if (scope.flow) scope.flow.cancelAuthenticationRequest()
      }
    }
  }
}
