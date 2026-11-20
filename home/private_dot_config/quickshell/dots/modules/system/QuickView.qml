pragma ComponentBehavior: Bound
import QtQuick
import "../theme"
import "../common"
import "js/Menus.js" as Menus

// The panel's first view: header, three meter pills, ten tiles, now playing, the
// notification log. Draws `st`; emits what was asked, SystemPanel acts on it.
Column {
  id: root

  property var st: ({})
  property string selected: ""
  signal tileToggled(string id)
  signal tileOpened(string id)
  signal meterMoved(string which, real fraction)
  signal meterOpened(string id)
  signal mediaCommand(string what)
  signal powerClicked()
  signal settingsClicked()

  readonly property var tileList: Menus.tiles(st)
  readonly property var s: st || ({})
  spacing: Theme.space.xl

  Row {
    width: parent.width
    height: 28
    spacing: Theme.space.m
    SText {
      width: parent.width - 2 * 28 - 2 * Theme.space.m
      anchors.verticalCenter: parent.verticalCenter
      text: [root.s.uptime || "", root.s.host || ""].filter(function (x) { return x !== "" }).join(" · ")
      dim: true
      elide: Text.ElideRight
    }
    SysButton {
      objectName: "settingsButton"
      width: 28; pad: 0
      live: false
      why: "not wired yet"
      SIcon { anchors.centerIn: parent; key: "gear"; boardSize: 15; color: Theme.color.fg }
      onClicked: root.settingsClicked()
    }
    SysButton {
      objectName: "powerButton"
      width: 28; pad: 0
      SIcon { anchors.centerIn: parent; key: "power"; boardSize: 15; color: Theme.color.failed }
      onClicked: root.powerClicked()
    }
  }

  Column {
    width: parent.width
    spacing: Theme.space.m
    SysMeter {
      objectName: "meterBright"
      width: parent.width
      icon: "brightness"
      avail: !!(root.s.bright && root.s.bright.avail)
      value: root.s.bright ? root.s.bright.v : 0
      onMoved: f => root.meterMoved("bright", f)
      onOpened: root.meterOpened("display")
    }
    SysMeter {
      objectName: "meterVol"
      width: parent.width
      icon: root.s.vol && root.s.vol.muted ? "soundOff" : "sound"
      avail: !!(root.s.vol && root.s.vol.avail)
      value: root.s.vol ? root.s.vol.v : 0
      onMoved: f => root.meterMoved("vol", f)
      onOpened: root.meterOpened("sound")
    }
    SysMeter {
      objectName: "meterMic"
      width: parent.width
      icon: root.s.mic && root.s.mic.muted ? "micOff" : "mic"
      avail: !!(root.s.mic && root.s.mic.avail)
      value: root.s.mic ? root.s.mic.v : 0
      onMoved: f => root.meterMoved("mic", f)
      onOpened: root.meterOpened("mic")
    }
  }

  Grid {
    id: grid
    width: parent.width
    columns: 2
    spacing: 6
    Repeater {
      model: root.tileList
      SysTile {
        required property var modelData
        objectName: "tile-" + modelData.id
        width: (grid.width - 6) / 2
        icon: modelData.icon
        name: modelData.name
        sub: modelData.sub
        on: modelData.on
        avail: modelData.avail
        selected: root.selected === modelData.id
        onToggled: root.tileToggled(modelData.id)
        onOpened: root.tileOpened(modelData.id)
      }
    }
  }

  SysMediaRow {
    objectName: "mediaRow"
    width: parent.width
    media: root.s.media || null
    onCommand: what => root.mediaCommand(what)
  }

  DText {
    objectName: "logHead"
    visible: !!(root.s.notifs && root.s.notifs.length > 0)
    width: parent.width
    role: "caption"
    text: "Notifications, " + (root.s.notifs ? root.s.notifs.length : 0) + " logged"
  }
  Column {
    objectName: "log"
    visible: !!(root.s.notifs && root.s.notifs.length > 0)
    width: parent.width
    Repeater {
      model: (root.s.notifs || []).slice(0, 4)
      Item {
        id: nrow
        required property var modelData
        required property int index
        width: parent.width
        height: 30
        Rectangle {
          anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
          height: 1
          color: Qt.alpha(Theme.color.fg, 0.10)
          visible: nrow.index < Math.min(4, (root.s.notifs || []).length) - 1
        }
        SText { anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
                text: nrow.modelData; elide: Text.ElideRight; color: Qt.alpha(Theme.color.fg, 0.85) }
      }
    }
  }
}
