pragma Singleton
import QtQuick
import qs.modules.theme

// The ONLY file in the overview that names Theme.*. Everything else reads Look.*,
// so a change in how T2 exposes tokens is a one-file fix. Values come from
// tokens.json via Theme; the overview never reads palette.yaml or calls matugen.
QtObject {
    id: look

    // colour roles
    readonly property color surface: Theme.color.surface
    readonly property color surfaceHigh: Theme.color.surfaceContainerHigh
    readonly property color outline: Theme.color.outline
    readonly property color fg: Theme.color.fg
    readonly property color fgDim: Theme.color.fgDim
    readonly property color fgFaint: Theme.color.fgFaint
    readonly property color accent: Theme.color.accent
    readonly property color accentFg: Theme.color.accentFg
    readonly property color amber: Theme.color.amber      // someone waits on me
    readonly property color red: Theme.color.red          // failed, nobody waits

    // alpha
    readonly property real aPanel: Theme.alpha.panel
    readonly property real aWash: Theme.alpha.wash
    readonly property real aHover: Theme.alpha.hover
    readonly property real aDivider: Theme.alpha.divider
    // pressed overlay on a Button. Key name `pressed` is agreed with T2 (alpha.pressed in
    // tokens.json); until the real Theme carries it, hover*1.8 keeps the step visible.
    readonly property real aPressed: Theme.alpha.pressed !== undefined ? Theme.alpha.pressed : Theme.alpha.hover * 1.8
    // the unlit track behind an accent fill (progress bar, focus ring): one value,
    // not one per part. Not a tokens.json key; it lives here with the other fixed ones.
    readonly property real aTrack: 0.12

    // radius and spacing
    readonly property int rChip: Theme.radius.chip
    readonly property int rPanel: Theme.radius.panel
    readonly property int rCard: Theme.radius.card
    readonly property int rPill: Theme.radius.pill
    readonly property int sXs: Theme.space.xs
    readonly property int sS: Theme.space.s
    readonly property int sM: Theme.space.m
    readonly property int sL: Theme.space.l
    readonly property int sXl: Theme.space.xl
    readonly property int sXxl: Theme.space.xxl
    readonly property int sXxxl: Theme.space.xxxl

    // type
    readonly property string sans: Theme.font.sans
    readonly property string mono: Theme.font.mono
    readonly property string iconFont: Theme.font.icon
    readonly property int fCaption: Theme.font.size.caption
    readonly property int fBodyS: Theme.font.size.bodyS
    readonly property int fBody: Theme.font.size.body
    readonly property int fTitle: Theme.font.size.title
    readonly property int fHeadline: Theme.font.size.headline
    readonly property int fDisplay: Theme.font.size.display

    // motion. The curves are tokens too: never Easing.* at a call site.
    readonly property int mFast: Theme.motion.fast
    readonly property int mBase: Theme.motion.base
    readonly property int mSlow: Theme.motion.slow
    readonly property int easeIn: Theme.motion.easeIn
    readonly property int easeOut: Theme.motion.easeOut

    // bar. chipHeight matches the wash plate T2's bar/Chip.qml draws (slab height
    // inset by space.s top and bottom), so a pill badge and an Ops chip line up.
    readonly property int barHeight: Theme.bar.height
    readonly property int chipHeight: look.barHeight - look.sS * 2

    // fixed by the spec's pixel table, not by tokens
    readonly property int cardWidth: 380
    readonly property int cardMaxHeight: 520
    readonly property int notchW: 8
    readonly property int notchH: 4
    readonly property int panelWidth: 920
    readonly property int panelHeight: 640
    readonly property int cell: 11
    readonly property int cellGap: 3
    readonly property int rCell: 2          // heatmap cell and progress-bar track
    readonly property int iconSize: look.fTitle  // every Material Symbol in the overview
    readonly property int heatCols: 17
    readonly property int heatRows: 7
    readonly property int ringDiameter: 20
    readonly property int ringStroke: 2
    readonly property var heatRamp: [0, 0.12, 0.30, 0.52, 0.80]

    function withAlpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }
    function wash(c) { return look.withAlpha(c, look.aWash) }
    // text that sits on a wash of its own tone: the tone lifted 45 % toward fg, so red
    // and amber labels clear WCAG AA (4.5:1) on their chip (plain red reads 3.2:1)
    function legible(c) { return Qt.tint(c, look.withAlpha(look.fg, 0.45)) }
}
