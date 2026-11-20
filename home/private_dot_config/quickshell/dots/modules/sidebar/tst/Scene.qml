import QtQuick
import Quickshell
import qs.modules.overview
import qs.modules.sidebar

// Test scene for tests/sidebar-ui.sh: renders the REAL SidebarBody on Qt's offscreen platform,
// logs `PROBE {json}`, saves a PNG of the stage and quits. Env: TAB, SELECT (item id),
// SYSTEM=1 (open the system slot), CLICK_NAMES (objectNames to click), OUT_DIR, TAG.
ShellRoot {
    id: sc

    readonly property string outDir: Quickshell.env("OUT_DIR") || "/tmp"
    readonly property string tag: Quickshell.env("TAG") || "main"
    readonly property string clicks: Quickshell.env("CLICK_NAMES") || ""

    function walk(item, fn) {
        if (!item) return;
        fn(item);
        var kids = item.children || [];
        for (var i = 0; i < kids.length; i++) walk(kids[i], fn);
    }
    function find(name) {
        var out = [];
        walk(stage, function (it) { if (it.objectName === name) out.push(it) });
        return out;
    }
    function box(it) {
        if (!it) return null;
        var p = it.mapToItem(stage, 0, 0);
        return { x: p.x, y: p.y, w: it.width, h: it.height, visible: it.visible };
    }

    function measure() {
        var m = { tag: sc.tag };
        m.body = box(body);
        m.header = box(find("sideHeader")[0]);
        m.nowTitle = find("nowTitle")[0].text;
        var nx = find("nextLine")[0];
        m.next = nx && nx.visible ? nx.text : "";
        m.tabs = find("sideTabs")[0] ? ["queue", "inbox", "agents", "work", "time"].map(function (k) {
            var t = find("tab-" + k)[0];
            return { key: k, x: box(t).x, y: box(t).y, w: t.width, h: t.height, selected: t.selected };
        }) : [];
        m.tabsBox = box(find("sideTabs")[0]);
        m.heads = find("groupHead").map(function (h) { return h.text });
        m.rows = find("sideRow").map(function (r) {
            var b = box(r), age = find("rowAge").filter(function (a) { return a.parent === r })[0];
            var mk = find("rowMark").filter(function (a) { return a.parent === r })[0];
            var tx = find("rowText").filter(function (a) { return a.parent === r })[0];
            var ab = box(age), mb = box(mk), tb = box(tx);
            return { id: r.item.id, title: r.item.title, mark: r.markKind, selected: r.selected, dim: r.dim,
                     x: b.x, y: b.y, w: b.w, h: b.h,
                     ageRight: ab.x + ab.w, ageW: ab.w, ageText: age.text, markX: mb.x, markW: mb.w, textX: tb.x, textW: tb.w,
                     src: r.srcName };
        });
        m.scroll = box(find("sideScroll")[0]);
        var ft = find("sideFooter")[0];
        m.footer = ft && ft.visible ? box(ft) : null;
        var fte = find("footTitle")[0];
        m.footTitle = fte ? fte.text : "";
        m.buttons = ["actReply", "actAgent", "actQueue", "actSnooze", "actExpand"].map(function (n) {
            var b = find(n)[0];
            return b ? { name: n, enabled: b.enabled, tip: b.tip, text: b.text, w: b.width, h: b.height, primary: b.primary } : { name: n, missing: true };
        });
        var em = find("emptyNote")[0];
        m.empty = em ? em.visible : false;
        var ss = find("systemSlot")[0];
        m.system = ss ? { active: ss.active, status: ss.status, source: String(ss.source), ready: ss.status === Loader.Ready } : null;
        var sm = find("systemMissing")[0];
        m.systemMissing = sm ? sm.visible : false;
        m.stub = find("systemStub").length;
        m.staleMark = find("staleMark").filter(function (s) { return s.visible }).length;
        m.dim = body.dim;
        return m;
    }

    function shoot() {
        var m = measure();
        console.log("PROBE " + JSON.stringify(m));
        stage.grabToImage(function (res) {
            res.saveToFile(sc.outDir + "/" + sc.tag + ".png");
            console.log("SHOT " + sc.tag);
            Qt.quit();
        });
    }

    Component.onCompleted: {
        body.tab = Quickshell.env("TAB") || "queue";
        body.selectedId = Quickshell.env("SELECT") || "";
        body.showSystem = Quickshell.env("SYSTEM") === "1";
    }

    FloatingWindow {
        implicitWidth: 480
        implicitHeight: 960
        color: "#0a0e10"

        Item {
            id: stage
            anchors.fill: parent

            SidebarBody {
                id: body
                x: 10
                y: 10
                height: 940
                animate: false
                onExpandRequested: function (t) { console.log("EXPAND " + t) }
            }

            Timer {
                interval: 700
                running: true
                onTriggered: {
                    var names = sc.clicks === "" ? [] : sc.clicks.split(",");
                    for (var i = 0; i < names.length; i++) {
                        var n = names[i], dbl = n.indexOf("dbl:") === 0;
                        var it = sc.find(dbl ? n.substring(4) : n)[0];
                        if (!it) { console.log("NOBUTTON " + n); continue; }
                        if (dbl) it.jumped(); else it.clicked();
                    }
                    shootTimer.start();
                }
            }
            Timer { id: shootTimer; interval: 300; onTriggered: sc.shoot() }
        }
    }
}
