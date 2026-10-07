# updates-full / apply (approved root action, sourced by dots-ops-run with lib loaded, set -euo pipefail):
# full native upgrade per family. No auto-retry: a failure stays red until the next updates-check re-asks.
_uf_fam=$(ops_family)
_uf_hint=none
if command -v snapper >/dev/null; then _uf_hint=snapper   # snapshots are the rollback path
elif command -v timeshift >/dev/null; then _uf_hint=timeshift; fi
# one step: run via ops_run, show its output, on failure record "<step>: <last 3 lines>" + the rollback hint and stop
_uf_step() {
  local step=$1 out rc=0; shift
  out=$(ops_run "$@" 2>&1) || rc=$?
  [ -z "$out" ] || printf '%s\n' "$out"
  if [ "$rc" -ne 0 ]; then
    ops_state updates-full fail "$step: $(printf '%s\n' "$out" | tail -n 3 | tr '\n' ' ')[rollback: $_uf_hint]"
    exit 1
  fi
}
case $_uf_fam in
  debian)
    _uf_step "apt-get update" apt-get update -qq
    _uf_step "apt-get dist-upgrade" env DEBIAN_FRONTEND=noninteractive apt-get -y -o Dpkg::Options::=--force-confold dist-upgrade ;;
  fedora) _uf_step "dnf upgrade" dnf upgrade -y ;;
  arch)   _uf_step "pacman -Syu" pacman -Syu --noconfirm ;;
  *)      ops_state updates-full ok "n/a: $_uf_fam has no full-update path here"; unset _uf_fam _uf_hint; return 0 ;;
esac
rm -f "$OPS_ROOT_STATE/ask-updates-full.json"
ops_state updates-full ok "updated ($_uf_fam) [rollback: $_uf_hint]"
ops_state updates-check ok "up to date (just applied)"
ops_run systemctl start --no-block dots-ops@reboot-needed.service || true   # kernel/libc may now need a reboot
unset _uf_fam _uf_hint
