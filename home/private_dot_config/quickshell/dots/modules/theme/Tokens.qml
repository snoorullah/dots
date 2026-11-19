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
    var ground = hex(rgb(Palette.ground));
    return {
      v: 1, source: "defaults", mode: "dark", wallpaper: null,
      color: {
        bg: ground,
        surface: hex(rgb(Palette.panel)),
        surfaceDim: mix(Palette.ground, "#000000", 0.20),
        surfaceContainer: hex(rgb(Palette.raised)),
        surfaceContainerHigh: mix(Palette.raised, "#ffffff", 0.06),
        outline: hex(rgb(Palette.border)),
        outlineVariant: hex(rgb(Palette.line)),
        fg: hex(rgb(Palette.text)),
        fgDim: hex(rgb(Palette.text_dim)),
        fgFaint: mix(Palette.ground, Palette.text_dim, 0.70),
        accent: hex(rgb(Palette.accent)),
        accentFg: hex(rgb(Palette.accent_fg)),
        waiting: hex(rgb(Palette.waiting)),
        failed: hex(rgb(Palette.failed)),
        unknown: hex(rgb(Palette.unknown))
      },
      alpha: { slab: 0.78, panel: 0.86, wash: 0.20, hover: 0.10, divider: 0.24, rest: 0.04, on: 0.16, pressed: 0.18 },
      radius: { chip: 6, row: 10, card: 14, panel: 14, pill: 999 },
      space: { xs: 4, s: 4, m: 8, l: 8, xl: 12, xxl: 16, xxxl: 24, xxxxl: 32 },
      font: { sans: "Bricolage Grotesque", mono: "JetBrains Mono", icon: "dots Icons",
              size: { caption: 12, bodyS: 13, body: 14, title: 16, headline: 20, page: 28, display: 40 },
              line: { caption: 16, bodyS: 18, body: 20, title: 24, headline: 28, page: 36, display: 48 },
              weight: { label: 600, body: 400, title: 600, page: 600, display: 500 },
              track: { label: 0.04 } },
      motion: { fast: 120, base: 180, slow: 180, fade: 240, easeIn: "OutExpo", easeOut: "OutCubic" },
      bar: { height: 30, gutter: 8, chipGapPx: 8 }
    };
  }
}
