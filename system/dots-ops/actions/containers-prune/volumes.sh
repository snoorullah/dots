# containers-prune / volumes (approved root action, sourced by dots-ops-run with lib loaded): also removes unused volumes.
# R55: reports as containers-prune-volumes — containers-prune is a user job, and the relay never overwrites a user job's state.
_out=$(ops_run docker system prune --volumes -f 2>&1) && _rc=0 || _rc=$?
printf '%s\n' "$_out"
if [ "$_rc" = 0 ]; then
  _rec=$(grep -i 'reclaimed' <<< "$_out" | tail -n 1) || true   # no such line must not abort under set -e/pipefail
  ops_state containers-prune-volumes ok "${_rec:-volumes pruned}"
else
  ops_state containers-prune-volumes warn "docker volume prune failed (rc=$_rc)"
fi
unset _out _rc _rec
