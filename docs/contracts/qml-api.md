# QML contract between the shell and the overview UI

Spec version `1`. The shell (`qs-dots`) owns everything under
`home/private_dot_config/quickshell/dots/` except `modules/overview/`.
The overview track owns `modules/overview/` and nothing else.

---

## 1. Theme: `Theme.*`

Overview QML never reads `palette.yaml`, never calls matugen, and never opens
`tokens.json` itself. It imports the singleton.

```qml
import "../theme"        // from modules/overview/*.qml

Rectangle { color: Theme.color.surface; radius: Theme.radius.panel }
```

| group | members |
|---|---|
| `Theme.color` | `bg surface surfaceDim surfaceContainer surfaceContainerHigh outline outlineVariant fg fgDim fgFaint accent accentFg amber red green purple pink cyan yellow` |
| `Theme.alpha` | `slab panel wash hover divider rest on pressed` |
| `Theme.radius` | `chip panel card pill` |
| `Theme.space` | `xs s m l xl xxl xxxl` |
| `Theme.font` | `sans mono icon` and `size.{caption bodyS body title headline display}` |
| `Theme.motion` | `fast base slow` (ms), `easeIn easeOut` (`Easing.*` type) |
| `Theme.bar` | `height gutter chipGapPx` |

The shell repaints live: `Theme` watches `tokens.json`. Every member is a
property, so bindings update without a restart.

Shared building blocks the overview may use from `modules/common/`:
`Anim`, `Icon`, `DText` (not `Text`: that would shadow QtQuick's), `Surface`, `FocusGrab`,
`Stale`, `Popout`.

Import them by relative path. A directory holding singletons has a `qmldir`:

```qml
import "../theme"          // Theme
import "../common"         // Anim, Icon, DText, Surface, Stale ...
import "../../services"    // Attention, Lamp, Ui, Overview ...
```

Useful services: `Lamp.on` (true during the lamp test, so a surface can force itself
visible), `Attention` (the three numbers the pill gets), `Overview.host`.

---

## 2. What the shell loads from the overview

```qml
// modules/overview/OverviewPill.qml   lives in the bar's right slab
Item {
  property int  attnWaiting
  property int  attnFailed
  property bool stale
  property string screenName
  // implicitWidth / implicitHeight MUST be 0 when nominal
  signal cardRequested()
  signal panelRequested(string page)
}

// modules/overview/OverviewHost.qml   instantiated once in the shell root
Item {
  function toggleCard()
  function openPanel(page)      // today|week|attention|focus|heatmap
  function close()
  function lamp(int ms)
  property string anchorScreen
  property real   anchorX
  property real   anchorBottom
}
```

Both are loaded with `Loader { asynchronous: true }` guarded by a file-exists
probe, so the shell runs green before the overview lands.

The shell feeds the pill's `attnWaiting`, `attnFailed` and `stale` from
`attention.json`. If the overview wants to own that parsing it may ignore the
bound values and read its own `State.qml`; the properties stay for the contract.

---

## 3. IPC

`qs ipc call dots.<surface> <fn> [arg]`

| surface | registered by | functions |
|---|---|---|
| `bar` | shell | `reload`, `lamp` |
| `quick` | shell | `toggle` |
| `notif` | shell | `toggle`, `dnd` |
| `osd` | shell | `display <volume\|brightness>` (not `show`: the CLI treats `ipc call t show x` as its own subcommand) |
| `overview` | overview | `toggle`, `panel <page>`, `focus <start\|stop\|break>` |

`bar.lamp` forces every conditional chip visible for 1.2 s (amber and red
included) and calls `OverviewHost.lamp(1200)` when the host is present.

---

## 4. Layer namespaces (frozen)

`qs-bar`, `qs-notif`, `qs-osd`, `qs-panel`, `qs-overview`. Set with
`WlrLayershell.namespace`. Hyprland carries one blur rule per namespace.

---

## 5. Environment

| variable | meaning |
|---|---|
| `DOTS_THEME_TOKENS` | override path of `tokens.json` (tests) |
| `DOTS_OVERVIEW_STATE_DIR` | override of `~/.local/state/dots-overview` (tests) |
| `DOTS_OPS_STATE` | override of the dots-ops state file the Ops chip reads |
