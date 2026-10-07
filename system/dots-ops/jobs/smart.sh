# smart (root): SMART health + error counters per disk, compared with the previous run. No capable disk -> ok n/a.
job_main() {
  local name type dev json passed realloc media prev_r prev_m sf found=0 bad=""
  while read -r name type; do
    [ "$type" = disk ] || continue
    [[ $name =~ ^(sd[a-z]+|nvme[0-9]+n[0-9]+)$ ]] || continue
    dev=/dev/$name
    smartctl -i "$dev" >/dev/null 2>&1 || continue   # no SMART (USB bridge, VM disk)
    json=$(smartctl -H -A -j "$dev" 2>/dev/null) || true   # exit bits flag a failing disk too: read the JSON instead
    jq -e . >/dev/null 2>&1 <<< "$json" || continue
    found=1
    passed=$(jq -r 'if .smart_status.passed == false then false else true end' <<< "$json")
    realloc=$(jq -r '[.ata_smart_attributes.table[]? | select(.name=="Reallocated_Sector_Ct") | .raw.value][0] // 0' <<< "$json")
    media=$(jq -r '.nvme_smart_health_information_log.media_errors // 0' <<< "$json")
    sf=$OPS_ROOT_STATE/smart-$name.json
    prev_r=$(jq -r '.reallocated // empty' "$sf" 2>/dev/null) || true; prev_m=$(jq -r '.media_errors // empty' "$sf" 2>/dev/null) || true
    [ "$passed" = true ] || bad+="${bad:+; }$name health FAILED"
    if [ -n "$prev_r" ] && [ "$realloc" -gt "$prev_r" ]; then bad+="${bad:+; }$name reallocated $prev_r->$realloc"; fi
    if [ -n "$prev_m" ] && [ "$media" -gt "$prev_m" ]; then bad+="${bad:+; }$name media_errors $prev_m->$media"; fi
    mkdir -p "$OPS_ROOT_STATE"
    jq -cn --argjson r "$realloc" --argjson m "$media" '{reallocated:$r,media_errors:$m}' > "$sf.tmp" && mv "$sf.tmp" "$sf"
  done < <(lsblk -dno NAME,TYPE 2>/dev/null)
  if [ "$found" = 0 ]; then ops_state smart ok "n/a: no SMART-capable disks"
  elif [ -n "$bad" ]; then ops_state smart fail "$bad"
  else ops_state smart ok "all disks healthy"; fi
}
