#!/usr/bin/env bash
# dots-ops shared library — source it, never execute. Root and user both use this file.
: "${OPS_IS_ROOT:=$([ "$EUID" = 0 ] && echo 1 || echo 0)}"
: "${OPS_ROOT_STATE:=/var/lib/dots-ops}"   # root job statuses + ask files (0755/0644, read by the user relay)
if [ "$OPS_IS_ROOT" = 1 ]; then   # root has no usable HOME under systemd/sudo; its own log/locks live here
  : "${OPS_STATE:=$OPS_ROOT_STATE/root}"
else
  : "${OPS_STATE:=${XDG_STATE_HOME:-$HOME/.local/state}/dots-ops}"
fi
: "${OPS_NOTIFY:=notify-send}"
: "${OPS_REMIND_SECS:=86400}"
mkdir -p "$OPS_STATE/state" "$OPS_STATE/pending" "$OPS_STATE/queue" "$OPS_STATE/locks" 2>/dev/null || true
if [ "$OPS_IS_ROOT" = 1 ]; then chmod 700 "$OPS_STATE/locks" 2>/dev/null || true; fi   # nobody else may hold root's locks

ops_now() { date +%s; }

ops_file_trusted() {   # path... — 0 if every path exists, is owned by root and is not group/other-writable (R20)
  local f m
  for f in "$@"; do
    [ -e "$f" ] && [ "$(stat -Lc %u "$f")" = 0 ] || return 1
    m=$(stat -Lc %a "$f"); [ $(( 0$m & 022 )) = 0 ] || return 1
  done
}

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

ops_signal() {   # refresh the Waybar custom/ops module (user context only; signal 9 = RTMIN+9)
  [ "$OPS_IS_ROOT" = 1 ] || pkill -RTMIN+9 -x waybar 2>/dev/null || true
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
  ops_signal
}

ops_lock() {   # job — exits 0 if another instance holds the lock
  exec {OPS_LOCK_FD}>"$OPS_STATE/locks/$1.lock"
  flock -n "$OPS_LOCK_FD" || { ops_log "$1" info "already running; skipped"; exit 0; }
}

: "${OPS_ASK_UI:=1}"
: "${OPS_SUDO:=sudo -n}"   # R8: never prompt for a password from a background job
if [ -z "${OPS_RUNNER:-}" ]; then   # R1: NixOS puts the runner in the system profile
  if [ -x /run/current-system/sw/bin/dots-ops-run ]; then OPS_RUNNER=/run/current-system/sw/bin/dots-ops-run
  else OPS_RUNNER=/usr/local/bin/dots-ops-run; fi
fi
if [ "$OPS_IS_ROOT" = 1 ]; then   # R3: root has no XDG_RUNTIME_DIR; the flag lives in /run/dots-ops
  : "${OPS_IDLE_FLAG:=/run/dots-ops/idle}"
else
  : "${OPS_IDLE_FLAG:=${XDG_RUNTIME_DIR:-/run/user/$EUID}/dots-ops/idle}"
fi
: "${OPS_POWER_DIR:=/sys/class/power_supply}"

ops_ask() {   # job question action [alt_action] — one live pending per job
  local job=$1 q=$2 act=$3 now; now=$(ops_now)
  if [ "$OPS_IS_ROOT" = 1 ]; then   # root cannot reach the desktop: leave an ask file for `dots-ops relay`
    mkdir -p "$OPS_ROOT_STATE"
    jq -cn --arg q "$q" --arg a "$act" --arg alt "${4:-}" --argjson t "$now" \
      '{question:$q,action:$a,asked:$t} + (if $alt == "" then {} else {alt_action:$alt} end)' \
      > "$OPS_ROOT_STATE/ask-$job.json.tmp" && mv "$OPS_ROOT_STATE/ask-$job.json.tmp" "$OPS_ROOT_STATE/ask-$job.json"
    ops_log "$job" ask "$q"
    return 0
  fi
  ops_ask_pending "$job" && return 0
  jq -cn --arg q "$q" --arg a "$act" --argjson t "$now" --argjson e $((now + 86400)) \
    '{question:$q,action:$a,asked:$t,expires:$e,snooze_until:0}' > "$OPS_STATE/pending/$job.json"
  ops_log "$job" ask "$q"
  [ "$OPS_ASK_UI" = 1 ] && command -v setsid >/dev/null && setsid -f dots-ops-ask "$job" >/dev/null 2>&1
  return 0
}

