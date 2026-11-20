import QtQuick
import Quickshell
import Quickshell.Io
import "modules/theme"
import "modules/common"
import "modules/session"
import "modules/session/js/Session.js" as S

// Test scene for tests/session-ui.sh, run with `quickshell -p <root>` on the offscreen Qt
// platform. Renders the REAL session components from fixture data, in the board's layout
// and one state per frame: one PNG and one `PROBE <tag> {json}` line per state, then quits.
ShellRoot {
    id: sc

    readonly property string outDir: Quickshell.env("OUT_DIR") || "/tmp"
    readonly property string fixture: Quickshell.env("FIXTURE") || ""
    property var fx: ({})
    property int step: -1
    property string picked: ""
    property string denied: ""
    property string sent: ""

    FileView {
        id: file
        path: sc.fixture
        blockLoading: true
        Component.onCompleted: { try { sc.fx = JSON.parse(file.text()) } catch (e) { console.log("FIXTURE ERROR " + e) } }
    }

    readonly property var plan: [
        { tag: "board-session", w: 1340, h: 840 },
        { tag: "away-near", w: 460, h: 520 },
        { tag: "away-far", w: 460, h: 520 },
        { tag: "away-select", w: 460, h: 520 },
        { tag: "session-idle", w: 420, h: 320 },
        { tag: "session-blocked", w: 420, h: 360 },
        { tag: "session-pending", w: 420, h: 360 },
        { tag: "polkit-idle", w: 500, h: 320 },
        { tag: "polkit-error", w: 500, h: 360 },
        { tag: "polkit-agent", w: 500, h: 360 },
        { tag: "return-declared", w: 800, h: 220 },
        { tag: "return-detected", w: 800, h: 220 },
        { tag: "return-full", w: 800, h: 300 },
        { tag: "empty", w: 460, h: 300 }
    ]
    readonly property var cur: step >= 0 && step < plan.length ? plan[step] : null
    readonly property string tag: cur ? cur.tag : ""

    function walk(item, fn) {
        if (!item) return
        fn(item)
        var kids = item.children || []
        for (var i = 0; i < kids.length; i++) walk(kids[i], fn)
    }
    function find(prefix, exact) {
        var out = []
        walk(stage, function (it) {
            var n = it.objectName
            if (n && (exact ? n === prefix : n.indexOf(prefix) === 0) && it.visible) out.push(it)
        })
        return out
    }
    function box(it) {
        var p = it.mapToItem(stage, 0, 0)
        return { x: Math.round(p.x), y: Math.round(p.y), w: Math.round(it.width), h: Math.round(it.height) }
    }
    function boxes(list) { return list.map(box) }
    function ids(prefix) { return find(prefix).map(function (t) { return t.objectName.substring(prefix.length) }) }

    function measure() {
        var m = { tag: sc.tag }
        m.away = boxes(find("away-row-"))
        m.awayIds = ids("away-row-")
        m.hints = find("away-hint-").map(function (h) { return h.children[0].text })
        m.sess = boxes(find("sess-"))
        m.sessIds = ids("sess-")
        m.sessLive = find("sess-").map(function (b) { return b.opacity === 1 })
        m.note = boxes(find("blockNote", true))
        m.pwField = boxes(find("pwField", true))
        m.pwAllow = boxes(find("pwAllow", true))
        m.pwDeny = boxes(find("pwDeny", true))
        m.pwError = boxes(find("pwError", true))
        m.pwAgent = boxes(find("pwAgent", true))
        m.denyFocus = find("pwDeny", true).length > 0 && find("pwDeny", true)[0].activeFocus
        m.ret = boxes(find("return-row-"))
        m.retIds = ids("return-row-")
        m.card = (find("card", true).map(box))[0] || null
        m.sel = awayList.current
        m.stage = { w: stage.width, h: stage.height }
        return m
    }

    function shoot() {
        console.log("PROBE " + sc.tag + " " + JSON.stringify(measure()))
        stage.grabToImage(function (res) {
            res.saveToFile(sc.outDir + "/" + sc.tag + ".png")
            console.log("SHOT " + sc.tag)
            sc.advance()
        })
    }
    function advance() { step++; if (step >= plan.length) Qt.quit(); else settle.restart() }

    Component.onCompleted: advance()
    Timer { id: settle; interval: 420; onTriggered: sc.shoot() }
    Timer { interval: 25000; running: true; onTriggered: { console.log("SCENE TIMEOUT"); Qt.quit() } }

    readonly property bool isBoard: tag === "board-session"
    readonly property bool isAway: tag.indexOf("away-") === 0
    readonly property var sessBlocker: tag === "session-blocked" ? fx.blocker
        : tag === "session-pending" ? ({ pending: true }) : ({ blocked: false })
    readonly property bool isSess: tag.indexOf("session-") === 0
    readonly property bool isPk: tag.indexOf("polkit-") === 0
    readonly property bool isRet: tag.indexOf("return-") === 0
    readonly property var fxNear: fx.near || []
    readonly property var fxFar: fx.far || []

    FloatingWindow {
        implicitWidth: sc.cur ? sc.cur.w : 400
        implicitHeight: sc.cur ? sc.cur.h : 400
        color: Theme.color.bg

        Item {
            id: stage
            anchors.fill: parent
            Rectangle { anchors.fill: parent; color: Theme.color.bg }

            // the System board: session card at (440, 500), password card at (820, 560)
            Surface {
                visible: sc.isBoard
                x: 440; y: 500; width: 360; height: boardSess.implicitHeight + 32; corner: 16
                SessionCard { id: boardSess; x: 16; y: 16; width: parent.width - 32
                    buttons: S.sessionButtons(sc.fx.env, sc.fx.blocker); blocker: sc.fx.blocker || ({ blocked: false }) }
            }
            Surface {
                visible: sc.isBoard
                x: 820; y: 560; width: 440; height: boardPk.implicitHeight + 32; corner: 16
                PolkitCard { id: boardPk; x: 16; y: 16; width: parent.width - 32
                    view: S.polkitView(sc.fx.polkit ? sc.fx.polkit.agent : ({})) }
            }

            Surface {
                objectName: visible ? "card" : ""
                visible: sc.isAway
                x: 20; y: 10; width: 420; height: awayList.implicitHeight + 32; corner: Theme.radius.card
                AwayList {
                    id: awayList
                    x: 16; y: 16; width: parent.width - 32
                    rows: sc.isAway ? S.awayRows(sc.tag === "away-far" ? sc.fxFar : sc.fxNear) : []
                    current: sc.tag === "away-select" ? 3 : 0
                    onPicked: key => sc.picked = key
                    onCancelled: sc.picked = "cancel"
                }
            }
            Surface {
                objectName: visible ? "card" : ""
                visible: sc.isSess
                x: 20; y: 10; width: 392; height: sessCard.implicitHeight + 32; corner: Theme.radius.card
                SessionCard { id: sessCard; x: 16; y: 16; width: parent.width - 32
                    buttons: S.sessionButtons(sc.fx.env, sc.sessBlocker)
                    blocker: sc.sessBlocker }
            }
            Surface {
                objectName: visible ? "card" : ""
                visible: sc.isPk
                x: 20; y: 10; width: 440; height: pkCard.implicitHeight + 32; corner: Theme.radius.card
                PolkitCard { id: pkCard; x: 16; y: 16; width: parent.width - 32
                    view: S.polkitView(sc.fx.polkit ? sc.fx.polkit[sc.tag.substring(7)] : ({}))
                    onSubmitted: value => sc.sent = "submitted"
                    onCancelled: sc.denied = "denied" }
            }
            Item {
                visible: sc.isRet
                x: 20; y: 10; width: 760; height: ret.implicitHeight
                AwayReturn {
                    id: ret
                    objectName: "ret"
                    width: parent.width
                    now: sc.fx.now || 0
                    declared: sc.tag === "return-detected" ? null : (sc.fx.declared || null)
                    idleSince: sc.tag === "return-detected" ? (sc.fx.idleSince || 0) : 0
                    agent: sc.tag === "return-full" ? (sc.fx.agent || null) : null
                    mail: sc.tag === "return-full" ? (sc.fx.mail || null) : null
                }
            }
            // empty: no choices yet (helper not answered), nothing to draw but the frame
            Surface {
                objectName: visible ? "card" : ""
                visible: sc.tag === "empty"
                x: 20; y: 10; width: 420; height: emptyList.implicitHeight + 32; corner: Theme.radius.card
                AwayList { id: emptyList; x: 16; y: 16; width: parent.width - 32; rows: [] }
            }
        }
    }
}
