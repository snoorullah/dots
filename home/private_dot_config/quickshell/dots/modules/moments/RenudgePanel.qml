import QtQuick
import "../common"

// Board section 2, "Dismiss, and it isn't lost": the toast while it is up, the note once it
// is dismissed. `toastOn` is the state; the card's Dismiss flips it.
MomentPanel {
  id: panel

  property bool toastOn: true
  property string name: "billing-api needs permission"
  property string detail: "terraform plan on staging"
  property string age: "2m"
  property string ref: ""
  property bool animate: true

  title: "Dismiss, and it isn't lost"
  icon: MomentIcons.nudge
  width: 560
  height: implicitHeight

  NudgeCard {
    objectName: "nudgeCard"
    width: parent.width
    visible: panel.toastOn
    shown: panel.toastOn
    animate: panel.animate
    title: panel.name
    detail: panel.detail
    age: panel.age
    ref: panel.ref
    onDismissed: panel.toastOn = false
  }
  NudgeNote {
    objectName: "nudgeNote"
    visible: !panel.toastOn
    age: panel.age
  }
  footer: DText {
    width: parent.width
    role: "bodyS"
    dim: true
    wrapMode: Text.WordWrap
    text: "Clicking always goes to that agent, not the newest one. It leaves only when the agent resumes or you snooze it."
  }
}
