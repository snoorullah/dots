# ssh-harden (root): keep /etc/ssh/sshd_config.d/50-dots.conf (no root login, keys only) in place — asked, never automatic.
# Lockout guards (Review Focus 5), checked here AND again by the apply action right before it touches sshd:
#   sshd enabled/active and the owner's ~/.ssh/authorized_keys missing/empty -> warn "skipped: ... would lock you out"
#   AuthenticationMethods needs password/keyboard-interactive (2FA)            -> warn, skipped
#   sshd_config has no Include of sshd_config.d/*.conf                         -> warn (the drop-in would be ignored)
#   sshd not installed / NixOS (services.openssh.settings)                     -> ok n/a
# The owner is /etc/dots-ops/owner (written by the installer, R40); their home comes from getent passwd, never from env.
# The apply action (actions/ssh-harden/apply.sh) sources this file.
: "${OPS_SYS_DIR:=/usr/local/lib/dots-ops}"
: "${OPS_SSHD_CONFIG:=/etc/ssh/sshd_config}"
: "${OPS_SSHD_DIR:=/etc/ssh/sshd_config.d}"
: "${OPS_OWNER_FILE:=/etc/dots-ops/owner}"
_SH_LOCKOUT="skipped: no authorized_keys — would lock you out"

_sh_sshd_on() {   # 0 = some sshd unit is enabled or running (socket activation included)
  local u
  for u in sshd.service ssh.service sshd.socket ssh.socket; do
    systemctl is-enabled --quiet "$u" 2>/dev/null && return 0
    systemctl is-active --quiet "$u" 2>/dev/null && return 0
  done
  return 1
}

_sh_keys_ok() {   # 0 = the owner has at least one non-comment line in ~/.ssh/authorized_keys
  local owner home ak
  owner=$(head -n 1 "$OPS_OWNER_FILE" 2>/dev/null) || return 1
  [[ $owner =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]*$ ]] || return 1
  home=$(getent passwd "$owner" | cut -d: -f6) || return 1
  [ -n "$home" ] || return 1
  ak=$home/.ssh/authorized_keys
  [ -f "$ak" ] || return 1   # -f: a FIFO/device planted there can't hang or feed the check
  grep -Eq '^[[:space:]]*[^#[:space:]]' "$ak" 2>/dev/null
}

# _sh_check: every guard. 1 = do not ask/apply, with _sh_st (ok|warn) and _sh_msg set.
_sh_check() {
  local conf
  _sh_st=ok; _sh_msg=""
  [ "$(ops_family)" != nixos ] || { _sh_msg="n/a: managed by services.openssh.settings (dots-ops.nix)"; return 1; }
  command -v sshd >/dev/null 2>&1 || { _sh_msg="n/a: sshd not installed"; return 1; }
  [ -f "$OPS_SYS_DIR/sshd/50-dots.conf" ] || { _sh_st=warn; _sh_msg="missing $OPS_SYS_DIR/sshd/50-dots.conf"; return 1; }
  if ! grep -Eiq '^[[:space:]]*Include([[:space:]]+[^[:space:]]+)*[[:space:]]+(/etc/ssh/)?sshd_config\.d/\*\.conf([[:space:]]|$)' "$OPS_SSHD_CONFIG" 2>/dev/null; then
    _sh_st=warn
    _sh_msg="skipped: $OPS_SSHD_CONFIG has no 'Include /etc/ssh/sshd_config.d/*.conf', so a drop-in would be ignored; add that line at the top to enable hardening"
    return 1
  fi
  for conf in "$OPS_SSHD_CONFIG" "$OPS_SSHD_DIR"/*.conf; do
    [ -f "$conf" ] || continue
    if grep -Eiq '^[[:space:]]*AuthenticationMethods[[:space:]].*(password|keyboard-interactive)' "$conf" 2>/dev/null; then
      _sh_st=warn; _sh_msg="skipped: AuthenticationMethods in $conf needs password/keyboard-interactive — hardening would lock you out"; return 1
    fi
  done
  if _sh_sshd_on && ! _sh_keys_ok; then _sh_st=warn; _sh_msg=$_SH_LOCKOUT; return 1; fi
  return 0
}

_sh_same() { [ -f "$2" ] && [ "$(sha256sum < "$1")" = "$(sha256sum < "$2")" ]; }

job_main() {
  local src="$OPS_SYS_DIR/sshd/50-dots.conf" dst="$OPS_SSHD_DIR/50-dots.conf" ask="$OPS_ROOT_STATE/ask-ssh-harden.json" eff bad="" k why
  if ! _sh_check; then rm -f "$ask"; ops_state ssh-harden "$_sh_st" "$_sh_msg"; return 0; fi
  if _sh_same "$src" "$dst"; then
    rm -f "$ask"
    # the first value sshd reads wins: an earlier drop-in (e.g. 50-cloud-init.conf) can still override ours
    eff=$(sshd -T 2>/dev/null) || eff=""
    if [ -n "$eff" ]; then
      for k in permitrootlogin passwordauthentication kbdinteractiveauthentication; do
        grep -qx "$k no" <<< "$eff" || bad+="${bad:+, }$(grep -m1 "^$k " <<< "$eff" || echo "$k ?")"
      done
    fi
    if [ -n "$bad" ]; then ops_state ssh-harden warn "50-dots.conf in place but overridden by an earlier file: $bad"
    else ops_state ssh-harden ok "hardened (50-dots.conf in place)"; fi
    return 0
  fi
  if _sh_sshd_on; then why="sshd is on and $(head -n 1 "$OPS_OWNER_FILE") has authorized_keys"; else why="sshd is not enabled"; fi
  ops_ask ssh-harden "Harden sshd? Installs $dst (PermitRootLogin no, PasswordAuthentication no, KbdInteractiveAuthentication no: key-only login). Checked: $why. Validated with sshd -t before reload; removed again if invalid." "root:ssh-harden apply"
  ops_state ssh-harden warn "hardening awaits approval"
}
