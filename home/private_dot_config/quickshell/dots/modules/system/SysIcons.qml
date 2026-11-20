pragma Singleton
import QtQuick

// Icon KEY (what js/Menus.js returns) to Phosphor name. Names live here, as literals,
// so tools/gen-phosphor-qml.py finds them; the keys are bare identifiers on purpose.
QtObject {
  readonly property var icons: ({
    wifi: "wifi-high", wifiOff: "wifi-slash", bt: "bluetooth", btOff: "bluetooth-slash",
    quiet: "bell-slash", vpn: "shield", ts: "network", mic: "microphone", micOff: "microphone-slash",
    night: "moon-stars", awake: "coffee", perf: "gauge", theme: "palette",
    sound: "speaker-high", soundOff: "speaker-slash", display: "sun", brightness: "sun",
    gear: "gear", power: "power", lock: "lock", logout: "sign-out", suspend: "moon",
    reboot: "arrow-clockwise", backup: "hard-drives", caret: "caret-right", back: "caret-left", x: "x",
    secure: "lock-simple", prev: "skip-back", play: "play", pause: "pause", next: "skip-forward",
    fullscreen: "arrows-out-simple", tile: "columns", tabgroup: "tabs", pin: "push-pin",
    profile: "arrow-square-out", screenshot: "camera", close: "x", wallpaper: "image",
    workspace: "plus", capture: "note-pencil", settings: "gear"
  })

  // The dots Icons font draws a glyph at about 0.64 of its pixel size, while the boards
  // give SVG pixel sizes. One constant, so a corrected font only needs this changed.
  readonly property real scale: 1.5
  function px(boardSize) { return Math.round(boardSize * scale) }

  function name(key) { return icons[key] !== undefined ? icons[key] : key }
}
