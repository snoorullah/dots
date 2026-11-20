import QtQuick
import QtTest
import "../js/Profiles.js" as P

TestCase {
  name: "Profiles"

  function test_owner() {
    compare(P.profileOf(1), "Agents")
    compare(P.profileOf(2), "Web")
    compare(P.profileOf(3), "Dev")
    compare(P.profileOf(4), "Comms")
    compare(P.profileOf(5), "Comms")
    compare(P.profileOf(7), "Notes")
    compare(P.profileOf(8), "Other")
    compare(P.profileOf(10), "Other")
  }
  function test_unowned_is_other() {
    compare(P.profileOf(11), "Other")
    compare(P.profileOf("12"), "Other")
  }
  function test_invalid() {
    compare(P.profileOf(-1), "")
    compare(P.profileOf(0), "")
    compare(P.profileOf(undefined), "")
    compare(P.profileOf("x"), "")
  }
  function test_sticky_keeps_last_on_special() {
    compare(P.stickyProfile(-99, "Dev"), "Dev")
    compare(P.stickyProfile(0, "Web"), "Web")
    compare(P.stickyProfile(-1, ""), "")
  }
  function test_sticky_follows_real_workspace() {
    compare(P.stickyProfile(2, "Dev"), "Web")
    compare(P.stickyProfile(12, "Dev"), "Other")
  }
  function test_no_workspace_in_two_profiles() {
    var seen = {}
    for (var i = 0; i < P.list.length; i++)
      for (var j = 0; j < P.list[i].ws.length; j++) {
        verify(!seen[P.list[i].ws[j]], "ws " + P.list[i].ws[j] + " owned twice")
        seen[P.list[i].ws[j]] = true
      }
  }
  function test_keys_unique() {
    var seen = {}
    for (var i = 0; i < P.list.length; i++) {
      verify(!seen[P.list[i].key])
      seen[P.list[i].key] = true
    }
  }
  function test_primary() {
    compare(P.primary("Comms"), 4)
    compare(P.primary("Other"), 8)
    compare(P.primary("Nope"), -1)
  }
  function test_workspaces_of() {
    var e = [{ id: 1 }, { id: 4 }, { id: 5 }, { id: 7 }, { id: 12 }]
    compare(P.workspacesOf(e, "Comms").length, 2)
    compare(P.workspacesOf(e, "Comms")[1].id, 5)
    compare(P.workspacesOf(e, "Other").length, 1)
    compare(P.workspacesOf(e, "Other")[0].id, 12)
    compare(P.workspacesOf(e, "Dev").length, 0)
    compare(P.workspacesOf(undefined, "Dev").length, 0)
  }
  function test_bar_list() {
    var l = P.barList()
    compare(l.length, 7)
    compare(l[0].name, "Agents")
    compare(l[0].icon, "sparkle")
  }
}
