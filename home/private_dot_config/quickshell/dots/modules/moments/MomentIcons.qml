pragma Singleton
import QtQuick

// The one place the moments surfaces name an icon. The board uses note-pencil,
// arrow-elbow-down-left, bell-ringing, arrow-u-down-left, paper-plane-tilt and
// clock-clockwise; the generated registry (PhosphorIcons) does not carry them yet, so each
// has a stand-in that resolves today. When the registry grows, change the names here only.
QtObject {
  readonly property string capture: "list-plus"        // board: note-pencil
  readonly property string enter: "caret-right"        // board: arrow-elbow-down-left
  readonly property string nudge: "bell"               // board: bell-ringing
  readonly property string jump: "arrow-square-out"
  readonly property string dismiss: "x"
  readonly property string back: "caret-left"          // board: arrow-u-down-left
  readonly property string handed: "chat-circle"       // board: paper-plane-tilt
}
