#!/usr/bin/env bash
# Focus dashboard: taskwarrior context + active task + timewarrior tracking
# Palette: green=#50fa7b red=#ff4d4d orange=#ff9e3b purple=#bd93f9 fg=#f8f8f2 muted=#585880

set -eu

RESET="#[fg=#585880,bg=default,nobold]"

# ── Timewarrior tracking status ───────────────────────────────────────
tracking=false
timer=""
if command -v timew >/dev/null 2>&1; then
  duration=$(timew get dom.active.duration 2>/dev/null) || duration=""
  if [ -n "$duration" ]; then
    tracking=true
    hours=$(printf %s "$duration" | grep -oP '\d+(?=H)' || echo "0")
    minutes=$(printf %s "$duration" | grep -oP '\d+(?=M)' || echo "0")
    timer="#[fg=#ff9e3b,bold] 󱎫 $(printf "%s:%02d" "$hours" "$minutes")#[nobold]"
  fi
fi

# ── Taskwarrior context ───────────────────────────────────────────────
context=""
if command -v task >/dev/null 2>&1; then
  ctx=$(task _get rc.context 2>/dev/null) || ctx=""
  [ -n "$ctx" ] && [ "$ctx" != "none" ] && context="#[fg=#585880] [$ctx]"
fi

# ── Active task description ───────────────────────────────────────────
desc=""
if command -v task >/dev/null 2>&1; then
  desc=$(task rc.verbose=nothing rc.report.next.columns=description rc.report.next.labels= +ACTIVE next limit:1 2>/dev/null | head -1 | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')

  if [ -z "$desc" ]; then
    desc=$(task rc.verbose=nothing rc.report.next.columns=description rc.report.next.labels= next limit:1 2>/dev/null | head -1 | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
  fi
fi

[ -z "$desc" ] && [ "$tracking" = false ] && exit 0

if [ -n "$desc" ] && [ ${#desc} -gt 25 ]; then
  desc="${desc:0:22}..."
fi

# ── Build output ──────────────────────────────────────────────────────
if [ "$tracking" = true ]; then
  focus="#[fg=#50fa7b,bold]󰔱"
  task_text="#[fg=#f8f8f2,nobold] ${desc}"
else
  if [ -n "$desc" ]; then
    focus="#[fg=#ff4d4d,dim]󰏤#[nodim]"
    task_text="#[fg=#585880] ${desc}"
  else
    focus="#[fg=#50fa7b,bold]󰔱"
    task_text=""
  fi
fi

printf " %s%s%s%s$RESET " "$focus" "$context" "$task_text" "$timer"
