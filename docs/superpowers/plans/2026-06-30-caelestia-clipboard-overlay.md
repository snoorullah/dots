# Caelestia Clipboard Overlay Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the broken X11 `Super+C` greenclip/rofi clipboard with a native, keyboard-first caelestia (Quickshell/QML) clipboard overlay backed by cliphist.

**Architecture:** Fork caelestia-shell via a local-path flake input. Add a `modules/clipboard/` overlay (mirroring `modules/areapicker` for IPC + WlrLayer overlay window) plus `services/Cliphist|ClipPins|ClipMeta`. Pure logic lives in `modules/clipboard/logic.js` (node-unit-tested). A bash sidecar records source-app + timestamp into JSON, joined lazily in QML by `Qt.md5` of decoded text.

**Tech Stack:** Quickshell QML + JS, Nix flake + home-manager, cliphist + wl-clipboard, bash, node (logic tests).

## Global Constraints

- caelestia-shell fork lives at `/home/devsupreme/src/caelestia-shell` (origin `github.com/caelestia-dots/shell`); custom code isolated under `modules/clipboard/` + the three new `services/Clip*.qml` to ease upstream rebases.
- Reuse only existing caelestia APIs: components `qs.components` (`StyledRect`, `StyledText`, `MaterialIcon`), `qs.components.containers` (`StyledWindow`, `StyledListView`), `qs.components.controls` (`StyledTextField`, `IconButton`), services `qs.services` (`Colours.palette.*`, `Screens.screens`); `Quickshell.Io` (`Process`, `SplitParser`, `StdioCollector`, `IpcHandler`, `FileView`), `Quickshell.Wayland` (`WlrLayershell`).
- IPC target name: `clipboard`. Keybind: `Super+C` → `caelestia-shell ipc call clipboard open`.
- Build/apply: `home-manager switch --flake ~/dotfiles` (rebuilds + restarts the shell).
- Copy-only (no keystroke injection). md5 (not sha256) for the meta join (`Qt.md5` in QML, `md5sum` in bash).
- Dotfiles work on branch `feat/caelestia-clipboard-overlay` (already created); commit per task.

---

### Task 1: Phase 0 — wire the fork (local-path flake input)

**Files:**
- Modify: `~/dotfiles/flake.nix` (the `caelestia` input line)

**Interfaces:**
- Produces: a buildable shell from `~/src/caelestia-shell` so later tasks' QML changes take effect on `home-manager switch`.

- [ ] **Step 1: Confirm clone is clean & current**

Run: `git -C ~/src/caelestia-shell fetch origin && git -C ~/src/caelestia-shell status -sb`
Expected: on a branch tracking origin, working tree clean.

- [ ] **Step 2: Point the flake input at the clone**

In `~/dotfiles/flake.nix`, change:
```nix
caelestia.url = "github:caelestia-dots/shell";
```
to:
```nix
caelestia.url = "git+file:///home/devsupreme/src/caelestia-shell";
```
(`git+file` respects committed state — commit clone changes to test them. Use `path:` only if you prefer dirty-tree builds.)

- [ ] **Step 3: Rebuild**

Run: `nix flake lock ~/dotfiles --update-input caelestia && home-manager switch --flake ~/dotfiles`
Expected: builds; caelestia-shell restarts; bar/desktop look identical (no behavior change yet).

- [ ] **Step 4: Commit**

```bash
git -C ~/dotfiles add flake.nix flake.lock
git -C ~/dotfiles commit -m "build(caelestia): source shell from local fork (~/src/caelestia-shell)"
```

---

### Task 2: Pure logic helpers (`logic.js`) — TDD with node

**Files:**
- Create: `~/src/caelestia-shell/modules/clipboard/logic.js`
- Test: `~/src/caelestia-shell/modules/clipboard/logic.test.mjs`

