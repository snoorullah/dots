pragma Singleton
// Typed defaults, used while tokens.json is missing or unreadable. This is the same
// derivation `dots-theme preset` performs (tests/shell.sh proves the two agree by
// rendering the bar from each and comparing pixels).
import Quickshell

Singleton {
  function rgb(h) {
    return [parseInt(h.substr(1, 2), 16), parseInt(h.substr(3, 2), 16), parseInt(h.substr(5, 2), 16)];
  }
  function hex(c) {
    var s = "#";
    for (var i = 0; i < 3; i++) {
      var v = Math.max(0, Math.min(255, Math.round(c[i])));
      s += (v < 16 ? "0" : "") + v.toString(16);
    }
    return s;
  }
  // t of b over a, in sRGB
  function mix(a, b, t) {
    var x = rgb(a), y = rgb(b);
    return hex([x[0] + (y[0] - x[0]) * t, x[1] + (y[1] - x[1]) * t, x[2] + (y[2] - x[2]) * t]);
  }

  function build() {
    var bg = hex(rgb(Palette.bg));
    return {
      v: 1, source: "defaults", mode: "dark", wallpaper: null,
      color: {
        bg: bg,
        surface: mix(bg, "#ffffff", 0.04),
        surfaceDim: mix(bg, "#000000", 0.20),
        surfaceContainer: Palette.sel,
        surfaceContainerHigh: mix(Palette.sel, "#ffffff", 0.06),
        outline: Palette.comment,
        outlineVariant: mix(Palette.comment, bg, 0.50),
        fg: Palette.fg,
        fgDim: mix(Palette.comment, Palette.fg, 0.40),
        fgFaint: mix(bg, mix(Palette.comment, Palette.fg, 0.40), 0.70),
        accent: Palette.purple,
        accentFg: bg,
        amber: Palette.orange, red: Palette.red, green: Palette.green,
        purple: Palette.purple, pink: Palette.pink, cyan: Palette.cyan, yellow: Palette.yellow
      },
      alpha: { slab: 0.78, panel: 0.86, wash: 0.20, hover: 0.10, divider: 0.24, rest: 0.04, on: 0.16, pressed: 0.18 },
      radius: { chip: 8, panel: 16, card: 16, pill: 999 },
      space: { xs: 2, s: 4, m: 6, l: 8, xl: 12, xxl: 16, xxxl: 24 },
      font: { sans: "Lato", mono: "JetBrainsMono Nerd Font", icon: "Material Symbols Rounded",
              size: { caption: 11, bodyS: 12, body: 13, title: 16, headline: 20, display: 28 } },
      motion: { fast: 120, base: 180, slow: 240, easeIn: "OutExpo", easeOut: "OutCubic" },
      bar: { height: 30, gutter: 8, chipGapPx: 6 }
    };
  }
}
