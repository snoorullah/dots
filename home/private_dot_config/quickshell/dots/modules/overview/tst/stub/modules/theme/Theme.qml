pragma Singleton
import QtQuick

// TEST STUB of T2's modules/theme/Theme.qml. Same key names as tokens.json. The colours are
// DERIVED from the raw palette exactly as the real theme/Tokens.qml derives them (same mix(),
// same weights), so the overview renders with the colours it will ship with. The palette below
// is home/.chezmoidata/palette.yaml; tests/overview-ui.sh asserts both that it still matches
// the yaml and that this derivation agrees with the real Tokens.qml, key for key.
// Never shipped on its own.
QtObject {
    id: stub

    readonly property var palette: ({
        bg: "#282a36", fg: "#f8f8f2", sel: "#44475a", comment: "#6272a4", cyan: "#8be9fd",
        green: "#50fa7b", orange: "#ffb86c", pink: "#ff79c6", purple: "#bd93f9", red: "#ff5555",
        yellow: "#f1fa8c"
    })

    function rgb(h) {
        return [parseInt(h.substr(1, 2), 16), parseInt(h.substr(3, 2), 16), parseInt(h.substr(5, 2), 16)]
    }
    function hex(c) {
        var s = "#"
        for (var i = 0; i < 3; i++) {
            var v = Math.max(0, Math.min(255, Math.round(c[i])))
            s += (v < 16 ? "0" : "") + v.toString(16)
        }
        return s
    }
    // t of b over a, in sRGB
    function mix(a, b, t) {
        var x = rgb(a), y = rgb(b)
        return hex([x[0] + (y[0] - x[0]) * t, x[1] + (y[1] - x[1]) * t, x[2] + (y[2] - x[2]) * t])
    }
    function derive(P) {
        var bg = hex(rgb(P.bg))
        return {
            bg: bg,
            surface: mix(bg, "#ffffff", 0.04),
            surfaceDim: mix(bg, "#000000", 0.20),
            surfaceContainer: P.sel,
            surfaceContainerHigh: mix(P.sel, "#ffffff", 0.06),
            outline: P.comment,
            outlineVariant: mix(P.comment, bg, 0.50),
            fg: P.fg,
            fgDim: mix(P.comment, P.fg, 0.40),
            fgFaint: mix(bg, mix(P.comment, P.fg, 0.40), 0.70),
            accent: P.purple,
            accentFg: bg,
            amber: P.orange, red: P.red, green: P.green,
            purple: P.purple, pink: P.pink, cyan: P.cyan, yellow: P.yellow
        }
    }

    readonly property var color: stub.derive(stub.palette)
    readonly property var alpha: ({ slab: 0.78, panel: 0.86, wash: 0.20, hover: 0.10, divider: 0.24, rest: 0.04, on: 0.16, pressed: 0.18 })
    readonly property var radius: ({ chip: 8, panel: 16, card: 16, pill: 999 })
    readonly property var space: ({ xs: 2, s: 4, m: 6, l: 8, xl: 12, xxl: 16, xxxl: 24 })
    readonly property var font: ({
        sans: "Lato", mono: "JetBrainsMono Nerd Font", icon: "Material Symbols Rounded",
        size: { caption: 11, bodyS: 12, body: 13, title: 16, headline: 20, display: 28 }
    })
    readonly property var motion: ({ fast: 120, base: 180, slow: 240,
                                 easeIn: Easing.OutExpo, easeOut: Easing.OutCubic })
    readonly property var bar: ({ height: 30, gutter: 8, chipGapPx: 6 })
}
