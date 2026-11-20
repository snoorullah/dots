# Launcher provider contract (boards: `Launcher`, `MenuLauncher*`)

Core and modes build against this file only. Base type: `modules/launcher/providers/Provider.qml`.
---
## 1. Layout

```
modules/launcher/
  Launcher.qml        core: window, field, chips, list, preview, actions
  providers/          Provider.qml + one <Name>Provider.qml per mode
  providers/*.py      helpers (Python), one per mode, with tests/
```

---
## 2. Discovery

1. Core holds a static `providers: [ ... ]` list in `Launcher.qml` (order = chip order, All first).
2. One provider per `Provider` subclass instance; no scanning, no plugins.
3. A provider with a missing helper or failing probe shows its error row; the rest still work.
4. Prefix is unique, 1-2 chars (`c:` `d:` `f:` `t:` `>` `=` `w:` `h:` `k:` `s:` `e:`).

---
## 3. Row and actions

| Field | Meaning |
|---|---|
| `key` | stable id inside the provider (selection survives re-query) |
| `title`, `sub` | list line 1 and 2 (muted) |
| `icon` | Phosphor name, never Nerd Font |
| `preview` | `{head, body, font?, image?}`; head 20px, body muted; `font` = CSS family shown at 36px; `image` = file path |
| `actions` | `[{label, primary}]`; index 0 is Enter; others get the secondary button style |

---
## 4. All: merge and rank

1. Active only on empty prefix and non-empty query; empty query shows Recents (last 8 activated, no `sensitive` providers).
2. Each `inAll` provider queried in parallel; keeps at most `allLimit` rows.
3. `rank = (row.score ?? 0.5) * allWeight`, plus 0.2 if activated in the last 7 days; sort descending, stable.
4. All groups nothing; each row shows its provider icon. Enter runs the row's own action 0 via its provider.
5. Slow providers never block: rows appear as each finishes; `busy` shows a spinner in the field.

---
## 5. Keyboard

| Key | Does |
|---|---|
| typing | prefix match switches mode and is shown as a chip; Backspace on empty chip returns to All |
| `Tab` / `Shift+Tab` | next / previous mode |
| `Ctrl+N` `Ctrl+P` or arrows | move selection (wraps off) |
| `Enter` | `activate(row, 0)` |
| `Ctrl+1..9` | `activate(row, n-1)` |
| `Ctrl+J` / `Ctrl+K` | cycle the secondary action, `Ctrl+Enter` runs it |
| `Esc` | close confirm card, else clear field, else close launcher |

The core owns the field; providers never take focus. Mode-specific keys go through `actions`.

---
## 6. Provider outcomes

1. `done(close, toast)`: core shows the toast and closes when `close` is true.
2. `confirmRequested({title, detail, danger, label})`: core draws the confirm card; Enter confirms; the core then calls `activate(row, action)` once more and the provider treats that second call as confirmed (it tracks its own pending row).
3. `error` non-empty: list shows one error row with the text; other state is kept.
4. `hint`: empty-state line when `rows` is empty and not busy.

---
## 7. Helpers (Python, argv only)

1. `helper` is an argv array; the query is appended as the last argument. Never a shell string.
2. stdout is one JSON object: `{"rows":[...], "hint":"...", "error":"..."}`; exit 0 even for "no results".
3. Helpers read local files only; no network except `llm` (Ollama on localhost).
4. A newer query supersedes an older one (`seq`); stale output is dropped.
5. Actions that change things call a second helper verb via `run([...], cb)`, same JSON shape.
6. Sensitive providers (`sensitive: true`) log nothing and `reset()` on close.

---
## 8. Rendering

- Core draws rows, preview and action buttons from the model; providers ship no UI.
- Tokens from `modules/theme`; no hex, no green; motion via `Anim`.
- Locked or Salah state: core shows the board's closed card; providers are not queried.
