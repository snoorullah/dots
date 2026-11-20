import QtQuick
import "../theme"
import "../common"

// What stays after a dismissed waiting toast: the bar still counts it, and it returns.
NoteBox {
  id: note

  property string age: ""
  property int count: 1

  padX: 14
  Flow {
    width: parent.width
    spacing: 0
    Repeater {
      model: "The toast is gone. The bar still reads".split(" ")
      DText {
        required property string modelData
        role: "bodyS"
        dim: true
        text: modelData + " "
      }
    }
    Row {
      spacing: 4
      StatusMark { anchors.verticalCenter: parent.verticalCenter; level: "waiting"; size: 12 }
      DText {
        role: "bodyS"
        color: Theme.color.waiting
        font.weight: Font.DemiBold
        text: note.count + " · " + note.age
      }
    }
    Repeater {
      model: ". It comes back softly at 10 minutes, then every 30.".split(" ")
      DText {
        required property string modelData
        role: "bodyS"
        dim: true
        text: modelData + " "
      }
    }
  }
}
