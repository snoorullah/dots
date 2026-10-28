pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import "js/Model.js" as Model

// The overview's whole view of the world: six JSON files written by dots-overview
// (contract in docs/contracts/*.schema.json). Read-only. A FileView with
// watchChanges per file, no polling. The one timer re-evaluates staleness every
// 30 s; it touches no file. DOTS_OVERVIEW_STATE_DIR and DOTS_OVERVIEW_NOW exist
// for the fixture tests and are unset in a real session.
Singleton {
    id: root

    readonly property string dir: Quickshell.env("DOTS_OVERVIEW_STATE_DIR")
        || (Quickshell.env("HOME") + "/.local/state/dots-overview")

    // Bumped by the staleness timer, by every ingest, and by the focus ring's 1 s timer.
    property int tick: 0
    property var texts: ({})
    readonly property int nowTs: { tick; return clockNow() }

    function clockNow() {
        var o = Number(Quickshell.env("DOTS_OVERVIEW_NOW"))
        return o > 0 ? o : Math.floor(Date.now() / 1000)
    }

    // ---- parsed documents ------------------------------------------------
    readonly property var parsedNow: { tick; texts; return Model.parseDoc(texts.now === undefined ? null : texts.now, nowTs) }
    readonly property var pAct: { tick; texts; return Model.parseDoc(texts.activity === undefined ? null : texts.activity, nowTs) }
    readonly property var pAtt: { tick; texts; return Model.parseDoc(texts.attention === undefined ? null : texts.attention, nowTs) }
    readonly property var pHeat: { tick; texts; return Model.parseDoc(texts.heatmap === undefined ? null : texts.heatmap, nowTs) }
    // mirror.json and meta.json are hourly or diagnostic: they never drive staleness.
    readonly property var pMirror: { tick; texts; return Model.parseDoc(texts.mirror === undefined ? null : texts.mirror, nowTs) }

    readonly property var nowDoc: parsedNow.doc
    readonly property var actDoc: pAct.doc
    readonly property var attDoc: pAtt.doc
    readonly property var heatDoc: pHeat.doc
    readonly property var mirrorDoc: pMirror.doc

    // Any of the four fast-cycle files stale, wrong version or unreadable: hollow ?
    // and every number dims to fgFaint. Missing files are "no data", not degraded.
    readonly property bool degraded: Model.isDegraded(parsedNow.status) || Model.isDegraded(pAct.status)
        || Model.isDegraded(pAtt.status) || Model.isDegraded(pHeat.status)
    readonly property bool dim: degraded

    // ---- derived ---------------------------------------------------------
    readonly property var counts: Model.counts(attDoc)
    readonly property int waiting: counts.waiting
    readonly property int failed: counts.failed
    readonly property var split: Model.splitItems(attDoc ? attDoc.items : [])
    readonly property var attentionItems: split.attention
    readonly property var nextItems: split.next
    readonly property var task: nowDoc ? nowDoc.task : null
    readonly property var focus: nowDoc ? nowDoc.focus : null
    readonly property bool focusRunning: !!focus && focus.state === "running"
    readonly property real focusElapsed: { tick; return Model.focusElapsed(focus, nowTs) }
    readonly property real focusTarget: focus ? (+focus.targetSec || 0) : 0
    readonly property string focusZone: (focus && focus.zone) ? focus.zone : (task && task.project ? task.project : "")
    readonly property var pill: Model.pillState(focus, counts, degraded)
    readonly property var today: (actDoc && actDoc.buckets) ? actDoc.buckets.today : null
    readonly property var sources: (attDoc && attDoc.sources) ? attDoc.sources : ({})

    // Lamp test: force every state visible for a moment (bar.lamp).
    property bool lamp: false
    function lampFor(ms) { lamp = true; lampTimer.interval = Math.max(100, ms); lampTimer.restart() }

    // Where the pill sits, written by the pill, read by the host for the card's notch.
    property string anchorScreen: ""
    property real anchorX: 0
    property real anchorBottom: 30

    // The item the Item page shows. openItem() also tells a visible panel to switch to it.
    property string selectedId: ""
    property int itemRequests: 0
    function openItem(id) { selectedId = id; itemRequests++ }

    // ---- ingest ----------------------------------------------------------
    property var warned: ({})

    function ingest(name, text) {
        var t = {}
        for (var k in texts) t[k] = texts[k]
        t[name] = text
        texts = t
        tick++
        var p = Model.parseDoc(text, clockNow())
        if (p.status === "version" || p.status === "bad") {
            // One line per failure class, not per file: a v2 writer breaks all six at once.
            if (!warned[p.status]) {
                warned[p.status] = true
                console.warn("overview: " + name + ".json " + (p.status === "version" ? "has v=" + p.v + ", expected 1" : "is not valid JSON") + "; showing ?")
            }
        }
    }

    // Called by the 1 s focus-ring timer; coalesces duplicate callers.
    property real lastBump: 0
    function bump() {
        var n = Date.now()
        if (n - lastBump < 900) return
        lastBump = n
        tick++
    }

    function itemById(id) {
        var items = attDoc ? attDoc.items : []
        for (var i = 0; i < items.length; i++) if (items[i].id === id) return items[i]
        return null
    }

    Timer {
        id: lampTimer
        onTriggered: root.lamp = false
    }

    // Staleness only: no file is read here.
    Timer {
        interval: 30000
        running: true
        repeat: true
        onTriggered: root.tick++
    }

    component Doc: FileView {
        id: doc
        required property string name
        path: root.dir + "/" + doc.name + ".json"
        watchChanges: true
        onFileChanged: doc.reload()
        onLoaded: root.ingest(doc.name, doc.text())
        onLoadFailed: root.ingest(doc.name, null)
    }

    Doc { name: "now" }
    Doc { name: "activity" }
    Doc { name: "attention" }
    Doc { name: "heatmap" }
    Doc { name: "mirror" }
    Doc { name: "meta" }
}
