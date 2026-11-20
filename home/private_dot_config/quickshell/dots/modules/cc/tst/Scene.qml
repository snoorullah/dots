import QtQuick
import Quickshell
import qs.modules.cc
import qs.modules.cc.parts
import qs.modules.overview
import "services"

// Test scene for tests/cc-ui.sh, run with `quickshell -p <root>` on Qt's offscreen platform.
// Renders the REAL CcView at 1600 x 1000 (the board's size) from fixture JSON, optionally
// runs STEPS (pick:ID, act:LABEL, key:K, undo, mode:M, back), logs one `PROBE {json}` line
// and saves a PNG of the stage. No compositor needed.
ShellRoot {
    id: sc

    readonly property string outDir: Quickshell.env("OUT_DIR") || "/tmp"
    readonly property string tag: Quickshell.env("TAG") || "main"
    readonly property string steps: Quickshell.env("STEPS") || ""
    property int closes: 0

    function walk(item, fn) {
        if (!item) return
        fn(item)
        var kids = item.children || []
        for (var i = 0; i < kids.length; i++) walk(kids[i], fn)
    }
    function find(name) {
        var out = []
        walk(stage, function (it) { if (it.objectName === name) out.push(it) })
        return out
    }
    function vis(it) {
        // visible in the scene graph sense: it and every ancestor
        for (var p = it; p; p = p.parent) if (!p.visible) return false
        return true
    }
    function box(it) {
        var p = it.mapToItem(stage, 0, 0)
        return { x: Math.round(p.x), y: Math.round(p.y), w: Math.round(it.width), h: Math.round(it.height) }
    }
    function texts(name) { return find(name).filter(vis).map(function (t) { return t.text }) }

    function measure() {
        var m = { tag: sc.tag, tab: CcState.tab, size: { w: stage.width, h: stage.height } }
        m.header = box(find("ccHeader")[0])
        m.nav = box(find("ccNav")[0])
        m.page = box(find("ccPage")[0])
        m.footer = box(find("ccFooter")[0])
        m.navTabs = find("navTab").map(function (t) { return t.modelData.label + ":" + t.modelData.n + (t.on ? "*" : "") })
        m.sources = find("sourceRow").map(function (r) { return r.modelData.name + "=" + r.modelData.label })
        m.status = find("statusLine")[0].text
        m.undo = vis(find("undoBtn")[0])
        var rows = find("queueRow").filter(vis)
        m.rows = rows.map(function (r) {
            var b = box(r)
            b.id = r.item.id; b.current = r.current; b.tone = r.item.tone; b.sec = r.item.sec
            b.title = r.item.title; b.dim = r.dim
            var mk = null
            walk(r, function (x) { if (x.objectName === "rowMark") mk = x })
            b.mark = mk ? vis(mk) : false
            return b
        })
        m.sections = find("sectionHead").filter(vis).map(function (s) {
            var b = box(s)
            b.text = ""
            walk(s, function (x) { if (x.text !== undefined && b.text === "") b.text = x.text })
            return b
        })
        m.chips = find("filterChip").filter(vis).map(function (c) { return { t: c.text, on: c.on, w: Math.round(c.width), h: Math.round(c.height) } })
        m.groups = find("groupSeg").filter(vis).map(function (c) { return { t: c.text, on: c.on } })
        var d = find("detail")[0]
        m.detail = vis(d) ? box(d) : null
        m.detailTitle = texts("detailTitle")[0] || ""
        m.actions = find("action").filter(vis).map(function (a) {
            return { t: a.text, key: a.keyHint, primary: a.primary, stub: a.stub, blocked: a.blocked, live: a.live, h: Math.round(a.height) }
        })
        m.compose = { reply: vis(find("composeReply")[0]), agent: vis(find("composeAgent")[0]), snooze: vis(find("composeSnooze")[0]) }
        m.send = find("sendBtn").filter(vis).map(function (b) { return { stub: b.stub, live: b.live, tip: b.tip } })
        m.hand = find("handBtn").filter(vis).map(function (b) { return { stub: b.stub, live: b.live } })
        m.empty = find("emptyList").filter(vis).length
        m.agentRows = find("agentRow").filter(vis).length
        m.agentsEmpty = find("agentsEmpty").filter(vis).length
        m.todayRows = find("todayRow").filter(vis).length
        m.now = find("nowCard").filter(vis).map(box)[0] || null
        m.taskViews = find("taskView").filter(vis).map(function (b) { return { t: b.text, on: b.on } })
        m.board = find("taskBoard").filter(vis).length
        m.all = find("taskAll").filter(vis).length
        m.timeTabs = find("timeTab").filter(vis).map(function (b) { return { t: b.text, on: b.on } })
        m.time = { today: find("timeToday").filter(vis).length, week: find("timeWeek").filter(vis).length, heat: find("timeHeat").filter(vis).length,
                   report: find("timeReport").filter(vis).length, noData: find("timeNoData").filter(vis).length,
                   whereRows: find("whereTime").filter(vis).length, bar: find("todayBar").filter(vis).map(box)[0] || null }
        m.stats = find("statValue").filter(vis).map(function (t) { return t.text })
        m.heatCells = find("cell").filter(vis).length
        m.staleMark = find("staleMark").filter(vis).length
        m.closes = sc.closes
        m.hidden = Object.keys(CcState.hidden).sort().join(",")
        m.sel = CcState.effId
        return m
    }

    function runStep(s) {
        var i = s.indexOf(":"), op = i < 0 ? s : s.substring(0, i), arg = i < 0 ? "" : s.substring(i + 1)
        if (op === "pick") CcState.pick(arg)
        else if (op === "act") {
            var hit = find("action").filter(vis).filter(function (b) { return b.text === arg })[0]
            if (hit) hit.clicked(); else console.log("NOACTION " + arg)
        }
        else if (op === "key") { CcState.runKey(arg) }
        else if (op === "step") CcState.step(Number(arg))
        else if (op === "undo") CcState.undo()
        else if (op === "mode") CcState.mode = arg
        else if (op === "snooze") CcState.snooze(arg)
        else if (op === "back") find("backBtn")[0].clicked()
        else if (op === "click") { var b = find(arg)[0]; if (b) b.clicked(); else console.log("NOBUTTON " + arg) }
        else console.log("BADSTEP " + s)
    }

    function shoot() {
        var m = measure()
        console.log("PROBE " + JSON.stringify(m))
        stage.grabToImage(function (res) {
            res.saveToFile(sc.outDir + "/" + sc.tag + ".png")
            console.log("SHOT " + sc.tag)
            Qt.quit()
        })
    }

    Component.onCompleted: {
        Ui.cc = true
        Ui.ccTab = Quickshell.env("TAB") || "queue"
        CcState.src = Quickshell.env("SRC") || "All"
        CcState.group = Quickshell.env("GROUP") || "Urgency"
        CcState.view = Quickshell.env("VIEW") || ""
        CcState.timeTab = Quickshell.env("TIMETAB") || "Today"
        CcState.timeBy = Quickshell.env("TIMEBY") || "Item"
        CcState.taskView = Quickshell.env("TASKVIEW") || "Today"
        if (Quickshell.env("SELECT")) CcState.pick(Quickshell.env("SELECT"))
        if (Quickshell.env("MODE")) CcState.mode = Quickshell.env("MODE")
    }

    FloatingWindow {
        implicitWidth: 1600
        implicitHeight: 1000
        color: "#000000"

        Item {
            id: stage
            anchors.fill: parent
            CcView {
                anchors.fill: parent
                onCloseRequested: sc.closes++
            }
        }
    }

    Timer {
        interval: 700
        running: true
        onTriggered: {
            if (sc.steps !== "") sc.steps.split(",").forEach(function (s) { sc.runStep(s) })
            settle.start()
        }
    }
    Timer { id: settle; interval: 400; onTriggered: sc.shoot() }
}
