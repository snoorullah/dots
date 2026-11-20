import QtQuick
import QtTest
import "../js/BarModel.js" as M

TestCase {
  name: "BarModel"

  function test_logout_left() {
    compare(M.logoutLeft(undefined), "")
    compare(M.logoutLeft(0), "08:00")
    compare(M.logoutLeft(3 * 3600 + 25 * 60), "04:35")
    compare(M.logoutLeft(8 * 3600 + 12 * 60), "+00:12")
    compare(M.logoutLeft(3600, 2 * 3600), "01:00")
  }
  function test_focus_left() {
    compare(M.focusLeft(null, 100), "")
    compare(M.focusLeft({ state: "idle", startedAt: 0, targetSec: 1500 }, 100), "")
    compare(M.focusLeft({ state: "running", startedAt: 1000, targetSec: 1500 }, 1000), "25:00")
    compare(M.focusLeft({ state: "running", startedAt: 1000, targetSec: 1500 }, 1061), "23:59")
    compare(M.focusLeft({ state: "running", startedAt: 1000, targetSec: 5400 }, 1000), "1:30:00")
    compare(M.focusLeft({ state: "running", startedAt: 1000, targetSec: 1500 }, 2600), "")
  }
  function test_todays_only() {
    var items = [{ src: "gh", ageSec: 600 }, { src: "gh", ageSec: 23 * 86400 }, { src: "herdr", ageSec: 99999 }]
    compare(M.todaysOnly(items, 10000, 10000 - 3600).length, 2)
    compare(M.todaysOnly(items, 10000, 10000 - 3600)[0].ageSec, 600)
    compare(M.todaysOnly(items, 10000, 0).length, 2)
  }
  function test_age() {
    compare(M.age(0), "now")
    compare(M.age(45), "now")
    compare(M.age(60), "1m")
    compare(M.age(720), "12m")
    compare(M.age(3599), "59m")
    compare(M.age(7200), "2h")
    compare(M.age(200000), "2d")
    compare(M.age(-3), "now")
    compare(M.age(undefined), "now")
    compare(M.age(NaN), "now")
  }

  function test_waits_oldest_first_and_cap() {
    var items = [
      { id: "a", kind: "alert", ageSec: 120 },
      { id: "b", kind: "review", ageSec: 180 },
      { id: "c", kind: "agent", ageSec: 720 },
      { id: "d", kind: "mail", ageSec: 60 },
      { id: "e", kind: "ticket", ageSec: 30 },
    ]
    var r = M.waitSymbols(items, 3)
    compare(r.shown.length, 3)
    compare(r.more, 2)
    compare(r.shown[0].id, "c")
    compare(r.shown[0].age, "12m")
    compare(r.shown[0].icon, "sparkle")
    compare(r.shown[0].popout, "agent")
    compare(r.shown[1].id, "b")
    compare(r.shown[1].popout, "waiting")
    compare(r.shown[2].id, "a")
    compare(r.shown[2].tone, "failed")
    compare(r.shown[2].icon, "warning")
  }

  function test_waits_empty_and_junk() {
    compare(M.waitSymbols([], 3).shown.length, 0)
    compare(M.waitSymbols(null, 3).more, 0)
    var r = M.waitSymbols([null, { id: "x", kind: "weird", ageSec: 5 }], 3)
    compare(r.shown.length, 1)
    compare(r.shown[0].icon, "circle")
    compare(r.shown[0].tone, "waiting")
  }

  function test_waits_no_more_when_exactly_cap() {
    var r = M.waitSymbols([{ id: "1", kind: "review", ageSec: 1 }, { id: "2", kind: "vip", ageSec: 2 },
                           { id: "3", kind: "mail", ageSec: 3 }], 3)
    compare(r.shown.length, 3)
    compare(r.more, 0)
  }

  function test_salah_runway() {
    var now = new Date(2026, 9, 30, 22, 28, 0)
    compare(M.salahLabel("​→ Isha 22:52", now), "Isha 24m")
    compare(M.salahLabel("Fajr 05:10", now), "Fajr 6h 42m")
    compare(M.salahLabel("Isha 22:28", now), "Isha now")
    compare(M.salahLabel("", now), "")
    compare(M.salahLabel("—", now), "")
    compare(M.salahLabel("Maghrib soon", now), "Maghrib soon")
  }

  function test_workspaces() {
    var ws = [{ id: 1, name: "infra" }, { id: 2, name: "2" }]
    var tl = [
      { wsId: 1, cls: "herdr", icon: "/i/herdr.png" },
      { wsId: 1, cls: "ghostty", icon: "/i/g.png" },
      { wsId: 1, cls: "ghostty", icon: "/i/g.png" },
      { wsId: 1, cls: "code", icon: "" },
      { wsId: 1, cls: "zen", icon: "/i/z.png" },
      { wsId: 2, cls: "slack", icon: "/i/s.png" },
    ]
    var r = M.workspaces(ws, tl, 1, 3)
    compare(r.length, 2)
    compare(r[0].active, true)
    compare(r[0].apps.length, 3)
    compare(r[0].apps[1].cls, "ghostty")
    compare(r[0].more, 1)
    compare(r[1].active, false)
    compare(r[1].apps[0].icon, "/i/s.png")
    compare(M.workspaces(null, null, 1, 3).length, 0)
  }

  function test_fault() {
    compare(M.fault({ level: "ok", text: "", stale: false }, false).kind, "none")
    var f = M.fault({ level: "fail", text: "backup failed", stale: false }, false)
    compare(f.kind, "failed")
    compare(f.text, "backup failed")
    var u = M.fault({ level: "ok", text: "", stale: true }, false)
    compare(u.kind, "unknown")
    compare(M.fault({ level: "ok", text: "", stale: false }, true).kind, "unknown")
    // a failure outranks a stale source
    compare(M.fault({ level: "fail", text: "x", stale: true }, true).kind, "failed")
    // warn is something waiting, not a fault
    compare(M.fault({ level: "warn", text: "y", stale: false }, false).kind, "none")
    compare(M.fault(null, false).kind, "none")
  }

  function test_metrics() {
    var m = M.metrics({ prs: 3, tasks: 2, xp: 154 })
    compare(m.length, 3)
    compare(m[0].key, "prs")
    compare(m[0].text, "3")
    compare(m[2].key, "xp")
    compare(m[2].text, "+154")
    compare(m[2].accent, true)
    var w = M.metrics({ tasks: 0, workedSec: 7500 })
    compare(w.length, 2)
    compare(w[1].text, "2h 05m")
    compare(M.metrics({}).length, 0)
    compare(M.metrics(null).length, 0)
  }

  function test_taskText() {
    compare(M.taskText({ ref: "HD 4412", desc: "Rotate deploy keys" }), "HD 4412 Rotate deploy keys")
    compare(M.taskText({ desc: "Only desc" }), "Only desc")
    compare(M.taskText(null), "")
  }

  function test_profileActive() {
    var p = ["Agents", "Dev", "Web"]
    compare(M.activeProfile(p, "dev"), "Dev")
    compare(M.activeProfile(p, "3"), "")
    compare(M.activeProfile(p, ""), "")
  }
}