**Interfaces:**
- Produces (QML-JS-safe, no node APIs in exported fns):
  - `parseList(text) -> [{id:string, raw:string, preview:string}]` (splits `cliphist list` output on first tab)
  - `detectType(preview) -> "image"|"link"|"color"|"code"|"text"`
  - `relTime(unixSeconds, nowSeconds) -> string` (e.g. `"2m ago"`, `"just now"`)
  - `fuzzy(query, items, keyFn) -> filtered items` (case-insensitive subsequence)

- [ ] **Step 1: Write the failing test**

`logic.test.mjs`:
```js
import assert from "node:assert/strict";
import { test } from "node:test";
import { parseList, detectType, relTime, fuzzy } from "./logic.js";

test("parseList splits id and preview on first tab", () => {
  const out = parseList("12\thello world\n11\tbinary data image/png\n");
  assert.deepEqual(out, [
    { id: "12", raw: "12\thello world", preview: "hello world" },
    { id: "11", raw: "11\tbinary data image/png", preview: "binary data image/png" },
  ]);
});
test("parseList ignores blank lines", () => {
  assert.equal(parseList("\n\n").length, 0);
});
test("detectType classifies", () => {
  assert.equal(detectType("binary data image/png"), "image");
  assert.equal(detectType("https://example.com/x"), "link");
  assert.equal(detectType("#1e90ff"), "color");
  assert.equal(detectType("1e90ff"), "color");
  assert.equal(detectType("const x = () => 1"), "code");
  assert.equal(detectType("just a note"), "text");
});
test("relTime formats", () => {
  assert.equal(relTime(1000, 1000), "just now");
  assert.equal(relTime(1000, 1000 + 120), "2m ago");
  assert.equal(relTime(1000, 1000 + 7200), "2h ago");
});
test("fuzzy subsequence, case-insensitive", () => {
  const items = [{ p: "Hello World" }, { p: "goodbye" }];
  assert.deepEqual(fuzzy("hlo", items, (i) => i.p), [{ p: "Hello World" }]);
  assert.deepEqual(fuzzy("", items, (i) => i.p), items);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ~/src/caelestia-shell/modules/clipboard && node --test`
Expected: FAIL (`Cannot find module './logic.js'`).

- [ ] **Step 3: Implement `logic.js`**

```js
.pragma library  // QML: safe to import as a shared JS library

function parseList(text) {
  const out = [];
  for (const line of String(text).split("\n")) {
    if (!line) continue;
    const tab = line.indexOf("\t");
    if (tab < 0) continue;
    out.push({ id: line.slice(0, tab), raw: line, preview: line.slice(tab + 1) });
  }
  return out;
}
function detectType(preview) {
  const p = String(preview);
  if (/^binary data image\//.test(p)) return "image";
  if (/^https?:\/\/\S+$/.test(p.trim())) return "link";
  if (/^#?[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$/.test(p.trim())) return "color";
  if (/[;{}=]|=>|\bfunction\b|\bconst\b|\bdef\b/.test(p)) return "code";
  return "text";
}
function relTime(t, now) {
  const d = Math.max(0, Math.floor(now - t));
  if (d < 45) return "just now";
  if (d < 3600) return Math.round(d / 60) + "m ago";
  if (d < 86400) return Math.round(d / 3600) + "h ago";
  return Math.round(d / 86400) + "d ago";
}
function fuzzy(query, items, keyFn) {
  const q = String(query).toLowerCase();
  if (!q) return items;
  return items.filter((it) => {
    const s = String(keyFn(it)).toLowerCase();
    let i = 0;
    for (const ch of s) if (ch === q[i]) i++;
    return i === q.length;
  });
}
export { parseList, detectType, relTime, fuzzy };
```
Note: `.pragma library` + `export` both work — QML imports via `import "logic.js" as Logic`; node imports via ESM. (If the toolchain rejects mixing, duplicate exports as `var Logic = {...}`; verify in Step 4.)

- [ ] **Step 4: Run tests to verify pass**

