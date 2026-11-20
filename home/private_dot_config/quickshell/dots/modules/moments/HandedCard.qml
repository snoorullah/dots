import QtQuick
import "../common"
import "js/Moments.js" as M

// Board section 4, "Handed to an agent": a read-only record. What was asked, what you said,
// what the agent did and when, and the one permission it used. `handed` is
// {ask, said, steps[{at,text}], permission}; nothing writes it yet, so it may be null.
MomentPanel {
  id: card

  property var handed: null
  readonly property var model: M.handedModel(handed)

  title: "Handed to an agent"
  icon: MomentIcons.handed
  gap: 10
  width: 560
  height: implicitHeight

  DText {
    width: parent.width
    visible: card.model.empty
    role: "bodyS"
    dim: true
    text: "Nothing handed over."
  }
  DText {
    objectName: "handedAsk"
    width: parent.width
    visible: !card.model.empty
    role: "bodyS"
    dim: true
    wrapMode: Text.WordWrap
    text: card.model.ask + (card.model.said !== "" ? " " + card.model.said : "")
  }
  Column {
    width: parent.width
    spacing: 10
    Repeater {
      model: card.model.steps
      Item {
        id: step
        required property var modelData
        width: parent.width
        height: Math.max(18, stepText.implicitHeight)
        objectName: "handedStep"
        DText {
          x: 0
          width: 44
          role: "bodyS"
          dim: true
          text: step.modelData.at
        }
        DText {
          id: stepText
          x: 52
          width: parent.width - 52
          role: "bodyS"
          wrapMode: Text.WordWrap
          text: step.modelData.text
        }
      }
    }
  }
  footer: NoteBox {
    objectName: "handedFooter"
    visible: card.model.permission !== ""
    padY: 10
    Flow {
      width: parent.width
      spacing: 0
      Repeater {
        model: (card.model.permission + " ").split(" ")
        DText {
          required property string modelData
          role: "bodyS"
          dim: true
          text: modelData + " "
        }
      }
      MButton {
        objectName: "handedSent"
        kind: "link"
        padX: 0
        implicitHeight: 18
        text: "See what was sent"
        usable: false
        // read-only: showing a sent message is a remote read
      }
    }
  }
}