ops_ask_pending() {   # 0 = live pending (or snoozed) exists
  local f="$OPS_STATE/pending/$1.json" now; now=$(ops_now)
  [ -f "$f" ] || return 1
  local exp snz
  if ! exp=$(jq -er .expires "$f" 2>/dev/null) || ! snz=$(jq -er .snooze_until "$f" 2>/dev/null); then
    rm -f "$f"; ops_log "$1" warn "corrupt pending removed"; return 1
  fi
  if [ "$exp" -le "$now" ] && [ "$snz" -le "$now" ]; then
    rm -f "$f"; ops_log "$1" info "approval expired; skipped"; return 1
  fi
  return 0
}

ops_answer() {   # job approve|skip|snooze
  local job=$1 ans=$2 f="$OPS_STATE/pending/$1.json" act rc=0
  [ -f "$f" ] || return 0
  act=$(jq -r .action "$f" 2>/dev/null)
  case $ans in
    approve)
      if ! ops_ask_pending "$job"; then ops_log "$job" info "approval expired; not run"; ops_signal; return 0; fi
      rm -f "$f"; ops_log "$job" approve "$act"
      case $act in
        user:*) bash -c "${act#user:}" || rc=$? ;;
        root:*)
          local ra sudo_cmd
          read -ra ra <<< "${act#root:}"
          read -ra sudo_cmd <<< "$OPS_SUDO"
          "${sudo_cmd[@]}" "$OPS_RUNNER" "${ra[0]}" "${ra[1]}" || rc=$? ;;
      esac
      [ "$rc" -eq 0 ] || ops_state "$job" warn "approved action failed (rc=$rc): $act" ;;
    skip)   rm -f "$f"; ops_log "$job" skip "$act" ;;
    snooze) jq --argjson s $(( $(ops_now) + 86400 )) '.snooze_until=$s' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
            ops_log "$job" snooze "$act" ;;
  esac
  ops_signal
  return "$rc"
}

