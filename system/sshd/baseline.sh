#!/usr/bin/env bash
# sshd baseline (root). Run by the chezmoi root script (00-system) on every non-NixOS machine, org-managed included,
# after openssh-server is installed and BEFORE sshd is enabled:
#   1. sshd_config must Include sshd_config.d/*.conf (Debian/Ubuntu/Fedora ship it; an Arch sshd_config may not):
#      when it is missing, the Include line is added at the top.
#   2. 40-dots-baseline.conf (next to this script) -> $SSHD_DIR/40-dots-baseline.conf: PermitRootLogin no,
#      PasswordAuthentication no, KbdInteractiveAuthentication no (ChallengeResponseAuthentication on OpenSSH < 8.7,
#      the same version check as system/dots-ops/jobs/ssh-harden.sh). Same values as ssh-harden's 50-dots.conf.
#   3. `sshd -t` validates (missing host keys are generated first with ssh-keygen -A). Rejected -> the previous
#      drop-in is restored (or ours removed), an Include we added is taken out again, sshd is not enabled; exit 1.
#   4. Lockout guard: sshd is enabled and started only when $AUTH_KEYS holds a key. Without one it stays installed
#      but disabled (Debian's postinst starts it; it is stopped again) — unless sshd was already on before this
#      run (SSHD_WAS_ON=1): then it is left running and not reloaded, with a warning.
# Idempotent: re-running rewrites the same drop-in and never adds a second Include.
# Env (tests override them): SSHD_CONFIG, SSHD_DIR, AUTH_KEYS (required), SSHD_WAS_ON (0/1).
set -uo pipefail
: "${SSHD_CONFIG:=/etc/ssh/sshd_config}"
: "${SSHD_DIR:=/etc/ssh/sshd_config.d}"
: "${AUTH_KEYS:?set AUTH_KEYS to the authorized_keys file of the owner}"
: "${SSHD_WAS_ON:=0}"
src="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/40-dots-baseline.conf"
dst="$SSHD_DIR/40-dots-baseline.conf"
log() { printf 'sshd: %s\n' "$*" >&2; }

SSHD=$(command -v sshd 2>/dev/null) || SSHD=""
if [ -z "$SSHD" ]; then for c in /usr/sbin/sshd /usr/bin/sshd; do [ -x "$c" ] && { SSHD=$c; break; }; done; fi
[ -n "$SSHD" ] || { log "sshd not installed; baseline skipped"; exit 0; }
[ -f "$src" ] || { log "missing $src"; exit 1; }
[ -f "$SSHD_CONFIG" ] || { log "$SSHD_CONFIG missing; baseline skipped, sshd not enabled"; exit 1; }

kbd_known() {   # 0 = this sshd knows KbdInteractiveAuthentication (OpenSSH >= 8.7, or version unknown)
  local v
  v=$("$SSHD" -V 2>&1 | grep -o 'OpenSSH_[0-9]*\.[0-9]*' | head -n 1) || v=""
  [ -n "$v" ] || { v=$(ssh -V 2>&1 | grep -o 'OpenSSH_[0-9]*\.[0-9]*' | head -n 1) || v=""; }
  [[ $v =~ OpenSSH_([0-9]+)\.([0-9]+) ]] || return 0
  [ "${BASH_REMATCH[1]}" -gt 8 ] || { [ "${BASH_REMATCH[1]}" = 8 ] && [ "${BASH_REMATCH[2]}" -ge 7 ]; }
}
desired() {
  if kbd_known; then cat "$src"
  else sed 's/^\([[:space:]]*\)KbdInteractiveAuthentication\b/\1ChallengeResponseAuthentication/' "$src"; fi
}
unit=""; for u in ssh.service sshd.service; do systemctl cat "$u" >/dev/null 2>&1 && { unit=$u; break; }; done
stop_sshd() {   # socket units too: Ubuntu >= 22.10 socket-activates sshd
  local u
  for u in ssh.socket sshd.socket ssh.service sshd.service; do
    systemctl cat "$u" >/dev/null 2>&1 && systemctl disable --now "$u" >/dev/null 2>&1
  done
  return 0
}
has_key() { [ -f "$AUTH_KEYS" ] && grep -Eq '^[[:space:]]*[^#[:space:]]' "$AUTH_KEYS" 2>/dev/null; }

# 1. Include of the drop-in dir (first match wins: it goes at the top)
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
cfg_bak=""
inc_re='^[[:space:]]*Include([[:space:]]+[^[:space:]]+)*[[:space:]]+(/etc/ssh/)?sshd_config\.d/\*\.conf([[:space:]]|$)'
if ! grep -Eiq "$inc_re" "$SSHD_CONFIG" && ! grep -qxF "Include $SSHD_DIR/*.conf" "$SSHD_CONFIG"; then
  cfg_bak=$work/sshd_config.prev; cp -p "$SSHD_CONFIG" "$cfg_bak"
  { printf 'Include %s/*.conf\n' "$SSHD_DIR"; cat "$cfg_bak"; } > "$SSHD_CONFIG"   # > keeps owner and mode
  log "added 'Include $SSHD_DIR/*.conf' at the top of $SSHD_CONFIG"
fi

# 2. the drop-in
prev=""
install -d -m 755 "$SSHD_DIR"
if [ -f "$dst" ]; then prev=$work/baseline.prev; cp -p "$dst" "$prev"; fi
desired > "$work/baseline.new" && install -m 644 "$work/baseline.new" "$dst"

# 3. validate
command -v ssh-keygen >/dev/null 2>&1 && ssh-keygen -A >/dev/null 2>&1   # Arch: host keys appear on first start only
rc=0; out=$("$SSHD" -t -f "$SSHD_CONFIG" 2>&1) || rc=$?
if [ "$rc" != 0 ]; then
  [ -z "$out" ] || printf '%s\n' "$out" >&2
  if [ -n "$prev" ]; then install -m 644 "$prev" "$dst"; else rm -f "$dst"; fi
  [ -z "$cfg_bak" ] || cat "$cfg_bak" > "$SSHD_CONFIG"
  log "sshd -t rejected the baseline (rc=$rc); rolled back, sshd NOT enabled"
  [ "$SSHD_WAS_ON" = 1 ] || stop_sshd
  exit 1
fi
log "baseline in place: $dst (key-only, no root login)"

# 4. enable only with a key (lockout guard)
if has_key; then
  [ -n "$unit" ] || { log "no ssh/sshd unit found; not enabled"; exit 0; }
  if systemctl is-active --quiet "$unit" 2>/dev/null; then systemctl reload "$unit" || systemctl restart "$unit"
  else systemctl enable --now "$unit" || { log "enabling $unit failed"; exit 1; }; fi
  log "$unit enabled (key login for $AUTH_KEYS)"
elif [ "$SSHD_WAS_ON" = 1 ]; then
  log "WARNING: sshd was already on before this run and $AUTH_KEYS has no key; left running and NOT reloaded."
  log "         Add a key before sshd restarts: the baseline turns password login off."
else
  stop_sshd
  log "installed but left DISABLED: $AUTH_KEYS has no key (key-only sshd would lock you out)."
  log "         Add your public key there, then: sudo systemctl enable --now ${unit:-sshd.service}"
fi
exit 0
