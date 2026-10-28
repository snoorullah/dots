import QtQuick
import "../theme"
import "../common"
import "../../services"

// The quick panel: wi-fi, bluetooth, do-not-disturb, night light, volume, brightness.
// No more than that. Twin: `qs ipc call dots.quick toggle`.
Popout {
  id: win

  property var notifs: null

  name: "quick"
  panelWidth: 320
  onWantedChanged: {
    if (wanted) {
      Net.refresh();
      Brightness.refresh();
    }
  }

  Column {
    width: parent.width
    spacing: Theme.space.xl

    Grid {
      columns: 2
      spacing: Theme.space.l

      QuickToggle {
        icon: Net.wifi ? "wifi" : "wifi_off"
        label: "Wi-Fi"
        on: Net.wifi
        available: Net.available
        onClicked: Net.setWifi(!Net.wifi)
      }
      QuickToggle {
        icon: Bt.powered ? "bluetooth" : "bluetooth_disabled"
        label: "Bluetooth"
        on: Bt.powered
        available: Bt.available
        onClicked: Bt.setPowered(!Bt.powered)
      }
      QuickToggle {
        icon: "notifications_off"
        label: "Do not disturb"
        on: win.notifs ? win.notifs.dnd : false
        held: true
        onClicked: if (win.notifs) win.notifs.dnd = !win.notifs.dnd
      }
      QuickToggle {
        icon: "nightlight"
        label: "Night light"
        on: NightLight.on
        held: true
        available: NightLight.available
        onClicked: NightLight.toggle()
      }
    }

    QuickSlider {
      width: parent.width
      icon: Audio.muted ? "volume_off" : "volume_up"
      value: Audio.volume
      available: Audio.ready
      onMoved: fraction => { Audio.setVolume(fraction); Hud.show("volume", fraction, Audio.muted); }
    }
    QuickSlider {
      width: parent.width
      icon: "brightness_6"
      value: Brightness.value
      available: Brightness.available
      onMoved: fraction => { Brightness.set(fraction); Hud.show("brightness", fraction, false); }
    }
  }
}
