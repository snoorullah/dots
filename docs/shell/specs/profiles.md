# Workspace profiles

A profile is a named group of workspaces for one kind of work. Apps open on their
profile's workspace; the bar shows only the profile you are in.

## Map (workspace numbers stay 1-10)

| Profile | Workspaces | Key | Classes routed on open |
|---|---|---|---|
| Agents | 1 | Super+Ctrl+A | none (terminals share one class; they open where you are) |
| Web | 2 | Super+Ctrl+W | `zen-beta` `zen-alpha` `zen` `firefox` `brave-browser` `google-chrome` `chromium` `aether` |
| Dev | 3 | Super+Ctrl+D | `code` `code-oss` `Cursor` |
| Comms | 4, 5 | Super+Ctrl+C | 4 chat: `slack` `teams-for-linux` `telegram` `legcord` `beeper` `zapzap`; 5 mail: `thunderbird` |
| Review | 6 | Super+Ctrl+R | none by default |
| Notes | 7 | Super+Ctrl+N | `md.obsidian.Obsidian` |
| Other | 8, 9, 10, 11+ | Super+Ctrl+O | `spotify` (8); anything unrouted on 8+ |

Number keys (`Super+1..0`, `Super+Shift+1..0`) are unchanged. `Super+Ctrl+<letter>`
focuses the profile's first workspace; every one was checked free against the config.

## Where it lives

1. `hyprland.lua.tmpl`: `window_rule(... workspace = "N silent")` per class, and the key loop.
2. `modules/bar/js/Profiles.js`: the same map for the bar (`profileOf`, `primary`, `workspacesOf`).
3. Tests: `modules/bar/tst/tst_profiles.qml`. Change a number in one place, change the other.

## Bar behaviour

- Collapsed: one chip, the active profile's icon and name. Active = owner of the focused workspace.
- Hover the strip, or click the active chip: the other six appear as icons.
- Click another profile: focus its first workspace; the strip collapses.
- Beside it: only the active profile's workspaces, each with its app logos.
- A workspace nobody owns (11+, or named) counts as Other.

## Not done

- Agents cannot be routed until agent terminals get their own window class.
- Last-used workspace per profile (a profile key always lands on its first).
