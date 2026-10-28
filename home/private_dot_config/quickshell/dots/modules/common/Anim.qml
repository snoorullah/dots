import QtQuick
import "../theme"

// One-shot motion only. Nothing in this shell loops, pulses or spins: bad news
// enters from width 0 over motion.base and leaves over motion.fast.
NumberAnimation {
  duration: Theme.motion.base
  easing.type: Theme.motion.easeIn
}