Run: `cd ~/src/caelestia-shell/modules/clipboard && node --test`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git -C ~/src/caelestia-shell add modules/clipboard/logic.js modules/clipboard/logic.test.mjs
git -C ~/src/caelestia-shell commit -m "feat(clipboard): pure logic helpers + node tests"
```

---

### Task 3: `Cliphist` service (list/decode/copy/delete/wipe)

**Files:**
- Create: `~/src/caelestia-shell/services/Cliphist.qml`

**Interfaces:**
- Consumes: `logic.js` `parseList`.
- Produces (Singleton): `property var entries` (array of `{id,raw,preview}`); `function refresh()`; `function copy(raw)`; `function decodeText(raw, cb)`; `function decodeImage(raw, path, cb)`; `function remove(raw)`; `function wipe()`.

- [ ] **Step 1: Implement the service (mirror `services/Network.qml` Process usage)**

```qml
pragma Singleton
import Quickshell
import Quickshell.Io
import "../modules/clipboard/logic.js" as Logic

Singleton {
    id: root
    property var entries: []

    function refresh() { listProc.running = true }
    function copy(raw) { run(["cliphist","decode"], raw, () => {}, true) }   // pipes decoded -> wl-copy (see run)
    function remove(raw) { runDrop(["cliphist","delete"], raw) ; refresh() }
    function wipe() { wipeProc.running = true ; entries = [] }

    // Generic: feed `raw` on stdin to argv; optionally pipe stdout to wl-copy.
    function run(argv, raw, cb, toClipboard) {
        const cmd = toClipboard
          ? ["sh","-c","printf '%s' \"$1\" | " + argv.join(" ") + " | wl-copy","sh",raw]
          : ["sh","-c","printf '%s' \"$1\" | " + argv.join(" "),"sh",raw];
        const p = drainComp.createObject(root, { command: cmd, _cb: cb });
        p.running = true;
    }
    function runDrop(argv, raw) { run(argv, raw, () => {}, false) }

    function decodeText(raw, cb) {
        const p = textComp.createObject(root, { command:
          ["sh","-c","printf '%s' \"$1\" | cliphist decode","sh",raw], _cb: cb });
        p.running = true;
    }
    function decodeImage(raw, path, cb) {
        const p = drainComp.createObject(root, { command:
          ["sh","-c","printf '%s' \"$1\" | cliphist decode > \"$2\"","sh",raw,path], _cb: () => cb(path) });
        p.running = true;
    }

    Process { id: listProc; command: ["cliphist","list"]
        stdout: StdioCollector { onStreamFinished: root.entries = Logic.parseList(text) } }
    Process { id: wipeProc; command: ["cliphist","wipe"] }

    Component { id: drainComp; Process { property var _cb
        onExited: { _cb(); destroy() } } }
    Component { id: textComp; Process { property var _cb
        stdout: StdioCollector { onStreamFinished: { _cb(text); } }
        onExited: destroy() } }

    Component.onCompleted: refresh()
}
```

- [ ] **Step 2: Register the singleton**

Confirm caelestia's `services/qmldir` lists singletons; add the line (match existing format, e.g. `singleton Cliphist 1.0 Cliphist.qml` or the project's `qmldir` convention).
Run: `grep -n "Network" ~/src/caelestia-shell/services/qmldir` to copy the exact pattern, then add the `Cliphist` line the same way.

- [ ] **Step 3: Build + smoke test**

Run: `git -C ~/src/caelestia-shell add -A && git -C ~/src/caelestia-shell commit -m "wip" && home-manager switch --flake ~/dotfiles`
Then: `caelestia-shell ipc call ... ` is not wired yet; verify no QML errors: `journalctl --user -e 2>/dev/null | grep -i caelestia | tail` OR run `qs -p ~/src/caelestia-shell -n` style lint if available. Expected: shell starts, no `Cliphist.qml` errors.

- [ ] **Step 4: Commit**

```bash
git -C ~/src/caelestia-shell add services/Cliphist.qml services/qmldir
git -C ~/src/caelestia-shell commit -m "feat(clipboard): Cliphist service (list/decode/copy/delete/wipe)"
```

---

### Task 4: `ClipPins` + `ClipMeta` services (JSON via FileView)

**Files:**
- Create: `~/src/caelestia-shell/services/ClipPins.qml`, `~/src/caelestia-shell/services/ClipMeta.qml`

**Interfaces:**
- `ClipPins` (Singleton): `property var pins` (array of `{raw, preview}`); `function toggle(raw, preview)`; `function isPinned(raw) -> bool`. Persists to `~/.local/state/caelestia/clip-pins.json`.
- `ClipMeta` (Singleton): `function lookup(md5) -> {ts, app}|null`. Reads `~/.local/state/caelestia/clip-meta.json`.

- [ ] **Step 1: Implement `ClipPins.qml` (mirror a FileView-using service)**

```qml
pragma Singleton
import Quickshell
import Quickshell.Io
Singleton {
    id: root
    property var pins: []
    readonly property string path: Quickshell.env("HOME") + "/.local/state/caelestia/clip-pins.json"
    function isPinned(raw) { return pins.some(p => p.raw === raw) }
    function toggle(raw, preview) {
        pins = isPinned(raw) ? pins.filter(p => p.raw !== raw) : [{raw, preview}, ...pins];
        view.setText(JSON.stringify(pins));
    }
    FileView { id: view; path: root.path
        onLoaded: { try { root.pins = JSON.parse(text() || "[]") } catch (e) { root.pins = [] } }
        onLoadFailed: root.pins = [] }
}
```

- [ ] **Step 2: Implement `ClipMeta.qml`**

```qml
pragma Singleton
import Quickshell
import Quickshell.Io
Singleton {
    id: root
    property var map: ({})
    readonly property string path: Quickshell.env("HOME") + "/.local/state/caelestia/clip-meta.json"
    function lookup(md5) { return root.map[md5] || null }
    FileView { path: root.path; watchChanges: true
        onLoaded: { try { root.map = JSON.parse(text() || "{}") } catch (e) { root.map = ({}) } }
        onLoadFailed: root.map = ({}) }
}
```

- [ ] **Step 3: Register both in `services/qmldir`** (same pattern as Task 3 Step 2).

- [ ] **Step 4: Build + verify no QML errors** (as Task 3 Step 3), then commit:

```bash
git -C ~/src/caelestia-shell add services/ClipPins.qml services/ClipMeta.qml services/qmldir
git -C ~/src/caelestia-shell commit -m "feat(clipboard): ClipPins + ClipMeta JSON services"
```

---

### Task 5: Metadata recorder sidecar (bash + hypr watchers)

**Files:**
- Create: `~/.config/caelestia/scripts/clip-meta-record.sh` (+ chezmoi source `~/ubuntu-dots/private_dot_config/caelestia/scripts/executable_clip-meta-record.sh`)
- Modify: `~/.config/hypr/hyprland.lua` (add two watcher exec_cmds near the existing cliphist ones, lines ~123-124)

**Interfaces:**
- Produces: `~/.local/state/caelestia/clip-meta.json` mapping `md5(content) -> {ts, app}`, consumed by `ClipMeta`.

- [ ] **Step 1: Write the recorder**

```bash
#!/usr/bin/env bash
# Reads clipboard content on stdin; records {ts, app} keyed by md5(content).
set -euo pipefail
state="$HOME/.local/state/caelestia"; mkdir -p "$state"
db="$state/clip-meta.json"; [ -s "$db" ] || echo '{}' > "$db"
tmp=$(mktemp)
md5=$(md5sum | awk '{print $1}')        # stdin -> md5
ts=$(date +%s)
app=$(hyprctl activewindow -j 2>/dev/null | jq -r '.class // "unknown"')
jq --arg k "$md5" --argjson v "{\"ts\":$ts,\"app\":\"$app\"}" '.[$k]=$v' "$db" > "$tmp" && mv "$tmp" "$db"
```

- [ ] **Step 2: Install (live + chezmoi) and validate**

Save the Step 1 script to `/tmp/clip-meta-record.sh`, then:
```bash
bash -n /tmp/clip-meta-record.sh && echo "syntax OK"
install -Dm755 /tmp/clip-meta-record.sh ~/.config/caelestia/scripts/clip-meta-record.sh
install -Dm755 /tmp/clip-meta-record.sh ~/ubuntu-dots/private_dot_config/caelestia/scripts/executable_clip-meta-record.sh
```

- [ ] **Step 3: Add watchers to `hyprland.lua`** (after the existing cliphist `exec_cmd` lines):

```lua
hl.exec_cmd("wl-paste --type text  --watch ~/.config/caelestia/scripts/clip-meta-record.sh")
hl.exec_cmd("wl-paste --type image --watch ~/.config/caelestia/scripts/clip-meta-record.sh")
```

- [ ] **Step 4: Verify end-to-end**

Run: `hyprctl reload`, then `wl-copy "meta-test-$(date +%s)"`, then
`md5=$(printf '%s' "meta-test-..." | md5sum | awk '{print $1}'); jq --arg k "$md5" '.[$k]' ~/.local/state/caelestia/clip-meta.json`
Expected: a `{ts, app}` object.

- [ ] **Step 5: Commit** (dotfiles + ubuntu-dots):
```bash
git -C ~/ubuntu-dots add private_dot_config/caelestia/scripts/executable_clip-meta-record.sh
git -C ~/ubuntu-dots commit -m "feat(clipboard): clipboard metadata recorder (app+ts sidecar)"
# hyprland.lua: commit in whichever repo manages it (chezmoi/ubuntu-dots)
```

---

### Task 6: Clipboard overlay window + IPC (`Clipboard.qml`)

**Files:**
- Create: `~/src/caelestia-shell/modules/clipboard/Clipboard.qml`
- Modify: `~/src/caelestia-shell/shell.qml` (add `import "modules/clipboard"` + `Clipboard {}`)

**Interfaces:**
- Consumes: `Cliphist.refresh()`.
- Produces: IPC `caelestia-shell ipc call clipboard open` toggles a centered overlay; exposes `property bool closing`.

- [ ] **Step 1: Implement the overlay scaffold (mirror `modules/areapicker/AreaPicker.qml`)**

```qml
pragma ComponentBehavior: Bound
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.components.containers
import qs.services
Scope {
    LazyLoader {
        id: root
        property bool closing
        Variants {
            model: Screens.screens
            StyledWindow {
                required property ShellScreen modelData
                screen: modelData
                name: "clipboard"
                WlrLayershell.exclusionMode: ExclusionMode.Ignore
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.keyboardFocus: root.closing ? WlrKeyboardFocus.None : WlrKeyboardFocus.Exclusive
                anchors.top: true; anchors.bottom: true; anchors.left: true; anchors.right: true
                ClipboardContent {              // Task 7
                    loader: root
                    onRequestClose: { root.closing = true; root.activeAsync = false }
                }
            }
        }
    }
    IpcHandler {
        target: "clipboard"
        function open(): void { root.closing = false; Cliphist.refresh(); root.activeAsync = true }
        function toggle(): void { root.activeAsync ? (root.closing = true, root.activeAsync = false) : open() }
    }
}
```
(If `ClipboardContent` isn't built yet, temporarily use an empty `Item { anchors.fill: parent }` so this task is independently testable.)

- [ ] **Step 2: Register in `shell.qml`**

Add `import "modules/clipboard"` next to the other module imports (line ~10) and `Clipboard {}` next to `AreaPicker {}` (line ~21).

- [ ] **Step 3: Build + verify IPC opens an overlay**

Run: `git -C ~/src/caelestia-shell add -A && git commit -m wip && home-manager switch --flake ~/dotfiles`
Then: `caelestia-shell ipc call clipboard open`
Expected: a fullscreen overlay layer appears (empty placeholder), grabs keyboard; `caelestia-shell ipc call clipboard toggle` closes it.

- [ ] **Step 4: Commit**

```bash
git -C ~/src/caelestia-shell add modules/clipboard/Clipboard.qml shell.qml
git -C ~/src/caelestia-shell commit -m "feat(clipboard): overlay window + IPC (target=clipboard)"
```

---

### Task 7: Overlay UI — search, filter tabs, list, keyboard nav (`ClipboardContent.qml`)

**Files:**
- Create: `~/src/caelestia-shell/modules/clipboard/ClipboardContent.qml`, `modules/clipboard/ClipList.qml`

**Interfaces:**
- Consumes: `Cliphist.entries`, `ClipPins.pins`, `logic.js` `fuzzy`/`detectType`.
- Produces: `signal requestClose()`; selection model the actions task (Task 9) consumes via `property var current`.

- [ ] **Step 1: Implement the centered panel** (a `StyledRect` card centered in the overlay; dim backdrop `MouseArea` → `requestClose`; `StyledTextField` search bound to a `query`; a `Row` of filter chips `All/Text/Img/Link`; a `ClipList` showing `fuzzy(query, merged(pins, Cliphist.entries))` filtered by the active type via `detectType`). Use `Colours.palette.*` for surfaces/text (mirror colours in `modules/launcher/`). Card width ~min(900, 70%), two columns: list (left ~55%) + a `Loader` placeholder for the preview (right) — preview implemented in Task 8.

Provide the full QML here:
```qml
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.components
import qs.components.containers
import qs.components.controls
import qs.services
import "logic.js" as Logic
Item {
    id: root
    required property var loader
    signal requestClose()
    property string query: ""
    property string filter: "all"
    property var model: filterModel()
    property int index: 0
    property var current: model.length ? model[index] : null

    function merged() {
        const pins = ClipPins.pins.map(p => ({ ...p, pinned: true }));
        const hist = Cliphist.entries.filter(e => !ClipPins.isPinned(e.raw));
        return pins.concat(hist);
    }
    function filterModel() {
        let m = merged();
        if (filter !== "all") m = m.filter(e => {
            const t = Logic.detectType(e.preview);
            return filter === t || (filter === "text" && t === "code");
        });
        return Logic.fuzzy(query, m, e => e.preview);
    }
    onQueryChanged: { model = filterModel(); index = 0 }
    onFilterChanged: { model = filterModel(); index = 0 }
    Connections { target: Cliphist; function onEntriesChanged() { root.model = root.filterModel() } }

    anchors.fill: parent
    MouseArea { anchors.fill: parent; onClicked: root.requestClose() }   // backdrop

    StyledRect {
        anchors.centerIn: parent
        width: Math.min(900, parent.width * 0.7); height: parent.height * 0.7
        radius: Appearance.rounding.large            // mirror existing usage if name differs
        color: Colours.palette.m3surface
        MouseArea { anchors.fill: parent }           // swallow backdrop clicks
        ColumnLayout {
            anchors.fill: parent; anchors.margins: 16; spacing: 12
            StyledTextField {
                id: search; Layout.fillWidth: true; focus: true
                placeholderText: "Search clipboard…"
                onTextChanged: root.query = text
                Keys.onDownPressed: root.index = Math.min(root.index + 1, root.model.length - 1)
                Keys.onUpPressed: root.index = Math.max(root.index - 1, 0)
                Keys.onEscapePressed: root.requestClose()
                Keys.onReturnPressed: { if (root.current) { Cliphist.copy(root.current.raw); root.requestClose() } }
            }
            Row { spacing: 8
                Repeater { model: ["all","text","image","link"]
                    TextButton { text: modelData; onClicked: root.filter = modelData
                        // visually mark active when modelData === root.filter (mirror ToggleButton)
                    } } }
            ClipList { Layout.fillWidth: true; Layout.fillHeight: true
                entries: root.model; currentIndex: root.index
                onActivated: i => { root.index = i; Cliphist.copy(root.model[i].raw); root.requestClose() } }
        }
    }
}
```
`ClipList.qml`: a `StyledListView` over `entries` with `currentIndex`, emitting `signal activated(int i)` on click/Enter; delegate is `ClipEntry` (Task 8). Keep selection synced to `currentIndex`.

- [ ] **Step 2: Build + verify**

`home-manager switch …`; `caelestia-shell ipc call clipboard open`.
Expected: centered card; your cliphist entries listed; typing filters; ↑/↓ moves selection; Enter copies + closes; Esc closes; filter chips narrow by type. (Verify a known entry: copy "abc", reopen, search "abc", Enter, then `wl-paste` → "abc".)

- [ ] **Step 3: Commit**
```bash
git -C ~/src/caelestia-shell add modules/clipboard/ClipboardContent.qml modules/clipboard/ClipList.qml
git -C ~/src/caelestia-shell commit -m "feat(clipboard): overlay UI — search, filters, list, keyboard nav"
```

---

### Task 8: Entry rendering + preview pane + smart detection + meta

**Files:**
- Create: `~/src/caelestia-shell/modules/clipboard/ClipEntry.qml`, `modules/clipboard/ClipPreview.qml`
- Modify: `modules/clipboard/ClipboardContent.qml` (mount `ClipPreview` in the right column, bound to `current`)

**Interfaces:**
- Consumes: `Cliphist.decodeText/decodeImage`, `ClipMeta.lookup`, `logic.js` `detectType`/`relTime`, `Time` service (for "now") if present.

- [ ] **Step 1: `ClipEntry.qml` — type-aware row**

Per `detectType(preview)`: text → `StyledText` first line (elide); code → same in monospace; image → small `Image` thumbnail decoded via `Cliphist.decodeImage(raw, "/tmp/clip-thumb-"+id+".png", cb)` (cache by id; lazy in `Component.onCompleted`); link → `MaterialIcon` link glyph + text; color → a `StyledRect` swatch (`color: "#"+preview.replace('#','')`) + label. Pinned rows show a pin `MaterialIcon`. Highlight when `index === ListView.view.currentIndex` using `Colours.palette.*`.

- [ ] **Step 2: `ClipPreview.qml` — right pane bound to `current`**

On `current` change: if image → `decodeImage` to `/tmp/clip-preview.png` → `Image`; else `decodeText(raw, t => previewText = t)` → scrollable `StyledText` (monospace if code; color swatch if color). Footer line: compute `Qt.md5(previewText)`, `const m = ClipMeta.lookup(md5)`, show `m ? (m.app + " · " + Logic.relTime(m.ts, now)) : ""`. Truncate preview text > 100 000 chars with a notice.

- [ ] **Step 3: Mount preview** in `ClipboardContent` right column (replace the Task 7 placeholder `Loader`): `ClipPreview { entry: root.current }`.

- [ ] **Step 4: Build + verify**

Expected: text entries show full preview + (for newly-copied) `src: <app> · <time>`; image entries show a thumbnail in the list and full image in preview; a `#1e90ff` entry shows a colour swatch; a URL shows the link glyph.

