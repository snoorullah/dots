# containers-prune / volumes (approved root action, sourced by dots-ops-run with lib loaded): also removes unused volumes.
_out=$(ops_run docker system prune --volumes -f 2>&1) && _rc=0 || _rc=$?
printf '%s\n' "$_out"
if [ "$_rc" = 0 ]; then
  _rec=$(grep -i 'reclaimed' <<< "$_out" | tail -n 1)
  ops_state containers-prune ok "${_rec:-volumes pruned}"
else
  ops_state containers-prune warn "docker volume prune failed (rc=$_rc)"
fi
unset _out _rc _rec
