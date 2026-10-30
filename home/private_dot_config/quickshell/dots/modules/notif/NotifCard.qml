pragma ComponentBehavior: Bound
import Quickshell
import Quickshell.Services.Notifications
import QtQuick
import "../theme"
import "../common"

// The inside of one notification, shared by the toast and the centre: app line with a
// close button, summary, body (the spec allows simple markup), and one button per action.
// Clicking the card opens the source: the app's "default" action, then dots-notif-open
// focuses its window (Claude Code: its herdr pane). Clicking × dismisses.
Item {
  id: card

  required property var notification
  property int summaryLines: 2
  property int bodyLines: 4
  signal opened()

  readonly property var buttons: {
    var out = [];
    var a = notification ? notification.actions : [];
    for (var i = 0; i < a.length; i++)
      if (a[i].identifier !== "default" && a[i].text !== "") out.push(a[i]);
    return out;
  }

  // Text.StyledText (and AutoText, the default, which picks it for anything that looks like
  // markup) renders <img src=...>, and a remote src is fetched: any app's notification, a
  // mail subject, a Slack message. Drop every <img> before anything is shown. The dots-inbox
  // toasts are also HTML-escaped at the source, so their text arrives as &lt;img ... and is
  // shown literally; this strip is the guard for every other app.
  function safe(t) {
    return String(t || "").replace(/<\s*img\b[^>]*>?/gi, "");
  }

  function open() {
    var n = card.notification;
    if (!n) return;
    var app = n.appName, entry = n.desktopEntry, def = null;
    for (var i = 0; i < n.actions.length; i++)
      if (n.actions[i].identifier === "default") def = n.actions[i];
    Quickshell.execDetached(["dots-notif-open", app, entry]);
    card.opened();
    if (def) def.invoke(); else n.dismiss();
  }

  implicitHeight: col.implicitHeight

  MouseArea {
    id: body
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    onClicked: card.open()
  }

  Column {
    id: col
    width: parent.width
    spacing: Theme.space.s

    Item {
      width: parent.width
      height: Math.max(appLine.implicitHeight, 20)

      DText {
        id: appLine
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - close.width - Theme.space.s
        text: card.notification ? card.notification.appName : ""
        textFormat: Text.PlainText
        dim: true
        role: "caption"
        elide: Text.ElideRight
      }
      MouseArea {
        id: close
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: 20
        height: 20
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: if (card.notification) card.notification.dismiss()
        Rectangle {
          anchors.fill: parent
          radius: width / 2
          color: close.containsMouse ? Qt.alpha(Theme.color.fg, Theme.alpha.hover) : "transparent"
        }
        Icon {
          anchors.centerIn: parent
          text: "close"
          size: 14
          color: close.containsMouse ? Theme.color.fg : Theme.color.fgDim
        }
      }
    }
    DText {
      width: parent.width
      text: card.notification ? card.safe(card.notification.summary) : ""
      textFormat: Text.StyledText
      role: "title"
      wrapMode: Text.WordWrap
      maximumLineCount: card.summaryLines
      elide: Text.ElideRight
    }
    DText {
      width: parent.width
      text: card.notification ? card.safe(card.notification.body) : ""
      textFormat: Text.StyledText
      dim: true
      role: "bodyS"
      wrapMode: Text.WordWrap
      maximumLineCount: card.bodyLines
      elide: Text.ElideRight
      visible: text !== ""
    }
    Flow {
      width: parent.width
      spacing: Theme.space.s
      visible: card.buttons.length > 0
      topPadding: Theme.space.xs

      Repeater {
        model: card.buttons

        MouseArea {
          id: btn
          required property var modelData
          width: label.implicitWidth + 2 * Theme.space.l
          height: 26
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: btn.modelData.invoke()
          Rectangle {
            anchors.fill: parent
            radius: Theme.radius.chip
            color: Qt.alpha(Theme.color.fg, btn.containsMouse ? 2 * Theme.alpha.hover : Theme.alpha.hover)
          }
          DText {
            id: label
            anchors.centerIn: parent
            text: btn.modelData.text
            role: "bodyS"
          }
        }
      }
    }
  }
}
