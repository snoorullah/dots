# Moments (unit spec)

Board: `Moments.dc.html`, four cards. Code: `modules/moments/`, `modules/notif/Toast.qml`.

---

## 1. Quick capture (`QuickCapture`, `CaptureCard`)

1. Centred 480 px card: title, "Thought" input (48 high), key hints, Press Enter button.
2. States: empty, typing, captured (note card appears, window closes after 2.4 s).
3. Enter writes a local task: argv `task add +capture -- <text>` (Taskwarrior, exec argv only).
   `dots-task new` is NOT used: it would rebind the running task.
4. `Tab agent` and `Ctrl+R remind` render dimmed, tooltip "read-only for now", do nothing.
5. Esc cancels. Window property `bool shown`; keyboard focus is exclusive while shown.
6. Captured note: "You're already back on {task}." from `now.json` task. Agent enrichment lines
   (project, tags, person) are shown only if `enrichment` is set; nothing sets it yet (stub).

## 2. Re-nudge (`Toast.qml`, `js/Moments.js`)

1. A waiting toast (app `Claude Code`) that times out or is clicked away is not lost.
2. It returns softly (fade 240 ms) at 10 min, then every 30 min, while the notification is still
   tracked (the agent has not resumed, the user has not cleared it).
3. `NudgeCard` is the board's toast face: title, amber age, detail, Jump there, Dismiss.
   Jump there runs `dots-jump <ref>` when a ref is given, else is disabled.
   After Dismiss, `NudgeNote` reads "The toast is gone. The bar still reads (amber circle) 1 - 2m."
4. Amber circle = waiting. Nothing pulses.

## 3. Return chip (`ReturnChip`)

1. Pill, 32 high, amber wash: arrow, "Detour 4m · back to HD 4412", key hint `Super+B`.
2. Data: `Feed.nowDoc` (`now.json`): detour is active while `clock.state == "away"`;
   count starts at `clock.sinceTs`; target is `task.ref` (else `task.desc`).
3. Hidden (zero width) when there is no detour. Click runs `dots-jump <ref>`. Super+B is the
   integration's keybind: it should call the same `ReturnChip.back()`.
4. After returning: `ReturnNote` "Back on HD 4412, same window." (the +XP badge is not built).

## 4. Handed to an agent (`HandedCard`)

1. Read-only: heading, ask line, timeline (time column 44 px + text), permission footer.
2. Data: `handed` property, `{ask, said, steps[{at,text}], permission}`. No writer exists yet,
   so integration passes it or leaves it null (card then shows "Nothing handed over").
3. "See what was sent" is disabled, tooltip "read-only for now".

## 5. Tokens and icons

Colours, radii, spacing, type from `Theme.*` only. Icons through `Icon`. Registry lacks
note-pencil, arrow-elbow-down-left, bell-ringing, arrow-u-down-left, paper-plane-tilt,
clock-clockwise; `MomentIcons` maps stand-ins and is the one place to swap them.

## 6. Not built

+XP badge, agent enrichment writer, Tab agent, Ctrl+R remind, "See what was sent".
