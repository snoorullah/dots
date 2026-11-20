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
        ground: "#0e1316", panel: "#151b1f", raised: "#1c2429", line: "#2a343a", border: "#3a474e",
        text: "#e7edf0", text_dim: "#a7b4bb", accent: "#8ccff1", accent_fg: "#0e1316",
        waiting: "#f2b04d", failed: "#ff8a7a", unknown: "#a7b4bb"
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
        return {
            bg: hex(rgb(P.ground)),
            surface: hex(rgb(P.panel)),
            surfaceDim: mix(P.ground, "#000000", 0.20),
            surfaceContainer: hex(rgb(P.raised)),
            surfaceContainerHigh: mix(P.raised, "#ffffff", 0.06),
            outline: hex(rgb(P.border)),
            outlineVariant: hex(rgb(P.line)),
            fg: hex(rgb(P.text)),
            fgDim: hex(rgb(P.text_dim)),
            fgFaint: mix(P.ground, P.text_dim, 0.70),
            accent: hex(rgb(P.accent)),
            accentFg: hex(rgb(P.accent_fg)),
            waiting: hex(rgb(P.waiting)), failed: hex(rgb(P.failed)), unknown: hex(rgb(P.unknown))
        }
    }

    readonly property var color: stub.derive(stub.palette)
    readonly property var alpha: ({ slab: 0.78, panel: 0.86, wash: 0.20, hover: 0.10, divider: 0.24, rest: 0.04, on: 0.16, pressed: 0.18 })
    readonly property var radius: ({ chip: 6, row: 10, card: 14, panel: 14, pill: 999 })
    readonly property var space: ({ xs: 4, s: 4, m: 8, l: 8, xl: 12, xxl: 16, xxxl: 24, xxxxl: 32 })
    readonly property var font: ({
        sans: "Bricolage Grotesque", mono: "JetBrains Mono", icon: "dots Icons",
        size: { caption: 12, bodyS: 13, body: 14, title: 16, headline: 20, page: 28, display: 40 },
        line: { caption: 16, bodyS: 18, body: 20, title: 24, headline: 28, page: 36, display: 48 },
        weight: { label: 600, body: 400, title: 600, page: 600, display: 500 },
        track: { label: 0.04 }
    })
    readonly property var motion: ({ fast: 120, base: 180, slow: 180, fade: 240,
                                 easeIn: Easing.OutExpo, easeOut: Easing.OutCubic })
    readonly property var bar: ({ height: 30, gutter: 8, chipGapPx: 8 })
}
