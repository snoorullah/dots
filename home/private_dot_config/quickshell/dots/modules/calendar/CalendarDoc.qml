import Quickshell.Io
import QtQuick
import qs.modules.overview

// The optional calendar.json (v1) next to attention.json. Absent or unreadable -> null.
QtObject {
  id: root
  property var doc: null

  property FileView fv: FileView {
    path: Feed.dir + "/calendar.json"
    watchChanges: true
    onFileChanged: reload()
    onLoaded: { try { root.doc = JSON.parse(text()); } catch (e) { root.doc = null; } }
    onLoadFailed: root.doc = null
  }
}
