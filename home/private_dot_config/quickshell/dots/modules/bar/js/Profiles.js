.pragma library
// Workspace profiles: which named group of workspaces a piece of work belongs to.
// The window rules in hyprland.lua.tmpl route app classes to these workspaces on open;
// this file is the other half: which profile owns a workspace, for the bar.
// Keep the workspace numbers in step with docs/shell/specs/profiles.md.

var list = [
  { name: "Agents", icon: "sparkle",          key: "A", ws: [1] },
  { name: "Dev",    icon: "terminal-window",  key: "D", ws: [3] },
  { name: "Web",    icon: "globe",            key: "W", ws: [2] },
  { name: "Comms",  icon: "chat-circle",      key: "C", ws: [4, 5] },
  { name: "Review", icon: "git-pull-request", key: "R", ws: [6] },
  { name: "Notes",  icon: "notebook",         key: "N", ws: [7] },
  { name: "Other",  icon: "stack",            key: "O", ws: [8, 9, 10] }
]

function find(name) {
  for (var i = 0; i < list.length; i++) if (list[i].name === name) return list[i]
  return null
}

// the profile owning a workspace id; any id nobody owns (11+, named ones) is Other
function profileOf(wsId) {
  var id = Number(wsId)
  if (!(id > 0)) return ""
  for (var i = 0; i < list.length; i++)
    if (list[i].ws.indexOf(id) >= 0) return list[i].name
  return "Other"
}

// where Super+Ctrl+<key> and a profile click land: the profile's first workspace
function primary(name) {
  var p = find(name)
  return p ? p.ws[0] : -1
}

// the bar's workspace entries that belong to one profile
function workspacesOf(entries, name) {
  var out = []
  var e = entries || []
  for (var i = 0; i < e.length; i++)
    if (profileOf(e[i].id) === name) out.push(e[i])
  return out
}

// [{name, icon}] for the bar
function barList() {
  return list.map(function (p) { return { name: p.name, icon: p.icon } })
}

// the profile to show for a workspace id: special and unnamed workspaces (id <= 0, e.g. the
// task popup) keep whatever profile was showing, so the bar never blanks
function stickyProfile(wsId, last) {
  var p = profileOf(wsId)
  return p !== "" ? p : (last || "")
}
