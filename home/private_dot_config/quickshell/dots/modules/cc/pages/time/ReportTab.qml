pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.modules.theme
import qs.modules.common
import qs.modules.cc.parts
import qs.modules.overview
import "../../js/Metrics.js" as M

// Report: a summary of the week, the month or the day written from the numbers on Progress.
// c copies it, Enter saves it as a file in ~/powerhouse/reports. Nothing leaves the machine:
// the copy goes to the local clipboard and the file is a plain write. Health and screen time
// are not in the report.
RowLayout {
  id: t
  property var parsed: null
  property var ks: ({ row: 0, col: 0, period: 1, weekOff: 0, detail: false, scroll: 0 })
  property bool inList: false
  property string status: ""
  signal periodPicked(int period)

  readonly property var doc: parsed ? parsed.doc : null
  readonly property bool ok: M.present(doc, "periods")
  readonly property string period: M.PERIODS[Math.max(0, Math.min(3, ks.period))]
  readonly property var lines: ok ? M.reportLines(doc, period) : []
  readonly property string text: ok ? M.reportText(doc, period) : ""
  readonly property string dir: Quickshell.env("HOME") + "/powerhouse/reports"
  readonly property string fileName: ok ? M.reportName(doc, period) : ""

  function copy() {
    if (!ok) { status = M.emptyText(parsed, "periods"); return }
    Quickshell.clipboardText = text
    status = "Copied " + scopeText(period) + " report to the clipboard."
  }
  function save() {
    if (!ok) { status = M.emptyText(parsed, "periods"); return }
    out.path = dir + "/" + fileName
    out.setText(text)
    status = "Saving to ~/powerhouse/reports/" + fileName + "."
  }
  function scopeText(p) { return p === "today" ? "today's" : "this " + p + "'s" }

  FileView {
    id: out
    atomicWrites: true
    printErrors: false
    onSaved: t.status = "Saved to ~/powerhouse/reports/" + t.fileName + "."
    onSaveFailed: t.status = "Could not write ~/powerhouse/reports/" + t.fileName + ". Does the folder exist?"
  }

  objectName: "timeReport"

  function nudge(f, dy) { if (f) f.contentY = Math.max(0, Math.min(Math.max(0, f.contentHeight - f.height), f.contentY + dy)) }
  function scrollBy(dy) { nudge(body, dy) }
  spacing: 16

  NoData {
    visible: !t.ok
    Layout.fillWidth: true
    Layout.alignment: Qt.AlignTop
    title: "Report"
    icon: "file-text"
    text: M.emptyText(t.parsed, "periods")
  }

  Card {
    id: repCard
    objectName: "reportCard"
    visible: t.ok
    Layout.fillWidth: true
    Layout.preferredWidth: 2
    Layout.fillHeight: true
    Layout.minimumHeight: 0
    Layout.minimumWidth: 0
    implicitHeight: 0
    pad: 20
    clip: true
    FocusRing { parent: repCard; kind: "pane"; focused: t.inList; radius: Theme.radius.card }
    Row {
      id: head
      spacing: 2
      Repeater {
        model: M.PERIODS
        Seg {
          required property string modelData
          required property int index
          objectName: "periodSeg"
          text: M.PERIOD_NAME[modelData]
          h: 26
          pad: 12
          on: t.ks.period === index
          onColor: Theme.color.outlineVariant
          onClicked: t.periodPicked(index)
        }
      }
    }
    Flickable {
      id: body
      objectName: "reportScroll"
      anchors.top: head.bottom
      anchors.topMargin: 16
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: actions.top
      anchors.bottomMargin: 12
      clip: true
      contentWidth: width
      contentHeight: lineCol.height
      boundsBehavior: Flickable.StopAtBounds
      Column {
        id: lineCol
        width: body.width
        spacing: 8
        Repeater {
          model: t.lines
          DText {
            required property string modelData
            required property int index
            width: lineCol.width
            text: index === 0 ? modelData.replace(/^# /, "") : modelData.replace(/^- /, "")
            role: index === 0 ? "title" : "body"
            wrapMode: Text.Wrap
          }
        }
      }
    }
    Column {
      id: actions
      anchors.bottom: parent.bottom
      width: parent.width
      spacing: 8
      Row {
        spacing: 8
        Btn { objectName: "copyReport"; text: "Copy"; icon: "clipboard-text"; keyHint: "c"; onClicked: t.copy() }
        Btn { objectName: "saveReport"; text: "Save as file"; icon: "file-text"; keyHint: "Enter"; onClicked: t.save() }
        Btn { objectName: "runReport"; text: "Run daily report"; icon: "list-plus"; keyHint: "r"; onClicked: Actions.report() }
      }
      DText { objectName: "reportStatus"; width: parent.width; text: t.status !== "" ? t.status : "Saves to ~/powerhouse/reports/" + t.fileName; role: "bodyS"; dim: true; elide: Text.ElideRight }
    }
  }

  Card {
    objectName: "reportAbout"
    visible: t.ok
    Layout.fillWidth: true
    Layout.preferredWidth: 1
    Layout.alignment: Qt.AlignTop
    Layout.minimumWidth: 0
    Column {
      width: parent.width
      spacing: 10
      Head { text: "How it is built"; icon: "notebook" }
      DText { width: parent.width; text: "Every line comes from the numbers on Progress for the same period. A line whose number is missing is left out, never filled with a zero."; role: "bodyS"; dim: true; wrapMode: Text.Wrap }
      DText { width: parent.width; text: "Nothing is sent. Copy goes to the clipboard on this machine and Save writes one file in ~/powerhouse/reports."; role: "bodyS"; dim: true; wrapMode: Text.Wrap }
      DText { width: parent.width; text: "Health and screen time are never part of it."; role: "bodyS"; dim: true; wrapMode: Text.Wrap }
    }
  }
}
