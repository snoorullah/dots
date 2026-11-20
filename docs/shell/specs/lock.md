# Lock screen (board: `Lock.dc.html`)

hyprlock, restyled. Unlock never depends on Quickshell.
Dynamic lines come from `dots-lock-info`; hyprlock has no QML, so no PNGs.
---
## 1. Layout (hyprlock labels, tokens from `palette.yaml`)

| Block | Where | Source |
|---|---|---|
| Out chip | centre, under the Hijri date | `dots-lock-info away` |
| Clock (Digits, Bricolage) | centre | `date` (1 s) |
| Gregorian + Hijri | under clock | `date`, `dots-lock-info date` |
| Host, net, volume, layout | top right | `dots-lock-info status` |
| TODAY SO FAR, 3 stats | left | `dots-lock-info stat1..stat3` |
| Day line, next prayer | left | `dots-lock-info day`, `prayer` |
| Music | bottom centre | `dots-lock-info music` |
| WHILE YOU WERE AWAY | right | `dots-lock-info away-counts` |
| Unlock field + hint | centre low | hyprlock `input-field` |
| Footer hints | bottom | static text |

No task names, ticket titles or mail subjects anywhere. Counts only.

## 2. Data per element (all local, no network)

1. **Out chip**: `~/.local/share/timetrack/away-intent.json` (`label`, `since`), else `now.json` clock `awayReason`.
   `logout` key reads "Logged out for today". Hidden when nothing declared.
2. **Date**: Gregorian by `strftime`; Hijri by the civil tabular calendar (may differ one day from sighting).
3. **Status**: hostname, `/sys/class/net` (wifi, wired, offline), `wpctl get-volume`, `hyprctl devices -j` keymap.
4. **Stats** vs 30-day average (`activity.json` buckets `today`, `month`/30; `salah.log`):
   worked, tasks done, salah on time. *Omitted, no source:* focus %, PRs merged.
5. **Day line**: worked of 8:00, logout = now + remaining, countdown.
6. **Next prayer**: `~/.config/adhd/prayer-times.conf` (iqamah times).
7. **Music**: `playerctl metadata` title and artist, only while Playing.
8. **Away counts**: `attention.json` items by kind (erp, mail, review, blocker, alert).
   Shown as growth since this lock began (baseline in `$XDG_RUNTIME_DIR`, keyed to the hyprlock pid).
   Without a hyprlock parent (tests), shows current totals.

## 3. Contract of `dots-lock-info`

1. `dots-lock-info <field> [--up HEX --down HEX --dim HEX]`, one field per call.
2. Output is Pango markup, XML-escaped. Colours come from the template, never hard-coded.
3. Never fails: missing or corrupt data prints nothing, exit 0.
4. Under 100 ms per call. Read-only except the baseline file. No network.
5. Env overrides for tests: `DOTS_STATE_DIR`, `DOTS_TIMETRACK_DIR`, `DOTS_ADHD_DIR`, `DOTS_LOCK_NOW`.

## 4. Stubbed or left out

1. Day timeline strip and Phosphor icons: hyprlock cannot draw them.
2. Row notes ("1 VIP", "warning"): not in `attention.json` counts.
3. Hyprlock cannot render offscreen. Checked by template render, cmd[] audit and unit tests.