ops_live_asks() {   # prints "job<TAB>question" per live, un-snoozed pending (user context)
  local f job now; now=$(ops_now)
  for f in "$OPS_STATE"/pending/*.json; do
    [ -f "$f" ] || continue
    job=$(basename "$f" .json)
    ops_ask_pending "$job" || continue
    [ "$(jq -r '.snooze_until // 0' "$f" 2>/dev/null)" -gt "$now" ] 2>/dev/null && continue   # snoozed: hidden until it wakes
    printf '%s\t%s\n' "$job" "$(jq -r '.question // "" | gsub("[\n\t]";" ")' "$f" 2>/dev/null)"
  done
}

ops_state_entries() {   # one JSON object per line per state file; an unreadable file becomes a warn entry (never fails open)
  local f job
  for f in "$OPS_STATE"/state/*.json; do
    [ -e "$f" ] || continue
    job=$(basename "$f" .json)
    jq -ce 'select(type=="object" and (.status|type)=="string" and (.job|type)=="string") | {job,status,summary:(.summary // ""),changed:(.changed // 0)}' "$f" 2>/dev/null | grep . \
      || jq -cn --arg j "$job" '{job:$j,status:"warn",summary:"unreadable state",changed:null}'
  done
}

ops_waybar_json() {   # one JSON object for the Waybar custom/ops module
  local states asks
  states=$(ops_state_entries | jq -cs '.' 2>/dev/null)
  asks=$(ops_live_asks | jq -Rsc 'split("\n") | map(select(length>0) | split("\t") | {job:.[0], q:(.[1:]|join(" "))})' 2>/dev/null)
  jq -nc --argjson s "${states:-[]}" --argjson a "${asks:-[]}" '
    ([$s[] | select(.status=="fail")] | length) as $f
    | ([$s[] | select(.status=="warn")] | length) as $w
    | ($a | length) as $k
    | (if $f > 0 then "fail" elif ($w > 0 or $k > 0) then "warn" else "ok" end) as $cls
    | ((if $f > 0 then "✗ \($f)" elif $w > 0 then "! \($w)" else "✓" end)
       + (if $k > 0 then " · \($k) ask" else "" end)) as $text
    | ([$s[] | select(.status != "ok") | "\(.job): \(.summary)"]
       + [$a[] | "ask \(.job): \(.q)"]) as $tip
    | {text:$text, class:$cls, tooltip:(if ($tip|length)==0 then "dots-ops: all ok" else ($tip|join("\n")) end)}'
}

ops_status_lines() {   # fzf input: job ⟂ status ⟂ summary ⟂ last change, worst first; live asks listed with status "ask"
  local now j q; now=$(ops_now)
  {
    ops_state_entries | jq -r --argjson now "$now" '
      (if .status=="fail" then 0 elif .status=="warn" then 2 else 3 end) as $o
      | (((($now - (.changed // $now)) / 60) | floor)) as $m
      | [$o, .job, .status, (.summary // "" | gsub("[\n\t]";" ")),
         (if $m < 60 then "\($m)m ago" elif $m < 1440 then "\($m / 60 | floor)h ago" else "\($m / 1440 | floor)d ago" end)]
      | @tsv' 2>/dev/null
    ops_live_asks | while IFS=$'\t' read -r j q; do printf '1\t%s\task\t%s\tnow\n' "$j" "$q"; done
  } | sort -s -t$'\t' -k1,1n -k2,2 | awk -F'\t' '{printf "%s ⟂ %s ⟂ %s ⟂ %s\n", $2, $3, $4, $5}'
}

ops_on_ac() {
  local d bat=0
  for d in "$OPS_POWER_DIR"/*; do
    [ -e "$d/type" ] || continue
    grep -q Device "$d/scope" 2>/dev/null && continue   # peripheral batteries (mouse, headset)
    case $(cat "$d/type") in
      Mains) [ "$(cat "$d/online" 2>/dev/null)" = 1 ] && return 0 ;;
      Battery) bat=1 ;;
    esac
  done
  [ "$bat" = 0 ]   # no battery = desktop = AC
}

ops_idle_ok() {
  ops_on_ac || return 1
  [ -e "$OPS_IDLE_FLAG" ] && return 0
  [ "${OPS_FALLBACK:-0}" = 1 ] && pgrep -x hyprlock >/dev/null 2>&1 && return 0
  [ "${OPS_FALLBACK:-0}" = 1 ] && ! loginctl list-sessions --no-legend 2>/dev/null | grep -q . && return 0
  return 1
}

ops_family() {   # prints arch|debian|fedora|nixos|unknown from os-release ID / ID_LIKE (OPS_OS_RELEASE overrides the file for tests)
  local f="${OPS_OS_RELEASE:-/etc/os-release}" id="" like="" k v w
  if [ -r "$f" ]; then
    while IFS='=' read -r k v; do
      v=${v%\"}; v=${v#\"}; v=${v%\'}; v=${v#\'}
      case $k in ID) id=$v ;; ID_LIKE) like=$v ;; esac
    done < "$f"
  fi
  for w in $id $like; do
    case $w in
      nixos) echo nixos; return 0 ;;
      arch) echo arch; return 0 ;;
      debian|ubuntu) echo debian; return 0 ;;
      fedora|rhel|centos) echo fedora; return 0 ;;
    esac
  done
  echo unknown
}