- [ ] **Step 5: Commit**
```bash
git -C ~/src/caelestia-shell add modules/clipboard/ClipEntry.qml modules/clipboard/ClipPreview.qml modules/clipboard/ClipboardContent.qml
git -C ~/src/caelestia-shell commit -m "feat(clipboard): entry rendering, preview pane, smart-detect, meta"
```

---

### Task 9: Actions — pin, delete, wipe, paste-as-plain, quick-pick, URL open

**Files:**
- Modify: `modules/clipboard/ClipboardContent.qml` (key handlers), `modules/clipboard/ClipEntry.qml` (per-row affordances)

**Interfaces:**
- Consumes: `ClipPins.toggle`, `Cliphist.remove/wipe/copy`, `Quickshell.execDetached` (or a `Process`) for `xdg-open`.

- [ ] **Step 1: Add key handlers** on the search field (so they work while typing-to-search uses plain chars; use modifiers/function keys to avoid clobbering search):
  - `Shift+Return` → copy as plain text: `Cliphist.copy(current.raw)` then also strip rich types — for v1, same as copy (cliphist stores text already); document limitation.
  - `Ctrl+P` → `ClipPins.toggle(current.raw, current.preview)`.
  - `Ctrl+D` / `Delete` → `Cliphist.remove(current.raw)`.
  - `Ctrl+Shift+Delete` → `Cliphist.wipe()`.
  - `Ctrl+1..9` → copy the Nth visible entry + close.
  - `Ctrl+O` → if `detectType(current.preview)==="link"` then open: `Quickshell.execDetached(["xdg-open", current.preview.trim()])`.

