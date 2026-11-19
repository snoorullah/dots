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
| `Theme.color` | `bg surface surfaceDim surfaceContainer surfaceContainerHigh outline outlineVariant fg fgDim fgFaint accent accentFg waiting failed unknown` (status set: fixed in both modes, each with a shape) |
| `Theme.alpha` | `slab panel wash hover divider rest on pressed` |
| `Theme.radius` | `chip row panel card pill` (`panel == card`) |
| `Theme.space` | `xs s m l xl xxl xxxl xxxxl` (4 px grid) |
| `Theme.font` | `sans mono icon` and `size`, `line` (`{caption bodyS body title headline page display}`), `weight.{label body title page display}`, `track.label` (em) |
| `Theme.motion` | `fast base slow fade` (ms), `easeIn easeOut` (`Easing.*` type) |
| `Theme.bar` | `height gutter chipGapPx` |

Values (token contract v1):

| group | values |
|---|---|
| `radius` | chip 6, row 10, card 14, panel 14, pill 999 (one card radius, no `cardLarge`) |
| `space` | xs 4, s 4, m 8, l 8, xl 12, xxl 16, xxxl 24, xxxxl 32 (key names kept, rename is a later follow-up) |
| `font` | sans Bricolage Grotesque, mono JetBrains Mono, icon dots Icons |
| `font.size` | caption 12, bodyS 13, body 14, title 16, headline 20, page 28, display 40 |
| `font.line` | 16 / 18 / 20 / 24 / 28 / 36 / 48 in the same order |
| `font.weight` | label 600, body 400, title 600, page 600, display 500 |
| `font.track.label` | 0.04 em |
| `motion` | fast 120, base 180, slow 180, fade 240; easeIn `OutExpo`, easeOut `OutCubic` |
| `bar` | height 30, gutter 8, chipGapPx 8 |

Motion rule: a surface the user opens slides in at most 180 ms (`slow`).
Anything that arrives by itself fades over `fade` (240 ms).

Required tokens, by consumer state. Kept, not deleted.

No consumer yet (only an unused alias in `overview/Look.qml`, or none):

| token | consumer (phase 1+) |
|---|---|
| `radius.row` | list and attention rows in the overview card and panel |
| `color.surfaceDim` | panel backdrop behind the card and the quick panel |
| `color.surfaceContainerHigh` | hovered and raised rows, popout surfaces |
| `space.xxxxl` | panel outer padding |

Already consumed:

| token | consumers |
|---|---|
| `font.size.headline` | `osd/Osd.qml`, `media/MediaPopout.qml`, `common/DText.qml`, `overview/parts/Txt.qml` |
| `font.size.page`, `font.size.display` | `common/DText.qml`, `overview/parts/Txt.qml` |
| `font.line.*`, `font.weight.*`, `font.track.label` | `overview/parts/Txt.qml` via `Look` (not `DText`) |
| `motion.fade` | `osd/Osd.qml` (OSD opacity) |
| `color.unknown` | `common/StatusMark.qml` (the Phosphor `question` mark) |

Two palettes live outside the token set and never appear in `tokens.json`:
the waybar-only `palette.ctx` block (four context hues, never used for status) and
the `dots-theme` app-icon recolour ramp (its own hue list, icon recolour only).

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

`qs -c dots ipc call dots.<surface> <fn> [arg]`

| surface | registered by | functions |
|---|---|---|
| `bar` | shell | `reload`, `lamp` |
| `quick` | shell | `toggle` |
| `notif` | shell | `toggle`, `dnd` |
| `osd` | shell | `display <volume\|brightness>` (not `show`: the CLI treats `ipc call t show x` as its own subcommand) |
| `overview` | overview | `toggle`, `panel <page>`, `focus <start\|stop\|break>` |

`bar.lamp` forces every conditional chip visible for 5 s (waiting and failed
included) and calls `OverviewHost.lamp(5000)` when the host is present.

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
