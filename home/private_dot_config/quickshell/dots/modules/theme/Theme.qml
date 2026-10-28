pragma Singleton
// Theme.* is the only way any surface reads a colour, a size or a duration.
// It follows ~/.local/state/dots-theme/tokens.json live (the file is replaced
// atomically by dots-theme, so a change is a rename the FileView watches) and falls
// back to Tokens.build() when the file is missing, unreadable or not version 1.
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
  id: root

  readonly property string path: {
    var o = Quickshell.env("DOTS_THEME_TOKENS");
    if (o) return o;
    var st = Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state");
    return st + "/dots-theme/tokens.json";
  }

  property var tok: Tokens.build()
  readonly property string source: tok.source
  readonly property string wallpaper: tok.wallpaper ? tok.wallpaper : ""

  // shallow-per-group merge over the defaults: a token a newer dots-theme adds is ignored,
  // a token an older one lacks is filled, and a wrong type never reaches a binding
  function apply(text) {
    var d = Tokens.build();
    try {
      var p = JSON.parse(text);
      if (p.v !== 1) { root.tok = d; return; }
      var out = { v: 1, source: p.source || "preset", mode: "dark", wallpaper: p.wallpaper || null };
      for (var g in d) {
        if (typeof d[g] !== "object" || d[g] === null) continue;
        out[g] = {};
        for (var k in d[g]) {
          var pv = p[g] ? p[g][k] : undefined;
          if (typeof d[g][k] === "object" && d[g][k] !== null) {
            out[g][k] = {};
            for (var kk in d[g][k]) {
              var sv = (pv && typeof pv === "object") ? pv[kk] : undefined;
              out[g][k][kk] = (typeof sv === typeof d[g][k][kk]) ? sv : d[g][k][kk];
            }
          } else {
            out[g][k] = (typeof pv === typeof d[g][k]) ? pv : d[g][k];
          }
        }
      }
      root.tok = out;
    } catch (e) {
      console.log("Theme: unreadable tokens.json, using defaults");
      root.tok = d;
    }
  }

  // false while tokens.json does not exist yet; a watch cannot be placed on a missing file,
  // so the retry below is the ONLY polling in the theme, and it stops as soon as the file is there
  property bool fileOk: false

  FileView {
    id: file
    path: root.path
    watchChanges: true
    onFileChanged: reload()
    onLoaded: { root.fileOk = true; root.apply(text()); }
    onLoadFailed: { root.fileOk = false; root.tok = Tokens.build(); }
  }

  Timer {
    interval: 3000
    running: !root.fileOk
    repeat: true
    onTriggered: file.reload()
  }

  function ease(name) {
    var m = { OutExpo: Easing.OutExpo, OutCubic: Easing.OutCubic, OutQuad: Easing.OutQuad,
              InOutCubic: Easing.InOutCubic, Linear: Easing.Linear };
    return m[name] !== undefined ? m[name] : Easing.OutCubic;
  }

  // typed groups, so a typo in `Theme.color.foo` is a lint error rather than a blank colour
  component Colors: QtObject {
    property color bg
    property color surface
    property color surfaceDim
    property color surfaceContainer
    property color surfaceContainerHigh
    property color outline
    property color outlineVariant
    property color fg
    property color fgDim
    property color fgFaint
    property color accent
    property color accentFg
    property color amber
    property color red
    property color green
    property color purple
    property color pink
    property color cyan
    property color yellow
  }
  component Alphas: QtObject {
    property real slab
    property real panel
    property real wash
    property real hover
    property real divider
    property real rest
    property real on
    property real pressed
  }
  component Radii: QtObject {
    property int chip
    property int panel
    property int card
    property int pill
  }
  component Spaces: QtObject {
    property int xs
    property int s
    property int m
    property int l
    property int xl
    property int xxl
    property int xxxl
  }
  component FontSizes: QtObject {
    property int caption
    property int bodyS
    property int body
    property int title
    property int headline
    property int display
  }
  component Fonts: QtObject {
    property string sans
    property string mono
    property string icon
    property FontSizes size: FontSizes {}
  }
  component Motions: QtObject {
    property int fast
    property int base
    property int slow
    property int easeIn
    property int easeOut
  }
  component Bars: QtObject {
    property int height
    property int gutter
    property int chipGapPx
  }

  readonly property Colors color: Colors {
    bg: root.tok.color.bg
    surface: root.tok.color.surface
    surfaceDim: root.tok.color.surfaceDim
    surfaceContainer: root.tok.color.surfaceContainer
    surfaceContainerHigh: root.tok.color.surfaceContainerHigh
    outline: root.tok.color.outline
    outlineVariant: root.tok.color.outlineVariant
    fg: root.tok.color.fg
    fgDim: root.tok.color.fgDim
    fgFaint: root.tok.color.fgFaint
    accent: root.tok.color.accent
    accentFg: root.tok.color.accentFg
    amber: root.tok.color.amber
    red: root.tok.color.red
    green: root.tok.color.green
    purple: root.tok.color.purple
    pink: root.tok.color.pink
    cyan: root.tok.color.cyan
    yellow: root.tok.color.yellow
  }
  readonly property Alphas alpha: Alphas {
    slab: root.tok.alpha.slab
    panel: root.tok.alpha.panel
    wash: root.tok.alpha.wash
    hover: root.tok.alpha.hover
    divider: root.tok.alpha.divider
    rest: root.tok.alpha.rest
    on: root.tok.alpha.on
    pressed: root.tok.alpha.pressed
  }
  readonly property Radii radius: Radii {
    chip: root.tok.radius.chip
    panel: root.tok.radius.panel
    card: root.tok.radius.card
    pill: root.tok.radius.pill
  }
  readonly property Spaces space: Spaces {
    xs: root.tok.space.xs
    s: root.tok.space.s
    m: root.tok.space.m
    l: root.tok.space.l
    xl: root.tok.space.xl
    xxl: root.tok.space.xxl
    xxxl: root.tok.space.xxxl
  }
  readonly property Fonts font: Fonts {
    sans: root.tok.font.sans
    mono: root.tok.font.mono
    icon: root.tok.font.icon
    size: FontSizes {
      caption: root.tok.font.size.caption
      bodyS: root.tok.font.size.bodyS
      body: root.tok.font.size.body
      title: root.tok.font.size.title
      headline: root.tok.font.size.headline
      display: root.tok.font.size.display
    }
  }
  readonly property Motions motion: Motions {
    fast: root.tok.motion.fast
    base: root.tok.motion.base
    slow: root.tok.motion.slow
    easeIn: root.ease(root.tok.motion.easeIn)
    easeOut: root.ease(root.tok.motion.easeOut)
  }
  readonly property Bars bar: Bars {
    height: root.tok.bar.height
    gutter: root.tok.bar.gutter
    chipGapPx: root.tok.bar.chipGapPx
  }
}