(Chosen Ctrl-modified keys so bare typing still drives fuzzy search. Update the footer hint text accordingly.)

- [ ] **Step 2: Build + verify each action**

Pin an entry → it jumps to top + persists across reopen (`cat ~/.local/state/caelestia/clip-pins.json`). Delete → entry gone from list + `cliphist list`. `Ctrl+Shift+Del` → history emptied. `Ctrl+O` on a URL opens the browser.

- [ ] **Step 3: Commit**
```bash
git -C ~/src/caelestia-shell add modules/clipboard/ClipboardContent.qml modules/clipboard/ClipEntry.qml
git -C ~/src/caelestia-shell commit -m "feat(clipboard): pin/delete/wipe/plain/quick-pick/open actions"
```

---

### Task 10: Migration — bind Super+C, retire greenclip + rofi-clipboard.sh

**Files:**
- Modify: `~/.config/hypr/hyprland.lua` (line 144 bind) + chezmoi source
- Modify: chezmoi: remove `rofi-clipboard.sh`; remove greenclip autostart
- Delete (live): stop greenclip daemon

**Interfaces:** none (final wiring).

- [ ] **Step 1: Rebind Super+C**

In `hyprland.lua`, change line ~144 from
`hl.bind(mod .. " + C", hl.dsp.exec_cmd(rofi .. "/rofi-clipboard.sh"))`
to
`hl.bind(mod .. " + C", hl.dsp.exec_cmd("caelestia-shell ipc call clipboard open"))`
Run: `hyprctl reload`.

