import QtQuick
import Quickshell
import Quickshell.Io
import "modules/bar"

// Test scene for tests/bar-ui.sh, run with `quickshell -p <root>` on the offscreen Qt
// platform: the REAL BarView from a fixture model, no services, no compositor. Logs
// `PROBE {json}` (geometry), saves a PNG of the stage and quits.
//   FIXTURE  path of the model JSON     LOGOS  dir of the generated logos
//   OUT      png path                   CLICKS comma list: objectName[:index]
//   WIDTH    stage width (1920)         ETIME  pin the equalizer (seconds)
ShellRoot {
    id: sc

    readonly property string fixture: Quickshell.env("FIXTURE")
    readonly property string logos: "file://" + Quickshell.env("LOGOS")
    readonly property string outPng: Quickshell.env("OUT") || "/tmp/bar.png"
    readonly property string clicks: Quickshell.env("CLICKS") || ""
    readonly property int stageW: Number(Quickshell.env("WIDTH")) || 1920
    readonly property real eTime: Number(Quickshell.env("ETIME") || "-1")
    property var emitted: []

    FileView {
        id: file
        path: sc.fixture
        blockLoading: true
    }
    readonly property var model: {
        var t = file.text().split("@LOGOS@").join(sc.logos)
        return JSON.parse(t)
    }

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
    function box(it) {
        if (!it) return null
        var p = it.mapToItem(stage, 0, 0)
        return { x: p.x, y: p.y, w: it.width, h: it.height, visible: it.visible }
    }
    function boxes(name) { return find(name).map(box) }

    function measure() {
        var m = { stageW: stage.width, stageH: stage.height, emitted: sc.emitted }
        m.left = box(find("leftPill")[0]); m.centre = box(find("centrePill")[0]); m.right = box(find("rightPill")[0])
        m.logo = box(find("logo")[0])
        m.profiles = boxes("profile")
        m.workspaces = boxes("workspace")
        m.wsNames = find("wsName").map(function (n) { return n.visible })
        m.wsLogos = boxes("wsLogo")
        m.task = box(find("task")[0]); m.taskText = find("taskText").map(function (n) { return { visible: n.visible, w: n.width } })[0]
        m.detour = box(find("detour")[0])
        m.waits = boxes("wait")
        m.waitMore = box(find("waitMore")[0])
        m.fault = box(find("fault")[0])
        m.music = box(find("music")[0])
        m.metrics = boxes("metric")
        m.logout = box(find("logout")[0])
        m.tray = box(find("tray")[0])
        m.bell = box(find("bell")[0]); m.bellDot = box(find("bellDot")[0])
        m.clockText = find("clockText").map(function (n) { return n.text })[0]
        m.clockChip = box(find("clockChip")[0]); m.salahChip = box(find("salahChip")[0])
        var eq = find("eq")[0]
        m.eq = eq ? { w: eq.width, h: eq.height, opacity: eq.opacity, bars: find("eqBar").length } : null
        var bars = []
        if (eq) walk(eq, function (it) { if (it.objectName === "eqBar") bars.push(Math.round(it.children[0].height * 100) / 100) })
        m.eqHeights = bars
        return m
    }

    function press(spec) {
        var p = spec.split(":"), items = find(p[0]), it = items[Number(p[1] || 0)]
        if (!it) { console.log("NOCLICK " + spec); return }
        if (p[0] === "logo") it.clicked(); else it.clicked(Qt.LeftButton)
    }

    FloatingWindow {
        implicitWidth: sc.stageW
        implicitHeight: 96
        color: "#2a3438"

        Item {
            id: stage
            anchors.fill: parent

            Rectangle { anchors.fill: parent; color: "#2a3438" }

            BarView {
                id: view
                width: parent.width
                height: view.stripHeight
                y: 24
                model: sc.model
                eqTime: sc.eTime
                trayModel: sc.model.trayCount ? Array.apply(null, Array(sc.model.trayCount)).map(function () { return { icon: "" } }) : null
                onToggleRequested: (name, x) => sc.emitted = sc.emitted.concat([{ kind: "toggle", name: name, x: x }])
                onLogoClicked: sc.emitted = sc.emitted.concat([{ kind: "logo" }])
                onWorkspaceRequested: id => sc.emitted = sc.emitted.concat([{ kind: "workspace", id: id }])
            }
        }
    }

    Timer {
        interval: 900
        running: true
        onTriggered: {
            if (sc.clicks !== "") sc.clicks.split(",").forEach(function (s) { sc.press(s) })
            console.log("PROBE " + JSON.stringify(sc.measure()))
            stage.grabToImage(function (res) {
                res.saveToFile(sc.outPng)
                Qt.quit()
            })
        }
    }
}
