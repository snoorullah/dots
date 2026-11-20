import QtQuick
import QtTest
import "../js/Tray.js" as T

TestCase {
    name: "Tray"

    function app(id, title, status) { return { id: id, title: title, status: status, hasMenu: true } }
    property var apps: [app("a", "Team chat", "NeedsAttention"), app("b", "Mesh VPN", "Active"),
                        app("c", "Cloud sync", "Active"), app("d", "Backup agent", "Passive"), app("e", "", "Passive")]

    function test_groups_and_order() {
        var m = T.build(apps, "")
        compare(m.groups.length, 3)
        compare(m.groups[0].key, "attention")
        compare(m.groups[0].label, "NEEDS ATTENTION · 1")
        compare(m.groups[1].label, "ACTIVE · 2")
        compare(m.groups[2].label, "IDLE · 2")
        compare(m.total, 5)
    }

    function test_row_fields() {
        var m = T.build(apps, "")
        var r = m.groups[0].rows[0]
        compare(r.name, "Team chat")
        compare(r.status, "Needs attention")
        compare(r.tone, "waiting")
        compare(m.groups[1].rows[0].status, "Active")
        compare(m.groups[2].rows[1].name, "e")        // untitled app falls back to its id
        compare(m.groups[2].rows[0].tone, "none")
    }

    function test_filter_fuzzy() {
        var m = T.build(apps, "mvp")
        compare(m.total, 1)
        compare(m.groups[0].rows[0].id, "b")
        var n = T.build(apps, "zzz")
        compare(n.total, 0)
        compare(n.noMatch, true)
        compare(T.build(apps, "SYNC").total, 1)
    }

    function test_empty() {
        var m = T.build([], "")
        compare(m.empty, true)
        compare(m.groups.length, 0)
        compare(T.build(null, "").empty, true)
    }

    function test_unknown_status_is_idle() {
        var m = T.build([app("z", "Zed", "Bogus")], "")
        compare(m.groups[0].key, "idle")
    }
}
