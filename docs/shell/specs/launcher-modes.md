# Launcher modes (boards `Launcher` tabs, `MenuLauncher{Windows,Snippets,Emoji,Hosts,Kube}`)

Contract: `launcher-contract.md`. Each mode = one provider (`providers/<Name>.qml`, presentation only)
+ one Python helper (`~/.local/bin/dots-launch-<mode>`, logic, JSON on stdout). Tests: `tests/launcher-modes.sh`.
---
## 1. Modes

| Prefix | Provider | Helper | Data source | Read-only / stubbed |
|---|---|---|---|---|
| `f:` | `Files` | `dots-launch-files` | `fd` over `$HOME` (secret dirs excluded) | Send to agent = stub (toast) |
| `d:` | `Dictionary` | `dots-launch-dict` | WordNet files (package `wordnet`), grammar = `llm` CLI | no WordNet = error row |
| `t:` | `Fonts` | `dots-launch-fonts` | `fc-list`, `PhosphorIcons.qml` names | Install, Copy SVG = stub |
| `w:` | `Windows` | `dots-launch-windows` | `hyprctl clients -j`, `herdr pane list` | audio filter needs fixture data |
| `s:` | `Snippets` | `dots-launch-snippets` | `~/.config/dots-launcher/snippets/*.json` | model "closest" = difflib |
| `e:` | `Emoji` | `dots-launch-emoji` | `unicodedata` + keyword table, `fc-list` for tofu | Copy only, never types |
| `h:` | `Hosts` | `dots-launch-hosts` | `~/.ssh/config`, `herdr pane list` | reachability not probed |
| `k:` | `Kube` | `dots-launch-kube` | `kubectl config view` | Peek reads only; ns list asks cluster |

---
## 2. Board states rendered (PNG per state, `SHOTS_DIR`)

1. Launcher tabs: `files`, `dict-word`, `dict-grammar`, `fonts`, `fonts-icon`.
2. Windows: `recent`, `focus`, `privacy`, `typed`, `panes`, `task`, `empty`, `single`, `error`, `salah`.
3. Snippets: `default`, `typing`, `filling`, `copied`, `sent`, `empty`, `nomatch`, `adding`, `sensitive`, `error`.
4. Emoji: `empty`, `browse`, `search`, `tray`, `copied`, `nomatch`, `tofu`.
5. Hosts: `default`, `filtered`, `actions`, `open`, `empty`, `adhoc`.
6. Kube: `default`, `changed`, `filter`, `nomatch`, `prod`, `confirm`, `ns`, `switched`, `peek`, `onprod`, `unreach`, `mismatch`, `nokube`, `idle`.

---
## 3. Row extras (optional, core may ignore)

1. `group`: section header drawn above the row. `indent`: 1 for nested rows (panes).
2. `chips: [{t, tone}]`, tone = `warn` `danger` `accent` `muted`. `hl: [index]`: matched letters.
3. `preview.fields: [{name, value, state}]`, state = `filled` `ghost` `empty` (snippet blanks).
4. `actions: [{label, primary, verb, arg, disabled}]`. Provider runs `helper act <verb> <arg>`.
5. `banner: {tone, title, detail}` on the provider: notice line above the list.

---
## 4. Rules

1. Argv only. No shell string anywhere; helpers call `subprocess` with lists.
2. Nothing leaves the machine: no probe of remote hosts; `llm` is the local model.
3. Anything that changes state goes through `act`; `DOTS_LAUNCH_EXEC_LOG=<file>` logs the argv instead of running it (tests).
4. Kube switch always asks first (owner decision 6); prod and unset tiers are marked `danger`.
5. Snippets refuse token-like text; saving it anyway needs a second Enter (`--force`).
6. Windows: titles masked to the app name when `masked` is set or the class is on the deny list.
7. Provider `reset()` drops rows; Snippets and Windows set `sensitive` where titles or text are private.

---
## 5. Deferred vs board

Not built yet. Each is a board element with no UI here.

1. **Kube undo**: board has a 5 s toast (Backspace). Built: row action "Undo last switch", 300 s window.
2. **Kube confirm card**: helper emits `spec.alt` (Peek instead, safer). Core `ConfirmCard.qml` must draw it and call `Kube.peekInstead()`. The test frame draws it.
3. **Snippets**: Shorter/Warmer preview (Ctrl+G, Accept/Discard) and the suggested-snippet strip (Accept/Dismiss). The helper emits `alt` text; no preview UI.
4. **Snippets store error**: "Open file" and "Retry" buttons. Only the error banner exists.
5. **Emoji**: "Ask local model, Ctrl+L". Not built.
6. **Sensitive copies**: Dictionary result and secret-like Snippets use `wl-copy --sensitive`, so clipboard history skips them.
