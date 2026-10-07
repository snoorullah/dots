#!/usr/bin/env bash
# dots-ops shared library — source it, never execute. Root and user both use this file.
: "${OPS_IS_ROOT:=$([ "$EUID" = 0 ] && echo 1 || echo 0)}"
: "${OPS_ROOT_STATE:=/var/lib/dots-ops}"   # root job statuses + ask files (0755/0644, read by the user relay)
if [ "$OPS_IS_ROOT" = 1 ]; then   # root has no usable HOME under systemd/sudo; its own log/locks live here
  : "${OPS_STATE:=$OPS_ROOT_STATE/root}"
else
  : "${OPS_STATE:=${XDG_STATE_HOME:-$HOME/.local/state}/dots-ops}"
fi
# R61: root bookkeeping that is not a status/ask file (lynis report, audit baseline, SMART counters, firewall hashes,
# ssh-harden copies, the pkg lock) lives one level down: the user's relay path unit watches only the top level, and
# every write there costs a relay run (PathChanged trigger limit).
: "${OPS_ROOT_DATA:=$OPS_ROOT_STATE/root}"
: "${OPS_NOTIFY:=notify-send}"
: "${OPS_REMIND_SECS:=86400}"
mkdir -p "$OPS_STATE/state" "$OPS_STATE/pending" "$OPS_STATE/queue" "$OPS_STATE/locks" 2>/dev/null || true
if [ "$OPS_IS_ROOT" = 1 ]; then chmod 700 "$OPS_STATE/locks" 2>/dev/null || true; fi   # nobody else may hold root's locks
if [ "$OPS_IS_ROOT" = 1 ]; then   # R61 upgrade path: move bookkeeping an older version left at the watched top level
  for _f in "$OPS_ROOT_STATE"/firewall.applied "$OPS_ROOT_STATE"/firewall.pending-hash "$OPS_ROOT_STATE"/audit-last.json \
            "$OPS_ROOT_STATE"/lynis-report.dat "$OPS_ROOT_STATE"/ssh-harden.*.conf "$OPS_ROOT_STATE"/smart-*.json; do
    [ -f "$_f" ] || continue
    mkdir -p "$OPS_ROOT_DATA" 2>/dev/null || break
    if [ -e "$OPS_ROOT_DATA/${_f##*/}" ]; then rm -f "$_f"; else mv "$_f" "$OPS_ROOT_DATA/" 2>/dev/null || true; fi
  done
  unset _f
fi

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
    # R62: a change notifies once; only a lasting fail reminds (every OPS_REMIND_SECS) — a permanent warn must not nag daily
    if [ "$st" != ok ] && { [ "$prev" != "$st" ] || { [ "$st" = fail ] && [ $((now - notified)) -ge "$OPS_REMIND_SECS" ]; }; }; then send=$st
    elif [ "$st" = ok ] && [ "$prev" != ok ] && [ "$prev" != none ]; then send=recovered; fi
  fi
  case $send in
    fail)      ops_notify critical "dots-ops: $job failed" "$sum"; notified=$now ;;
    warn)      ops_notify normal   "dots-ops: $job" "$sum"; notified=$now ;;
    recovered) ops_notify low      "dots-ops: $job recovered" "$sum"; notified=0 ;;
  esac
  # inv = the systemd invocation that wrote it: the ExecStopPost reporter (R57) sees the job already reported its failure
  jq -cn --arg j "$job" --arg s "$st" --arg m "$sum" --argjson t "$now" --argjson n "$notified" --arg i "${INVOCATION_ID:-}" \
    '{job:$j,status:$s,summary:$m,changed:$t,notified:$n} + (if $i == "" then {} else {inv:$i} end)' \
    > "$dir/$job.json.tmp" && mv "$dir/$job.json.tmp" "$dir/$job.json"
  ops_log "$job" "$st" "$sum"
  ops_signal
}

