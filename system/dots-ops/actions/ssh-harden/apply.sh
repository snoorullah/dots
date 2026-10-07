# ssh-harden / apply (approved root action, sourced by dots-ops-run with lib loaded, set -euo pipefail):
# re-run every lockout guard (keys may have gone since the ask), install 50-dots.conf, validate with `sshd -t`
# (invalid -> previous drop-in restored or ours removed, fail, exit 1), then reload the sshd/ssh unit if it runs.
# $P is the runner's root-owned prefix (/usr/local/lib/dots-ops, or the Nix store path on NixOS).
OPS_SYS_DIR=${P:?}
if [ "$EUID" = 0 ] && ! ops_file_trusted "$P/jobs" "$P/jobs/ssh-harden.sh" "$P/sshd/50-dots.conf"; then   # R20
  ops_state ssh-harden fail "refused: ssh-harden job or drop-in not root-owned"; exit 1
fi
source "$P/jobs/ssh-harden.sh"
if ! _sh_check; then
  rm -f "$OPS_ROOT_STATE/ask-ssh-harden.json"; ops_state ssh-harden "$_sh_st" "$_sh_msg"; return 0
fi
_sh_src=$OPS_ROOT_STATE/ssh-harden.desired.conf; _sh_dst=$OPS_SSHD_DIR/50-dots.conf; _sh_bak=""
mkdir -p "$OPS_ROOT_STATE"; _sh_desired > "$_sh_src"   # R47: without the KbdInteractiveAuthentication line on OpenSSH < 8.7
if [ -f "$_sh_dst" ]; then _sh_bak=$OPS_ROOT_STATE/ssh-harden.prev.conf; ops_run cp "$_sh_dst" "$_sh_bak"; fi
ops_run install -d -m 755 "$OPS_SSHD_DIR"
ops_run install -m 644 "$_sh_src" "$_sh_dst"
_sh_rc=0; _sh_out=$(ops_run sshd -t 2>&1) || _sh_rc=$?
[ -z "$_sh_out" ] || printf '%s\n' "$_sh_out"
if [ "$_sh_rc" != 0 ]; then   # sshd keeps running on its old config; leave the on-disk config as it was
  if [ -n "$_sh_bak" ]; then ops_run install -m 644 "$_sh_bak" "$_sh_dst"; _sh_undo="previous drop-in restored"
  else ops_run rm -f "$_sh_dst"; _sh_undo="drop-in removed"; fi
  ops_state ssh-harden fail "sshd -t rejected 50-dots.conf (rc=$_sh_rc): $(printf '%s\n' "$_sh_out" | tail -n 1); $_sh_undo; sshd not reloaded"
  exit 1
fi
_sh_unit=""
for _u in sshd.service ssh.service; do systemctl cat "$_u" >/dev/null 2>&1 && { _sh_unit=$_u; break; }; done
_sh_how="sshd not running; applies on its next start"
if [ -n "$_sh_unit" ] && systemctl is-active --quiet "$_sh_unit" 2>/dev/null; then
  if ! ops_run systemctl reload "$_sh_unit"; then
    ops_state ssh-harden warn "50-dots.conf installed and valid, but reloading $_sh_unit failed; it applies on the next restart"; exit 1
  fi
  _sh_how="reloaded $_sh_unit"
fi
if [ "${DOTS_OPS_DRY_RUN:-0}" != 1 ]; then
  rm -f "$OPS_ROOT_STATE/ask-ssh-harden.json" ${_sh_bak:+"$_sh_bak"}
  ops_state ssh-harden ok "hardened ($_sh_how)"
fi
unset _sh_src _sh_dst _sh_bak _sh_rc _sh_out _sh_undo _sh_unit _sh_how _u