- [ ] **Step 2: Verify Super+C opens the native overlay** (not rofi). Copy something, `Super+C`, search, Enter, paste — confirm.

- [ ] **Step 3: Retire greenclip**

```bash
pkill -x greenclip || true
grep -rn greenclip ~/.config/hypr ~/ubuntu-dots 2>/dev/null   # find autostart
# remove the greenclip autostart line(s); remove rofi-clipboard.sh from chezmoi:
git -C ~/ubuntu-dots rm private_dot_config/rofi/scripts/executable_rofi-clipboard.sh
```
Leave the cliphist `wl-paste --watch cliphist store` lines intact.

- [ ] **Step 4: Verify clean state**

`pgrep -x greenclip` → nothing. `Super+C` works. `Print` (grim stopgap) still works. cliphist watchers + meta watchers running (`pgrep -af wl-paste`).

- [ ] **Step 5: Commit + open PRs**

```bash
git -C ~/ubuntu-dots add -A && git -C ~/ubuntu-dots commit -m "chore(clipboard): retire greenclip + rofi-clipboard.sh; add meta watcher; bind Super+C to caelestia"
git -C ~/src/caelestia-shell push -u <fork> HEAD   # backup the fork
# Optionally PR the dotfiles branch; caelestia fork stays local/backup.
```

---

## Self-review notes (author)
- Spec coverage: §3 fork wiring=Task1; §3.3 overlay=Task6; §3.4 IPC/keybind/retire=Task6/10; §4 UX=Task7/8/9; §5 components/services=Task3/4/6/7/8; §6 sidecar=Task5; §7 error handling folded into Task3/4/8 (empty/corrupt JSON, decode failure, truncate); §8 perf=lazy decode (Task3/8) + virtualized StyledListView (Task7); §9 migration=Task10 (+ grim stopgap already done); §10 testing=Task2 (logic) + manual verifies per task.
- Known soft spots to resolve during impl (read the referenced caelestia files): exact `Colours.palette.*` keys + `Appearance.rounding.*` names (mirror `modules/launcher`), `services/qmldir` singleton syntax (Task3 Step2), `StyledTextField`/`StyledListView` property names, `Quickshell.execDetached` vs `Process` for `xdg-open`, and whether `.pragma library` coexists with ESM `export` (Task2 Step3 fallback noted).
