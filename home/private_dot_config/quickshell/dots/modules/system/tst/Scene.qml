import QtQuick
import Quickshell
import Quickshell.Io
import "modules/theme"
import "modules/common"
import "modules/system"
import "modules/system/js/Menus.js" as Menus

// Test scene for tests/system-ui.sh, run with `quickshell -p <root>` on the offscreen Qt
// platform. Renders the REAL system components from a fixture state, in the board's
// layouts, one PNG and one `PROBE <tag> {json}` line per state, then quits.
ShellRoot {
    id: sc

    readonly property string outDir: Quickshell.env("OUT_DIR") || "/tmp"
    readonly property string fixture: Quickshell.env("FIXTURE") || ""
    property var st: ({})
    property int step: -1
    property string clicked: ""

    FileView {
        id: fx
        path: sc.fixture
        blockLoading: true
        Component.onCompleted: { try { sc.st = JSON.parse(fx.text()) } catch (e) { console.log("FIXTURE ERROR " + e) } }
    }

    readonly property var plan: [
        { tag: "board-system", w: 1340, h: 840 },
        { tag: "board-menus", w: 1340, h: 900 },
        { tag: "popout-quick", w: 460, h: 840 },
        { tag: "popout-session", w: 460, h: 400 },
        { tag: "popout-wifi", w: 460, h: 700 },
        { tag: "empty", w: 460, h: 840 },
        { tag: "menu-wifi", w: 480, h: 700 }, { tag: "menu-bt", w: 480, h: 500 }, { tag: "menu-quiet", w: 480, h: 640 },
        { tag: "menu-vpn", w: 480, h: 620 }, { tag: "menu-ts", w: 480, h: 700 }, { tag: "menu-mic", w: 480, h: 700 },
        { tag: "menu-night", w: 480, h: 560 }, { tag: "menu-awake", w: 480, h: 420 }, { tag: "menu-perf", w: 480, h: 640 },
        { tag: "menu-theme", w: 480, h: 480 }, { tag: "menu-sound", w: 480, h: 440 }, { tag: "menu-display", w: 480, h: 560 }
    ]
    readonly property var cur: step >= 0 && step < plan.length ? plan[step] : null
    readonly property string tag: cur ? cur.tag : ""
    readonly property string menuId: tag.indexOf("menu-") === 0 ? tag.substring(5) : ""

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

    function measure() {
        var m = { tag: sc.tag }
        m.tiles = boxes(find("tile-"))
        m.tileIds = find("tile-").map(function (t) { return t.objectName.substring(5) })
        m.meters = boxes(find("meter"))
        m.rows = find("row-").map(function (r) { return r.objectName.substring(4) })
        m.rowBoxes = boxes(find("row-"))
        m.sess = boxes(find("sess-"))
        m.sessIds = find("sess-").map(function (r) { return r.objectName.substring(5) })
        m.ctx = boxes(find("ctx-row"))
        m.back = boxes(find("menuBack", true))
        m.media = boxes(find("mediaRow", true))
        m.log = boxes(find("log", true))
        m.panel = (find("panelCard", true).map(box))[0] || null
        m.card = (find("menuCard", true).map(box))[0] || null
        m.power = boxes(find("powerButton", true))
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

    FloatingWindow {
        implicitWidth: sc.cur ? sc.cur.w : 400
        implicitHeight: sc.cur ? sc.cur.h : 400
        color: Theme.color.bg

        Item {
            id: stage
            anchors.fill: parent

            Rectangle { anchors.fill: parent; color: Theme.color.bg }

            Item {
                id: board
                anchors.fill: parent
                visible: sc.tag === "board-system" || sc.tag === "board-menus"

                // left: quick panel, as in both boards
                Surface {
                    objectName: sc.tag === "board-system" || sc.tag === "board-menus" ? "panelCard" : ""
                    x: 20; y: 20; width: 400; height: 800
                    corner: 16
                    QuickView {
                        x: 16; y: 14; width: parent.width - 32
                        st: sc.st
                        selected: sc.tag === "board-menus" ? "wifi" : ""
                    }
                }
                // System board: bluetooth menu, media card, two right-click menus, session card
                Surface {
                    visible: sc.tag === "board-system"
                    x: 440; y: 20; width: 360; height: btMenu.implicitHeight + 32; corner: 16
                    SysMenuCard { id: btMenu; x: 16; y: 16; width: parent.width - 32; model: Menus.menu("bt", sc.st) }
                }
                MediaCard {
                    visible: sc.tag === "board-system"
                    x: 820; y: 20
                    media: sc.st.media
                }
                ContextMenu { visible: sc.tag === "board-system"; kind: "window"; x: 820; y: 260 }
                ContextMenu { visible: sc.tag === "board-system"; kind: "desktop"; x: 1072; y: 260 }
                Surface {
                    visible: sc.tag === "board-system"
                    x: 440; y: 500; width: 360; height: sess.implicitHeight + 32; corner: 16
                    SysSession { id: sess; x: 16; y: 16; width: parent.width - 32
                        buttons: Menus.sessionButtons(sc.st, { sessionId: "1", user: "u" })
                        blocker: sc.st.session ? sc.st.session.blocker : "" }
                }
                // Menus board: the wifi menu beside the panel
                Surface {
                    objectName: sc.tag === "board-menus" ? "menuCard" : ""
                    visible: sc.tag === "board-menus"
                    x: 440; y: 20; width: 420; height: Math.min(860, wm.implicitHeight + 32); corner: 16
                    SysMenuCard { id: wm; x: 16; y: 16; width: parent.width - 32; model: Menus.menu("wifi", sc.st) }
                }
            }

            // popout-sized views: what the real popout holds (400 wide card, 16 px padding)
            Surface {
                id: pop
                visible: sc.tag.indexOf("popout-") === 0 || sc.tag === "empty"
                objectName: visible ? "panelCard" : ""
                x: 20; y: 10; width: 400
                height: popView.implicitHeight + 32
                corner: 14
                SystemView {
                    id: popView
                    x: 16; y: 16; width: parent.width - 32
                    st: sc.tag === "empty" ? ({}) : sc.st
                    view: sc.tag === "popout-session" ? "session" : sc.tag === "popout-wifi" ? "wifi" : ""
                    env: ({ sessionId: "1", user: "u" })
                }
            }

            // one menu at a time, 420 wide
            Surface {
                visible: sc.menuId !== ""
                objectName: visible ? "menuCard" : ""
                x: 20; y: 10; width: 420
                height: one.implicitHeight + 32
                corner: 16
                SysMenuCard {
                    id: one
                    x: 16; y: 16; width: parent.width - 32
                    model: sc.menuId !== "" ? Menus.menu(sc.menuId, sc.st) : null
                }
            }
        }
    }
}
