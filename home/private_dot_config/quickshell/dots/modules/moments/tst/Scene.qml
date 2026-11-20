import QtQuick
import Quickshell
import qs.modules.moments
import qs.modules.theme

// Test scene for tests/moments-ui.sh, run with `quickshell -p <root>` on the offscreen Qt
// platform (the shell root links the stub Theme, the real common/ and moments/). It renders
// the REAL components, logs `PROBE <tag> {json}`, saves a PNG of the stage and quits.
// SCENARIO: board | chip | chipnone | capture | action
// Knobs: TEXT CAPTURED=1 TOAST=off BACK=1 HANDED=<json file> ACTION=<what> OUT_DIR
ShellRoot {
    id: sc

    readonly property string scenario: Quickshell.env("SCENARIO") || "board"
    readonly property string outDir: Quickshell.env("OUT_DIR") || "/tmp"
    readonly property string action: Quickshell.env("ACTION") || ""
    readonly property string text: Quickshell.env("TEXT") || ""
    readonly property bool captured: Quickshell.env("CAPTURED") === "1"
    readonly property bool toastGone: Quickshell.env("TOAST") === "off"
    readonly property bool backDone: Quickshell.env("BACK") === "1"
    property var handed: null

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
    function b1(name) { return box(find(name)[0]) }

    function measure() {
        var m = { scenario: sc.scenario }
        var names = ["captureInput", "pressEnter", "capturedNote", "nudgeCard", "nudgeNote", "nudgeJump", "nudgeDismiss",
                     "returnFace", "panelChip", "returnNote", "handedAsk", "handedFooter", "handedSent", "capturePanel",
                     "renudgePanel", "returnPanel", "handedPanel", "captureHints"]
        for (var i = 0; i < names.length; i++) m[names[i]] = b1(names[i])
        m.handedSteps = find("handedStep").map(box)
        m.tipsVisible = find("tip").concat(find("hintTip")).filter(function (t) { return t.visible }).length
        var sent = find("handedSent")[0]
        m.handedSentEnabled = sent ? sent.usable : null
        var chip = find("chip")[0]
        if (chip) { m.chip = box(chip); m.chip.implicitWidth = chip.implicitWidth }
        m.left = b1("mockLeft"); m.right = b1("mockRight")
        m.stateTask = MomentState.hasTask
        m.detour = MomentState.detour
        return m
    }

    function shoot(tag) {
        console.log("PROBE " + tag + " " + JSON.stringify(measure()))
        stage.grabToImage(function (res) {
            res.saveToFile(sc.outDir + "/" + sc.scenario + "-" + tag + ".png")
            console.log("SHOT " + tag)
            Qt.quit()
        })
    }

    Component.onCompleted: {
        var h = Quickshell.env("HANDED")
        if (h) {
            var xhr = new XMLHttpRequest()
            xhr.open("GET", "file://" + h, false)
            xhr.send()
            try { sc.handed = JSON.parse(xhr.responseText) } catch (e) { console.log("handed fixture unreadable") }
        }
    }

    FloatingWindow {
        implicitWidth: sc.scenario === "board" ? 1200 : 760
        implicitHeight: sc.scenario === "board" ? 860 : 220
        color: Theme.color.surfaceDim

        Item {
            id: stage
            anchors.fill: parent

            Rectangle { anchors.fill: parent; color: Theme.color.surfaceDim }

            Grid {
                visible: sc.scenario === "board"
                x: 32
                y: 32
                columns: 2
                spacing: 24

                CaptureCard {
                    id: capture
                    objectName: "capturePanel"
                    width: 560
                    height: 386
                    backTo: "HD 4412"
                    captured: sc.captured
                    enrichment: sc.captured ? ["project: infra", "tags: capacity, db", "person: Sam R.", "from: HD 4412, terminal pane 2", "due: none"] : []
                    Component.onCompleted: { if (sc.text !== "") capture.text = sc.text }
                }
                RenudgePanel {
                    objectName: "renudgePanel"
                    width: 560
                    height: 386
                    animate: false
                    ref: "HD 4412"
                    toastOn: !sc.toastGone
                    age: sc.toastGone ? "10m" : "2m"
                }
                ReturnPanel {
                    objectName: "returnPanel"
                    width: 560
                    height: 386
                    where: "You're in Slack, replying to Priya."
                    detour: MomentState.detour
                    task: MomentState.task
                    backDone: sc.backDone
                    next: "pin the workflow"
                }
                HandedCard {
                    objectName: "handedPanel"
                    width: 560
                    height: 386
                    handed: sc.handed
                }
            }

            // a mock bar with the real chip between two neighbours
            Rectangle {
                visible: sc.scenario === "chip" || sc.scenario === "chipnone"
                x: 40
                y: 20
                height: 30
                width: row.implicitWidth + 20
                color: Qt.alpha(Theme.color.surface, 0.78)
                Row {
                    id: row
                    x: 10
                    spacing: 6
                    anchors.verticalCenter: parent.verticalCenter
                    Rectangle { objectName: "mockLeft"; width: 40; height: 14; radius: 4; color: "#5a5d70" }
                    ReturnChip { id: chip; objectName: "chip" }
                    Rectangle { objectName: "mockRight"; width: 40; height: 14; radius: 4; color: "#5a5d70" }
                }
            }

            Item {
                visible: sc.scenario === "capture" || sc.scenario === "action"
                x: 20
                y: 20
                CaptureCard {
                    id: lone
                    objectName: "capturePanel"
                    Component.onCompleted: { if (sc.text !== "") lone.text = sc.text }
                }
            }
        }
    }

    Timer {
        interval: 700
        running: true
        onTriggered: {
            if (sc.scenario === "action") {
                var r
                if (sc.action === "submit") r = lone.submit()
                else if (sc.action === "chip") r = chip.back()
                console.log("DID " + sc.action + " " + r + " captured=" + lone.captured)
                sc.shoot("action")
            } else if (sc.scenario === "chip" && sc.action === "chip") {
                console.log("DID chip " + chip.back())
                quitT.start()
            } else {
                sc.shoot("main")
            }
        }
    }
    Timer { id: quitT; interval: 400; onTriggered: Qt.quit() }
}
