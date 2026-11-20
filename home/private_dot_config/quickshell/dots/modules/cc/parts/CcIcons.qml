pragma Singleton
import QtQuick

// Every Phosphor icon the control centre names from DATA (js/Queue.js action and source tables,
// model arrays) rather than from an `Icon { name: "x" }` literal. tools/gen-phosphor-qml.py
// reads `icons: ({ ... })` maps, so listing the names here is what puts them in PhosphorIcons.
// tests/cc-ui.sh checks that every icon name in js/Queue.js is listed.
QtObject {
  readonly property var icons: ({
    all: "funnel", agent: "sparkle", slack: "chat-circle", mail: "envelope", github: "git-pull-request",
    erp: "ticket", alert: "bell-ringing", you: "note-pencil",
    allow: "check", deny: "x", pane: "terminal-window", snooze: "alarm", reply: "arrow-bend-up-left",
    send: "paper-plane-tilt", queue: "list-plus", open: "arrow-square-out", analysis: "magnifying-glass",
    fix: "git-branch", review: "eye", draft: "pencil-simple", task: "check-square",
    vips: "star", overdue: "clock-countdown", infra: "hard-drives",
    today: "calendar-check", board: "kanban", list: "list-bullets"
  })
}