ops_report_unit() {   # name [act] — ExecStopPost of every dots-ops unit (R57), via `dots-ops-job --report-failure`
  # A unit that crashed, was killed or hit its timeout never reached its own ops_state: report it as fail
  # "unit <SERVICE_RESULT>/<EXIT_CODE>/<EXIT_STATUS>" under <name> (job units: the job; action units: <job>-<action>, R55).
  # Skipped when a state written by this same invocation is already warn/fail (the job/action said why itself).
  # act: on success, a fail this reporter wrote earlier for the action is cleared (nothing else would ever clear it).
  local name=$1 mode=${2:-} res=${SERVICE_RESULT:-} dir f cur
  if [ "$OPS_IS_ROOT" = 1 ]; then dir=$OPS_ROOT_STATE; else dir=$OPS_STATE/state; fi
  if [ -z "$res" ] || [ "$res" = success ]; then
    if [ "$mode" = act ] && [ -f "$dir/$name.json" ] \
       && [ "$(jq -r 'select(.status == "fail") | .summary' "$dir/$name.json" 2>/dev/null | cut -c1-5)" = "unit " ]; then
      ops_state "$name" ok "last run finished normally"
    fi
    return 0
  fi
  if [ -n "${INVOCATION_ID:-}" ]; then
    for f in "$dir"/*.json; do
      [ -f "$f" ] || continue
      cur=$(jq -r --arg i "$INVOCATION_ID" 'select(.inv == $i and (.status == "warn" or .status == "fail")) | .status' "$f" 2>/dev/null) || cur=""
      [ -z "$cur" ] || { ops_log "$name" info "unit $res; already reported by the job ($(basename "$f" .json) $cur)"; return 0; }
    done
  fi
  ops_state "$name" fail "unit $res/${EXIT_CODE:-?}/${EXIT_STATUS:-?}"
}

ops_ran_within() {   # name secs — 0 = skip: <name> last ran less than secs ago ($OPS_STATE/<name>.last) and the run is not forced
  local t now; [ "${OPS_FORCE:-0}" = 1 ] && return 1
  t=$(head -n 1 "$OPS_STATE/$1.last" 2>/dev/null) || return 1
  [[ $t =~ ^[0-9]+$ ]] || return 1
  now=$(ops_now); [ $((now - t)) -lt "$2" ] || return 1
  ops_log "$1" info "skipped: last run $(( (now - t) / 3600 ))h ago"
}
ops_ran_mark() { [ "${DOTS_OPS_DRY_RUN:-0}" = 1 ] || ops_now > "$OPS_STATE/$1.last"; }   # name — record a real run

# R56: one shared root package lock. updates-full apply and updates-security hold it for the package transaction;
# reboot now/tonight refuse (or retry) while it is held, so no reboot lands in the middle of dpkg/pacman/dnf.
ops_pkg_lock() {   # [wait-secs] — take it on fd OPS_PKG_FD, waiting up to OPS_PKG_LOCK_WAIT (30 min); 1 = still busy
  mkdir -p "$OPS_ROOT_DATA/locks" && exec {OPS_PKG_FD}>>"$OPS_ROOT_DATA/locks/pkg.lock" || return 1
  flock -w "${1:-${OPS_PKG_LOCK_WAIT:-1800}}" "$OPS_PKG_FD"
}
ops_pkg_unlock() { if [ -n "${OPS_PKG_FD:-}" ]; then exec {OPS_PKG_FD}>&-; OPS_PKG_FD=""; fi; }
ops_pkg_busy() {   # 0 = a package transaction holds the lock right now (never waits)
  local fd
  [ -e "$OPS_ROOT_DATA/locks/pkg.lock" ] || return 1
  exec {fd}>>"$OPS_ROOT_DATA/locks/pkg.lock" || return 1
  if flock -n "$fd"; then exec {fd}>&-; return 1; fi
  exec {fd}>&-
}

ops_logind_idle() {   # 0 = logind says this user has been idle >= OPS_FALLBACK_IDLE_SECS (900 s): IdleHint=yes, IdleSinceHint old (R58)
  local out hint since
  out=$(loginctl show-user "$EUID" -p IdleHint -p IdleSinceHint 2>/dev/null) || return 1
  hint=$(sed -n 's/^IdleHint=//p' <<< "$out"); since=$(sed -n 's/^IdleSinceHint=//p' <<< "$out")
  [ "$hint" = yes ] && [[ $since =~ ^[0-9]+$ ]] || return 1
  [ $(( $(ops_now) - since / 1000000 )) -ge "${OPS_FALLBACK_IDLE_SECS:-900}" ]   # 0 = idle since before boot: long enough
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

ops_ask() {   # job question action [alt_action [alt_label]] — one live pending per job; alt = optional second button (R5)
  local job=$1 q=$2 act=$3 alt=${4:-} altl=${5:-} now; now=$(ops_now)
  if [ "$OPS_IS_ROOT" = 1 ]; then   # root cannot reach the desktop: leave an ask file for `dots-ops relay`
    mkdir -p "$OPS_ROOT_STATE"
    jq -cn --arg q "$q" --arg a "$act" --arg alt "$alt" --arg al "$altl" --argjson t "$now" \
      '{question:$q,action:$a,asked:$t} + (if $alt == "" then {} else {alt_action:$alt} + (if $al == "" then {} else {alt_label:$al} end) end)' \
      > "$OPS_ROOT_STATE/ask-$job.json.tmp" && mv "$OPS_ROOT_STATE/ask-$job.json.tmp" "$OPS_ROOT_STATE/ask-$job.json"
    ops_log "$job" ask "$q"
    return 0
  fi
  ops_ask_pending "$job" && return 0
  jq -cn --arg q "$q" --arg a "$act" --arg alt "$alt" --arg al "$altl" --argjson t "$now" --argjson e $((now + 86400)) \
    '{question:$q,action:$a,asked:$t,expires:$e,snooze_until:0}
     + (if $alt == "" then {} else {alt_action:$alt} + (if $al == "" then {} else {alt_label:$al} end) end)' > "$OPS_STATE/pending/$job.json"
  ops_log "$job" ask "$q"
  ops_ask_ui "$job"
  return 0
}

ops_ask_ui() {   # job — show the approval toast for the job's pending
  # R36: a transient user unit, not a detached child (that stays in the calling unit's cgroup and dies with a oneshot relay)
  if [ "$OPS_ASK_UI" = 1 ]; then systemd-run --user --no-block --collect "$HOME/.local/bin/dots-ops-ask" "$1" >/dev/null 2>&1 || true; fi
  return 0
}

ops_pending_token() {   # job — sha256 of the pending's question+action+alt_action+asked (R54); 1 = no readable pending
  local s
  s=$(jq -ce '[.question, .action, (.alt_action // ""), .asked]' "$OPS_STATE/pending/$1.json" 2>/dev/null) || return 1
  printf '%s' "$s" | sha256sum | cut -d' ' -f1
}

ops_toast_close() {   # job — close the approval toast still on screen for this job (dots-ops-ask keeps its id in <job>.nid)
  local n="$OPS_STATE/pending/$1.nid" id
  id=$(head -n 1 "$n" 2>/dev/null) || return 0
  rm -f "$n"
  [[ $id =~ ^[0-9]+$ ]] && command -v gdbus >/dev/null 2>&1 || return 0
  gdbus call --session --dest org.freedesktop.Notifications --object-path /org/freedesktop/Notifications \
    --method org.freedesktop.Notifications.CloseNotification "$id" >/dev/null 2>&1 || true
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

ops_dispatch() {   # job action-string: run a user:/root: action; returns its rc
  local act=$1 rc=0
  case $act in
    user:*) bash -c "${act#user:}" || rc=$? ;;
    root:*)
      local ra sudo_cmd
      read -ra ra <<< "${act#root:}"
      read -ra sudo_cmd <<< "$OPS_SUDO"
      "${sudo_cmd[@]}" "$OPS_RUNNER" "${ra[0]}" "${ra[1]}" || rc=$? ;;
  esac
  return "$rc"
}

ops_answer() {   # job approve|alt|skip|snooze [token]
  # R54: a token (from the toast or the status TUI) must match the pending as it is NOW; the relay may have replaced it
  # with another question since the toast was shown. A stale answer does nothing; the newer ask is shown again.
  local job=$1 ans=$2 tok=${3:-} f="$OPS_STATE/pending/$1.json" act altact rc=0 saved
  [ -f "$f" ] || return 0
  if [ -n "$tok" ] && [ "$tok" != "$(ops_pending_token "$job")" ]; then
    ops_log "$job" warn "stale approval ignored ($ans was for content that is no longer pending)"
    if ops_ask_pending "$job"; then ops_ask_ui "$job"; fi
    ops_signal; return 0
  fi
  act=$(jq -r .action "$f" 2>/dev/null)
  case $ans in
    approve|alt)
      if [ "$ans" = alt ]; then
        altact=$(jq -r '.alt_action // empty' "$f" 2>/dev/null)
        [ -n "$altact" ] || { ops_log "$job" warn "alt answered but the pending has no alt_action"; return 0; }
        act=$altact
      fi
      if ! ops_ask_pending "$job"; then ops_log "$job" info "approval expired; not run"; ops_signal; return 0; fi
      saved=$(cat "$f"); rm -f "$f"; ops_log "$job" "$ans" "$act"
      ops_dispatch "$act" || rc=$?
      if [ "$rc" -ne 0 ]; then
        # R60: sudo refused / runner broken: the root action never started, so keep the ask (same content, same token)
        if [[ $act == root:* ]] && [ ! -e "$f" ]; then
          printf '%s\n' "$saved" > "$f"; ops_log "$job" info "pending restored after the failed root dispatch"
        fi
        ops_state "$job" warn "approved action failed (rc=$rc): $act"
      fi ;;
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
  # plus a 5th field, the ask's token (R54), which `dots-ops status` hides (--with-nth) and passes to `answer`
  local now j q; now=$(ops_now)
  {
    ops_state_entries | jq -r --argjson now "$now" '
      (if .status=="fail" then 0 elif .status=="warn" then 2 else 3 end) as $o
      | (((($now - (.changed // $now)) / 60) | floor)) as $m
      | [$o, .job, .status, (.summary // "" | gsub("[\n\t]";" ")),
         (if $m < 60 then "\($m)m ago" elif $m < 1440 then "\($m / 60 | floor)h ago" else "\($m / 1440 | floor)d ago" end)]
      | @tsv' 2>/dev/null
    ops_live_asks | while IFS=$'\t' read -r j q; do printf '1\t%s\task\t%s\tnow\t%s\n' "$j" "$q" "$(ops_pending_token "$j")"; done
  } | sort -s -t$'\t' -k1,1n -k2,2 \
    | awk -F'\t' '{printf "%s ⟂ %s ⟂ %s ⟂ %s", $2, $3, $4, $5; if ($6 != "") printf " ⟂ %s", $6; printf "\n"}'
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

ops_restic_env() {   # 0 if restic credentials are available; sources ~/.secrets only when it is ours and not group/other-writable
  local s="$HOME/.secrets"
  if [ -f "$s" ] && [ "$(stat -Lc %u "$s")" = "$EUID" ] && [ $(( 0$(stat -Lc %a "$s") & 022 )) = 0 ]; then
    set -a; . "$s" 2>/dev/null; set +a
  fi
  [ -n "${RESTIC_REPOSITORY:-}" ] && { [ -n "${RESTIC_PASSWORD:-}" ] || [ -n "${RESTIC_PASSWORD_FILE:-}" ]; }
}
