#!/usr/bin/env bash
# dots-ops shared library — source it, never execute. Root and user both use this file.
: "${OPS_STATE:=${XDG_STATE_HOME:-$HOME/.local/state}/dots-ops}"
: "${OPS_ROOT_STATE:=/var/lib/dots-ops}"
: "${OPS_NOTIFY:=notify-send}"
: "${OPS_REMIND_SECS:=86400}"
: "${OPS_IS_ROOT:=$([ "$(id -u)" = 0 ] && echo 1 || echo 0)}"
mkdir -p "$OPS_STATE/state" "$OPS_STATE/pending" "$OPS_STATE/queue" "$OPS_STATE/locks" 2>/dev/null || true

ops_now() { date +%s; }

ops_log() {   # job level msg...
  local job=$1 level=$2; shift 2
  jq -cn --arg t "$(date -Is)" --arg j "$job" --arg l "$level" --arg m "$*" \
    '{t:$t,job:$j,level:$l,msg:$m}' >> "$OPS_STATE/log.jsonl"
  local size; size=$(stat -c%s "$OPS_STATE/log.jsonl" 2>/dev/null || echo 0)
  if [ "$size" -gt 10485760 ]; then
    mv "$OPS_STATE/log.jsonl" "$OPS_STATE/log.jsonl.$(date +%Y%m%d%H%M%S)"
    find "$OPS_STATE" -maxdepth 1 -name 'log.jsonl.*' -mtime +30 -delete
  fi
}

ops_run() {   # every mutating command goes through here
  if [ "${DOTS_OPS_DRY_RUN:-0}" = 1 ]; then printf '+ %s\n' "$*"; else "$@"; fi
}

ops_notify() {   # urgency title body — queue on failure (no daemon, TTY)
  local u=$1 t=$2 b=$3
  "$OPS_NOTIFY" -a dots-ops -u "$u" "$t" "$b" 2>/dev/null && return 0
  jq -cn --arg u "$u" --arg t "$t" --arg b "$b" '{u:$u,t:$t,b:$b}' \
    > "$OPS_STATE/queue/$(date +%s%N).json"
}

ops_flush_queue() {
  local f
  for f in "$OPS_STATE"/queue/*.json; do
    [ -e "$f" ] || continue
    "$OPS_NOTIFY" -a dots-ops -u "$(jq -r .u "$f")" "$(jq -r .t "$f")" "$(jq -r .b "$f")" 2>/dev/null \
      && rm -f "$f"
  done
}

ops_state() {   # job status summary — notifies on change (user context only)
  local job=$1 st=$2 sum=$3 dir prev notified now
  now=$(ops_now)
  if [ "$OPS_IS_ROOT" = 1 ]; then dir=$OPS_ROOT_STATE; mkdir -p "$dir"; else dir=$OPS_STATE/state; fi
  prev=$(jq -r '.status // "none"' "$dir/$job.json" 2>/dev/null || echo none)
  notified=$(jq -r '.notified // 0' "$dir/$job.json" 2>/dev/null || echo 0)
  local send=""
  if [ "$OPS_IS_ROOT" != 1 ]; then
    if [ "$st" != ok ] && { [ "$prev" != "$st" ] || [ $((now - notified)) -ge "$OPS_REMIND_SECS" ]; }; then send=$st
    elif [ "$st" = ok ] && [ "$prev" != ok ] && [ "$prev" != none ]; then send=recovered; fi
  fi
  case $send in
    fail)      ops_notify critical "dots-ops: $job failed" "$sum"; notified=$now ;;
    warn)      ops_notify normal   "dots-ops: $job" "$sum"; notified=$now ;;
    recovered) ops_notify low      "dots-ops: $job recovered" "$sum"; notified=0 ;;
  esac
  jq -cn --arg j "$job" --arg s "$st" --arg m "$sum" --argjson t "$now" --argjson n "$notified" \
    '{job:$j,status:$s,summary:$m,changed:$t,notified:$n}' > "$dir/$job.json.tmp" && mv "$dir/$job.json.tmp" "$dir/$job.json"
  ops_log "$job" "$st" "$sum"
}

ops_lock() {   # job — exits 0 if another instance holds the lock
  exec {OPS_LOCK_FD}>"$OPS_STATE/locks/$1.lock"
  flock -n "$OPS_LOCK_FD" || { ops_log "$1" info "already running; skipped"; exit 0; }
}
