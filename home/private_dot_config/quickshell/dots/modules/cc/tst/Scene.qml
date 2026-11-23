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
        m.agentFor = find("agentFor").filter(vis).map(function (t) { return t.text })
        m.agentWork = find("agentWork").filter(vis).map(function (t) { return t.text })
        m.agentJump = find("agentJump").filter(vis).map(function (b) { return { blocked: b.blocked } })
        m.ccOpen = Ui.cc
        m.agentsEmpty = find("agentsEmpty").filter(vis).length
        m.todayRows = find("todayRow").filter(vis).length
        m.now = find("nowCard").filter(vis).map(box)[0] || null
        m.taskViews = find("taskView").filter(vis).map(function (b) { return { t: b.text, on: b.on } })
        m.board = find("taskBoard").filter(vis).length
        m.all = find("taskAll").filter(vis).length
        m.timeTabs = find("timeTab").filter(vis).map(function (b) { return { t: b.text, on: b.on } })
        m.time = { today: find("timeToday").filter(vis).length, week: find("timeWeek").filter(vis).length, heat: find("timeHeat").filter(vis).length,
                   report: find("timeReport").filter(vis).length, noData: find("timeNoData").filter(vis).length,
                   whereRows: find("whereTime").filter(vis).length, bar: find("todayBar").filter(vis).map(box)[0] || null,
                   card: find("todayCard").filter(vis).map(box)[0] || null, doneCard: find("doneCard").filter(vis).map(box)[0] || null,
                   page: find("timePage").map(function (x) { return { flick: x.contentHeight !== undefined } })[0] || null,
                   flicks: find("timeToday").length ? (function () { var n = []; walk(find("timeToday")[0], function (x) { if (x.contentHeight !== undefined && x.flickableDirection !== undefined) n.push(x.objectName) }); return n })() : [],
                   barSegs: (function () { var b = find("todayBar").filter(vis)[0]; if (!b) return null; var r = []; walk(b, function (x) { if (x.radius === 4 && x !== b) r.push({ x: Math.round(x.x), w: Math.round(x.width) }) }); return r })() }
        m.work = measureWork("workPage", ["nowCard", "todayListCard", "untickCard", "boardCol", "allScroll"])
        m.timePg = measureWork("timePage", ["todayCard", "whereTime", "doneCard", "weekCard", "weekSide", "daysCard", "dayDetail", "timeHeat", "heatGrid", "monthsCard",
                                            "zoneRank", "zoneWeeks", "zoneProjects", "zoneDays", "progressScroll", "reportCard", "reportAbout", "screenCard", "healthCard", "remindersCard", "salahCard",
                                            "timeReport", "timeNoData", "todayBar", "agentTables", "agentKinds", "agentDaily", "agentSubLive"])
        m.agPg = measureWork("agentsPage", ["awayCard", "metricsCard"])
        m.tm = measureTime()
        m.ag = measureAgents()
        m.stats = find("statValue").filter(vis).map(function (t) { return t.text })
        m.heatCells = find("cell").filter(vis).length
        m.staleMark = find("staleMark").filter(vis).length
        m.closes = sc.closes
        m.k = measureKeys()
        m.hidden = Object.keys(CcState.hidden).sort().join(",")
        m.sel = CcState.effId
        return m
    }

    // Time > Agents and the Agents page cards: what is on screen, by object name
    function measureAgents() {
        var cnt = function (n) { return find(n).filter(vis).length }
        var tx = function (n) { return find(n).filter(vis).map(function (t) { return t.text }) }
        var tab = find("timeAgents")[0]
        return {
            tab: tab ? vis(tab) : false, kpi: cnt("agentKpi"), kpiValues: tx("kpiValue"), kpiNotes: tx("kpiNote"), deltas: cnt("delta"), tblRows: cnt("agentTblRow"),
            kindSegs: cnt("kindSeg"), legend: cnt("kindLegend"), dailyTokens: cnt("dailyTokens"), dailyCost: cnt("dailyCost"), subShare: tx("subShare")[0] || "",
            live: { working: tx("liveWorking")[0] || "", needs: tx("liveNeeds")[0] || "", idle: tx("liveIdle")[0] || "", shown: cnt("liveCounts") },
            periodSegs: find("agentPeriodSeg").filter(vis).map(function (b) { return { t: b.text, on: b.on } }), jumpBtn: cnt("agentTblJump"),
            ks: tab ? tab.ks : null, noData: tab ? cnt("timeNoData") : 0,
            awayRows: cnt("awayRow"), awayEmpty: cnt("awayEmpty"), awaySummary: tx("awaySummary")[0] || "", metricRuns: tx("metricRuns")[0] || "", metricTokens: tx("metricTokens")[0] || "",
            metricCost: tx("metricCost")[0] || "", openLink: cnt("openTimeAgents"),
            sideScroll: find("agentSideScroll").filter(vis).map(function (f) { return { clip: f.clip, h: Math.round(f.height), contentH: Math.round(f.contentHeight) } }),
            tableScroll: find("agentTableScroll").filter(vis).map(function (f) { return { clip: f.clip, h: Math.round(f.height), contentH: Math.round(f.contentHeight), y: Math.round(f.contentY) } })
        }
    }

    // Time sub-tabs fed by metrics.json: what is on screen, by object name
    function measureTime() {
        var cnt = function (n) { return find(n).filter(vis).length }
        var firstText = function (c) { var t = ""; walk(c, function (x) { if (x.text !== undefined && x.role === "bodyS" && t === "") t = x.text }); return t }
        var tp = find("timePage")[0]
        return {
            state: tp ? tp.parsed.state : "", weekChart: cnt("weekChart"), weekBars: cnt("weekBar"), targetLine: cnt("targetLine"),
            kpi: cnt("kpiCard"), kpiValues: find("kpiValue").filter(vis).map(function (t) { return t.text }), sparks: cnt("spark"), deltas: cnt("delta"),
            dayRows: cnt("dayRow"), dayDetail: cnt("dayDetail"), cells: cnt("cell"), readout: texts("heatReadout")[0] || "",
            zoneRank: cnt("zoneRank"), zoneWeeks: cnt("zoneWeeks"), zoneDays: cnt("zoneDays"), remRows: cnt("remRow"), screenCard: cnt("screenCard"), healthCard: cnt("healthCard"),
            report: texts("reportStatus")[0] || "", hints: texts("timeStamp")[0] || "", stamp: texts("timeStamp")[0] || "", hintBar: cnt("timeHints"),
            noData: find("timeNoData").filter(vis).map(firstText), weekScrolls: cnt("weekScroll")
        }
    }

    // Tasks page: is the page a Flickable, which Flickables exist and clip, and does any visible
    // text run outside the clipped box (card, column or scroll area) it sits in
    function isFlick(x) { return x.contentHeight !== undefined && x.flickableDirection !== undefined }
    function measureWork(pageName, colNames) {
        var pg = find(pageName)[0]
        if (!pg) return null
        var w = { page: box(pg), flickPage: isFlick(pg), flicks: [], texts: [], out: [], cols: [], rowsText: [] }
        walk(pg, function (x) {
            if (isFlick(x) && vis(x)) w.flicks.push({ name: x.objectName, clip: x.clip, box: box(x), contentH: Math.round(x.contentHeight) })
        })
        colNames.forEach(function (n) {
            find(n).filter(vis).forEach(function (c) {
                var b = box(c)
                b.name = n
                b.inFlick = false     // content of a scroll area may run below it; that is what scrolling is
                for (var p = c.parent; p && p !== pg; p = p.parent) if (p.contentItem !== undefined && isFlick(p)) b.inFlick = true
                w.cols.push(b)
            })
        })
        walk(pg, function (x) {
            if (x.text === undefined || x.contentWidth === undefined || !vis(x) || x.text === "") return
            var b = box(x), host = null, flick = null
            for (var p = x.parent; p; p = p.parent) {
                if (p === pg) break
                if (!flick && p.contentItem !== undefined && isFlick(p)) flick = p
                if (!host && p.clip === true && p.contentItem === undefined) host = p
            }
            // tall lists may run below a scroll viewport (that is what scrolling is); x never may
            var h = flick || host || pg
            var hb = box(h)
            var xo = b.x < hb.x - 1 || b.x + b.w > hb.x + hb.w + 1
            var yo = !flick && (b.y < hb.y - 1 || b.y + b.h > hb.y + hb.h + 1)
            w.texts.push(x.text)
            if (xo || yo) w.out.push({ t: x.text, b: b, host: hb })
        })
        w.headerNow = texts("ccNowText")[0] || ""
        w.rowsText = find("todayRowTitle").filter(vis).map(function (t) { return t.text })
        return w
    }

    // keyboard state after the key steps: the focus model, the filter, the help overlay and the rings
    function measureKeys() {
        var rings = find("focusRing").filter(vis)
        var ov = find("helpOverlay")[0]
        var fb = find("filterBar")[0]
        return { page: CcState.pageId, zone: CcState.zone, pane: CcState.pane, mode: CcState.mode, kind: CcState.kindNow,
                 pending: CcState.pending, help: ov ? vis(ov) : false, helpRows: find("helpRow").filter(vis).map(function (r) { return r.modelData.keys + "|" + r.modelData.label }),
                 filter: CcState.filterText, filterBar: fb ? vis(fb) : false, snooze: CcState.snoozeIdx, agent: CcState.agentCur, task: CcState.taskCur,
                 src: CcState.src, taskView: CcState.taskView, timeTab: CcState.timeTab, keyboard: CcState.keyboard, chipFocus: CcState.chipFocus,
                 rings: rings.length, ringKinds: rings.map(function (r) { return r.kind + ":" + r.spec.width + ":" + r.spec.offset }),
                 hint: (find("keyHint")[0] || { text: "" }).text, rowsShown: find("queueRow").filter(vis).length,
                 agentsShown: CcState.agentsShown.length, tasksShown: CcState.tasksShown.length, status: CcState.status,
                 view: CcState.view, group: CcState.group, grant: CcState.grant, timeBy: CcState.timeBy, viewFocus: CcState.viewFocus, groupFocus: CcState.groupFocus,
                 tks: (find("timePage")[0] || { ks: null }).ks, rem: Object.keys((find("timePage")[0] || { hiddenRem: {} }).hiddenRem).length }
    }
    readonly property var keyNames: ({ Esc: 0x01000000, Tab: 0x01000001, Backtab: 0x01000002, Enter: 0x01000004, Home: 0x01000010, End: 0x01000011,
                                       Left: 0x01000012, Up: 0x01000013, Right: 0x01000014, Down: 0x01000015, PageUp: 0x01000016, PageDown: 0x01000017 })
    // one synthetic key press through CcView.handle: the same path a real press takes. `tok` is
    // Esc, Enter, Tab, Down, Ctrl+d, Ctrl+Enter, or one printable character.
    function press(tok) {
        var ctrl = tok.indexOf("Ctrl+") === 0
        var base = ctrl ? tok.substring(5) : tok
        var named = sc.keyNames[base]
        var key = named !== undefined ? named : base.toUpperCase().charCodeAt(0)
        var text = named !== undefined ? "" : base
        var mods = (ctrl ? Qt.ControlModifier : 0) | ((named === undefined && base !== base.toLowerCase()) ? Qt.ShiftModifier : 0)
        var e = { key: key, text: ctrl ? "" : text, modifiers: mods, accepted: false }
        var view = find("ccView")[0]
        var handled = view.handle(e)
        // typing into the filter field has no real TextInput under offscreen: do what it would
        if (!handled && CcState.zone === "filter" && named === undefined && !ctrl) CcState.filterText = CcState.filterText + text
        return handled
    }

    // The Time sub-tabs read metrics.json. A scene whose state dir has none gets the full fixture
    // (METRICS=name picks another, METRICS=none keeps the state dir), so every time scene has data.
    function useAgents() {
        var name = Quickshell.env("AGENTM") || "agents"
        if (name === "none") return
        CcState.agentMetricsPath = Quickshell.shellPath("modules/cc/tst/fixtures/" + name + "/agent-metrics.json")
        CcState.awayPath = Quickshell.shellPath("modules/cc/tst/fixtures/" + name + "/away.json")
    }
    function useMetrics() {
        var name = Quickshell.env("METRICS") || ""
        var tp = find("timePage")[0]
        if (!tp || name === "none") return
        if (name === "" && tp.metricsText !== "") return
        tp.metricsPath = Quickshell.shellPath("modules/cc/tst/fixtures/" + (name || "metrics") + "/metrics.json")
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
        else if (op === "jumprow") { var jr = find("agentJump").filter(vis)[Number(arg)]; if (jr) jr.clicked(); else console.log("NOJUMP " + arg) }
        else if (op === "keys") arg.split(".").forEach(function (t) { if (t !== "") sc.press(t === "Dot" ? "." : t) })
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
        CcState.setTab(Quickshell.env("TAB") || "queue")   // the real path: Time opens on its sub-tab strip
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
        implicitWidth: Number(Quickshell.env("WIN_W")) || 1600
        implicitHeight: Number(Quickshell.env("WIN_H")) || 1000
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
    Timer { interval: 300; running: true; onTriggered: { sc.useMetrics(); sc.useAgents() } }
    Timer { id: settle; interval: 400; onTriggered: sc.shoot() }
}
