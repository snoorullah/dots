# smart (root): SMART health + error counters per disk, compared with the previous run. No capable disk -> ok n/a.
# Counter files are keyed by serial number (kernel names move between boots). An increase keeps the disk failing for 7 days (R29).
job_main() {
  local name type dev json passed realloc media prev_r prev_m sf key serial found=0 bad="" now fu inc
  now=$(ops_now)
  while read -r name type; do
    [ "$type" = disk ] || continue
    [[ $name =~ ^(sd[a-z]+|nvme[0-9]+n[0-9]+)$ ]] || continue
    dev=/dev/$name
    smartctl -i "$dev" >/dev/null 2>&1 || continue   # no SMART (USB bridge, VM disk)
    json=$(smartctl -H -A -j "$dev" 2>/dev/null) || true   # exit bits flag a failing disk too: read the JSON instead
    jq -e 'type=="object" and has("smart_status")' >/dev/null 2>&1 <<< "$json" || continue   # no verdict = not capable
    found=1
    passed=$(jq -r 'if .smart_status.passed == false then false else true end' <<< "$json")
    realloc=$(jq -r '[.ata_smart_attributes.table[]? | select(.id == 5 or .name == "Reallocated_Sector_Ct") | .raw.value][0] // 0' <<< "$json")
    media=$(jq -r '.nvme_smart_health_information_log.media_errors // 0' <<< "$json")
    serial=$(jq -r '.serial_number // empty' <<< "$json" | tr -c 'A-Za-z0-9_\n-' _)
    key=${serial:-$name}
    sf=$OPS_ROOT_DATA/smart-$key.json
    prev_r=$(jq -r '.reallocated // empty' "$sf" 2>/dev/null) || true
    prev_m=$(jq -r '.media_errors // empty' "$sf" 2>/dev/null) || true
    fu=$(jq -r '.fail_until // 0' "$sf" 2>/dev/null) || true
    [[ $fu =~ ^[0-9]+$ ]] || fu=0
    [ "$passed" = true ] || bad+="${bad:+; }$name health FAILED"
    inc=0
    if [ -n "$prev_r" ] && [ "$realloc" -gt "$prev_r" ]; then inc=1; bad+="${bad:+; }$name reallocated $prev_r->$realloc"; fi
    if [ -n "$prev_m" ] && [ "$media" -gt "$prev_m" ]; then inc=1; bad+="${bad:+; }$name media_errors $prev_m->$media"; fi
    if [ "$inc" = 1 ]; then fu=$((now + 604800))
    elif [ "$fu" -gt "$now" ]; then bad+="${bad:+; }$name error counters rose recently (failing until $(date -d "@$fu" +%F))"; fi
    mkdir -p "$OPS_ROOT_DATA"
    jq -cn --argjson r "$realloc" --argjson m "$media" --argjson f "$fu" '{reallocated:$r,media_errors:$m,fail_until:$f}' > "$sf.tmp" && mv "$sf.tmp" "$sf"
  done < <(lsblk -dno NAME,TYPE 2>/dev/null)
  if [ "$found" = 0 ]; then ops_state smart ok "n/a: no SMART-capable disks"
  elif [ -n "$bad" ]; then ops_state smart fail "$bad"
  else ops_state smart ok "all disks healthy"; fi
}
