// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Shaik Noorullah Shareef
//
// Scratchpad model: one per profile, five tabs, only Note is built. Pure.
.pragma library

var tabs = [
  { id: "note",     label: "Note",     icon: "note-pencil",     built: true },
  { id: "terminal", label: "Terminal", icon: "terminal-window", built: false },
  { id: "snippet",  label: "Snippet",  icon: "clipboard-text",  built: false },
  { id: "math",     label: "Math",     icon: "squares-four",    built: false },
  { id: "ask",      label: "Ask",      icon: "sparkle",         built: false }
]

// actions under the editor. Nothing here sends anything: Save writes a local copy, the rest is read-only for now.
var actions = [
  { id: "task",   label: "Turn into task",  stub: true,  tip: "read-only for now: nothing is written to the tracker" },
  { id: "agent",  label: "Send to agent",   stub: true,  tip: "read-only for now: nothing is sent" },
  { id: "save",   label: "Save to notes",   stub: false, tip: "" },
  { id: "pin",    label: "Pin",             stub: false, tip: "" }
]

function build(inp) {
  var tab = inp.tab || "note"
  var cur = tabs.filter(function (t) { return t.id === tab })[0] || tabs[0]
  var text = String(inp.text || "")
  return {
    tabs: tabs.map(function (t) { return { id: t.id, label: t.label, icon: t.icon, built: t.built, on: t.id === cur.id } }),
    tab: cur.id, built: cur.built, text: text, empty: text.trim() === "",
    actions: actions.map(function (a) { return { id: a.id, label: a.label, stub: a.stub || (a.id === "save" && text.trim() === ""), tip: a.id === "save" && text.trim() === "" ? "nothing to save" : a.tip, on: a.id === "pin" && !!inp.pinned } }),
    profile: inp.profile || "",
    foot: "One per project, follows the profile you are in."
  }
}
