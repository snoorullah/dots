import QtQuick
import QtTest
import "../js/Wall.js" as W
import "../js/Acts.js" as A

TestCase {
    name: "Wall"

    function fixture() {
        var x = new XMLHttpRequest()
        x.open("GET", Qt.resolvedUrl("fixtures/walls.json"), false)
        x.send()
        return JSON.parse(x.responseText)
    }
    function mk(st, extra) {
        var f = fixture()
        var s = W.initial()
        for (var k in st) s[k] = st[k]
        f.st = s
        for (var e in extra) f[e] = extra[e]
        return W.build(f)
    }

    function test_default_selects_the_current_wallpaper_and_is_not_previewing() {
        var m = mk({})
        compare(m.mode, "grid")
        compare(m.selPath, "/w/wallpaper-03.png")
        verify(!m.previewing)
        verify(!m.setEnabled)
        compare(m.tiles.length, 8)
        verify(m.tiles[2].isCur)
        compare(m.tiles[2].ring, "accent")
    }
    function test_arrowing_previews_and_enables_set() {
        var m = mk({ sel: "/w/wallpaper-05.png" })
        verify(m.previewing)
        verify(m.setEnabled)
        compare(m.selName, "wallpaper-05")
        compare(m.tiles[4].ring, "accent")
        compare(m.tiles[2].ring, "cur")
    }
    function test_broken_tile_is_dimmed_never_selectable_and_counted() {
        var f = fixture(); f.folder.skipped = 1
        var m = mk({}, { folder: f.folder })
        verify(m.tiles[3].isBroken)
        verify(m.tiles[3].dim)
        compare(m.folder.skippedText, "1 skipped")
        var r = W.nav(m, W.initial(), "right")        // 03 -> 04 is broken: skip to 05
        compare(r.st.sel, "/w/wallpaper-05.png")
        var broken = mk({ sel: "/w/wallpaper-04.png" })
        verify(!broken.setEnabled)
    }
    function test_grid_has_four_columns() {
        var m = mk({})
        compare(W.nav(m, W.initial(), "down").st.sel, "/w/wallpaper-07.png")
        compare(W.nav(m, W.initial(), "up").st.sel, undefined)   // row 0: nothing to go up to
        var left = W.nav(mk({ sel: "/w/wallpaper-01.png" }), W.initial(), "left")
        compare(left.st.sel, "/w/wallpaper-01.png")
    }
    function test_enter_applies_with_palette_output_and_space_stays() {
        var m = mk({ sel: "/w/wallpaper-05.png", monitor: 1 })
        var e = W.nav(m, W.initial(), "enter").side
        compare(e.type, "apply")
        compare(e.path, "/w/wallpaper-05.png")
        compare(e.output, "DP-1")
        compare(e.palette, "wallpaper")
        verify(!e.stay)
        verify(W.nav(m, W.initial(), "space").side.stay)
    }
    function test_enter_on_the_current_wallpaper_closes() {
        compare(W.nav(mk({}), W.initial(), "enter").side.type, "close")
    }
    function test_esc_reverts_a_preview_then_clears_the_filter_then_closes() {
        var pv = mk({ sel: "/w/wallpaper-05.png" })
        var r = W.nav(pv, W.initial(), "esc")
        compare(r.side.type, "restore")
        compare(r.st.sel, "/w/wallpaper-03.png")
        var q = mk({ query: "03" }, {})
        compare(W.nav(q, { query: "03" }, "esc").st.query, "")
        compare(W.nav(mk({}), W.initial(), "esc").side.type, "close")
    }
    function test_palette_source_changes_what_the_mini_shell_uses() {
        var w = mk({ sel: "/w/wallpaper-05.png", extract: 0 })
        compare(w.pal.surface, "#2a1a1c")
        compare(w.palette, "wallpaper")
        var c = mk({ sel: "/w/wallpaper-05.png", extract: 1 })
        compare(c.pal.surface, "#0f1a1f")                       // the current wallpaper's
        compare(c.palette, "current")
        var md = mk({ sel: "/w/wallpaper-05.png", extract: 2 })
        compare(md.pal.src, "mode")
        compare(md.notice.icon, "moon")
        compare(md.palette, "current")
        compare(W.nav(w, W.initial(), "3").st.extract, 2)
    }
    function test_low_contrast_is_tuned_and_can_be_shown_untuned() {
        var t = mk({ sel: "/w/wallpaper-08.png" })
        verify(t.contrast.tuned)
        verify(t.contrast.canUntune)
        compare(t.contrast.text, "4.5:1 passes AA")
        compare(t.contrast.untuneLabel, "Show untuned")
        compare(t.pal.text, "#1a2a31")
        var u = mk({ sel: "/w/wallpaper-08.png", untuned: true })
        compare(u.contrast.text, "2.6:1 fails AA")
        verify(!u.contrast.pass)
        verify(!u.contrast.tuned)
        compare(u.contrast.untuneLabel, "Use tuned")
        compare(u.pal.text, "#5f6f76")
    }
    function test_unknown_palette_shows_no_contrast_row_instead_of_a_guess() {
        var m = mk({ sel: "/w/wallpaper-02.png" })
        verify(!m.palKnown)
        verify(!m.contrast.show)
        compare(m.contrast.text, "")
    }
    function test_filter_by_name_or_tag_and_count_text() {
        var m = mk({ query: "warm" })
        compare(m.tiles.length, 1)
        compare(m.tiles[0].name, "wallpaper-05")
        compare(m.search.text, "1 of 12")
        verify(m.search.show)
        compare(mk({ query: "zzz" }).tiles.length, 0)
        compare(mk({ query: "zzz" }).selPath, "")
    }
    function test_large_folder_counts_use_thousands_separators() {
        var f = fixture(); f.folder.count = 1284
        var m = mk({ query: "wallpaper" }, { folder: f.folder })
        compare(m.folder.count, "1,284")
        compare(m.search.text, "8 of 1,284")
    }
    function test_empty_and_loading_states() {
        var e = mk({}, { items: [], folder: { name: "", count: 0, exists: false } })
        compare(e.mode, "empty")
        compare(e.folder.name, "No folder")
        compare(mk({ loading: true }).mode, "loading")
    }
    function test_notices_salah_over_mode_over_paused() {
        var s = mk({ extract: 2 }, { salah: true })
        compare(s.notice.icon, "mosque")
        compare(s.palette, "current")
        compare(s.shuffle.label, "Shuffle off")
        var p = mk({}, { shuffle: true, focusMode: true })
        compare(p.notice.icon, "timer")
        compare(p.shuffle.label, "Hourly, paused")
        compare(p.shuffle.mid, "paused")
        compare(mk({}, { shuffle: true, nextAt: "15:00" }).shuffle.mid, "next")
        compare(mk({}, { shuffle: true, salah: true }).shuffle.label, "Held, salah")
        compare(mk({}).notice, null)
    }
    function test_monitor_cycles_through_all_then_each_display() {
        var m = mk({})
        compare(m.target.label, "All monitors")
        compare(m.target.output, "")
        compare(W.nav(m, W.initial(), "m").st.monitor, 1)
        compare(mk({ monitor: 2 }).target.output, "HDMI-A-1")
        compare(W.nav(mk({ monitor: 2 }), { monitor: 2 }, "m").st.monitor, 0)
    }
    function test_keys_for_shuffle_fav_folder_lock_undo() {
        var m = mk({}, { lock: true })
        compare(W.nav(m, W.initial(), "s").side.on, true)
        compare(W.nav(m, W.initial(), "f").side.path, "/w/wallpaper-03.png")
        compare(W.nav(m, W.initial(), "g").st.folderPrompt, true)
        compare(mk({ folderPrompt: true }).search.prompt, true)
        compare(W.nav(mk({ folderPrompt: true }), { folderPrompt: true }, "esc").st.folderPrompt, false)
        compare(W.nav(m, W.initial(), "l").side.on, false)
        compare(W.nav(m, W.initial(), "u").side, null)
        var t = mk({ toast: true })
        compare(W.nav(t, { toast: true }, "u").side.type, "undo")
    }
    function test_question_mark_toggles_the_key_legend() {
        compare(W.nav(mk({}), W.initial(), "?").st.keys, true)
        verify(mk({ keys: true }).keys)
        compare(mk({}).legend.length, 10)
    }
    function test_suggestion_only_when_open_and_not_current() {
        var f = fixture()
        verify(mk({}, { suggest: "/w/wallpaper-07.png" }).suggestion)
        verify(!mk({ aiOpen: false }, { suggest: "/w/wallpaper-07.png" }).suggestion)
        verify(mk({}, { suggest: "/w/wallpaper-07.png" }).tiles[6].isSug)
    }

    function test_argv_builders_whitelist_verbs_and_validate_paths() {
        compare(A.wp("/w.py", ["scan"]).join("|"), "python3|/w.py|scan")
        compare(A.wp("/w.py", ["rm", "-rf"]), null)
        compare(A.wp("/w.py", []), null)
        compare(A.apply("/w.py", "/w/a.png", "", "wallpaper").join("|"), "python3|/w.py|apply|/w/a.png|--palette|wallpaper")
        compare(A.apply("/w.py", "/w/a.png", "DP-1", "mode").join("|"), "python3|/w.py|apply|/w/a.png|--output|DP-1|--palette|mode")
        compare(A.apply("/w.py", "a.png", "", "mode"), null)                 // not absolute
        compare(A.apply("/w.py", "-rf", "", "mode"), null)
        compare(A.apply("/w.py", "/w/a.png", "DP-1; reboot", "mode"), null)
        compare(A.apply("/w.py", "/w/a.png", "", "evil").join("|"), "python3|/w.py|apply|/w/a.png")
        compare(A.preview("/w.py", "/w/a.png").join("|"), "python3|/w.py|preview|/w/a.png")
    }
}
