# ssh-harden (root): keep /etc/ssh/sshd_config.d/50-dots.conf (no root login, keys only) in place — asked, never automatic.
# Lockout guards (Review Focus 5), checked here AND again by the apply action right before it touches sshd:
#   sshd enabled/active and the owner has no usable authorized key             -> warn "skipped: ... would lock you out"
#     (R47: the files sshd really reads — `sshd -T -C user=<owner>,...` authorizedkeysfile, %h/%u/%U/%% expanded,
#      relative to home; with StrictModes yes the file, its dirs up to home and home itself must be owned by the owner
#      or root and not group/other-writable; sshd -T failing -> ~/.ssh/authorized_keys)
#   ... and hardening is already installed                                     -> warn "hardening active, no authorized_keys:
#                                                                                  remote login impossible"
#   AuthenticationMethods needs password/keyboard-interactive (2FA)            -> warn, skipped
#   sshd_config has no Include of sshd_config.d/*.conf                         -> warn (the drop-in would be ignored)
#   sshd not installed / NixOS (services.openssh.settings)                     -> ok n/a
# OpenSSH < 8.7 does not know KbdInteractiveAuthentication (sshd -t would reject it): it gets ChallengeResponseAuthentication no (R49).
# The owner is /etc/dots-ops/owner (written by the installer, R40); their home comes from getent passwd, never from env.
# The apply action (actions/ssh-harden/apply.sh) sources this file.
: "${OPS_SYS_DIR:=/usr/local/lib/dots-ops}"
: "${OPS_SSHD_CONFIG:=/etc/ssh/sshd_config}"
: "${OPS_SSHD_DIR:=/etc/ssh/sshd_config.d}"
: "${OPS_OWNER_FILE:=/etc/dots-ops/owner}"
_SH_LOCKOUT="skipped: no authorized_keys — would lock you out"
_SH_ACTIVE_NOKEYS="hardening active, no authorized_keys: remote login impossible"

_sh_sshd_on() {   # 0 = some sshd unit is enabled or running (socket activation included)
  local u
  for u in sshd.service ssh.service sshd.socket ssh.socket; do
    systemctl is-enabled --quiet "$u" 2>/dev/null && return 0
    systemctl is-active --quiet "$u" 2>/dev/null && return 0
  done
  return 1
}

_sh_safe_path() {   # path uid: owned by uid or root, not group/other-writable (sshd StrictModes)
  local o m
  o=$(stat -Lc %u "$1" 2>/dev/null) || return 1
  m=$(stat -Lc %a "$1" 2>/dev/null) || return 1
  { [ "$o" = "$2" ] || [ "$o" = 0 ]; } && [ $(( 0$m & 022 )) = 0 ]
}

_sh_strict_ok() {   # file home uid: the file, every dir between it and home, and home itself
  local d
  _sh_safe_path "$1" "$3" || { _sh_keys_why="StrictModes rejects $1"; return 1; }
  d=${1%/*}
  while [ -n "$d" ] && [ "$d" != "$2" ] && [[ $d == "$2"/* ]]; do
    _sh_safe_path "$d" "$3" || { _sh_keys_why="StrictModes rejects $d"; return 1; }
    d=${d%/*}
  done
  _sh_safe_path "$2" "$3" || { _sh_keys_why="StrictModes rejects $2"; return 1; }
}

_sh_keys_ok() {   # 0 = the owner has a usable non-comment key line in a file sshd actually reads for them
  local owner pw home uid eff akf strict=yes tok f
  local -a toks
  _sh_keys_why=""
  owner=$(head -n 1 "$OPS_OWNER_FILE" 2>/dev/null) || return 1
  [[ $owner =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]*$ ]] || return 1
  pw=$(getent passwd "$owner") || return 1
  home=$(cut -d: -f6 <<< "$pw"); uid=$(cut -d: -f3 <<< "$pw")
  home=${home%/}
  [ -n "$home" ] && [[ $uid =~ ^[0-9]+$ ]] || return 1
  akf=.ssh/authorized_keys   # fallback when sshd -T cannot answer
  if eff=$(sshd -T -C "user=$owner,host=localhost,addr=127.0.0.1" 2>/dev/null) && [ -n "$eff" ]; then
    f=$(sed -n 's/^authorizedkeysfile[[:space:]]\{1,\}//p' <<< "$eff" | head -n 1)
    [ -z "$f" ] || akf=$f
    grep -qx 'strictmodes no' <<< "$eff" && strict=no
  fi
  read -ra toks <<< "$akf"
  for tok in "${toks[@]}"; do
    [ "$tok" != none ] || continue
    f=${tok//%%/$'\001'}; f=${f//%h/$home}; f=${f//%u/$owner}; f=${f//%U/$uid}; f=${f//$'\001'/%}
    [[ $f == /* ]] || f=$home/$f
    [ -f "$f" ] || continue   # -f: a FIFO/device planted there can't hang or feed the check
    grep -Eq '^[[:space:]]*[^#[:space:]]' "$f" 2>/dev/null || continue
    if [ "$strict" = yes ] && ! _sh_strict_ok "$f" "$home" "$uid"; then continue; fi
    return 0
  done
  return 1
}

_sh_kbd_known() {   # 0 = this sshd knows KbdInteractiveAuthentication (OpenSSH >= 8.7, or version unknown)
  local v
  v=$(sshd -V 2>&1 | grep -o 'OpenSSH_[0-9]*\.[0-9]*' | head -n 1) || v=""
  [ -n "$v" ] || { v=$(ssh -V 2>&1 | grep -o 'OpenSSH_[0-9]*\.[0-9]*' | head -n 1) || v=""; }
  [[ $v =~ OpenSSH_([0-9]+)\.([0-9]+) ]] || return 0
  [ "${BASH_REMATCH[1]}" -gt 8 ] || { [ "${BASH_REMATCH[1]}" = 8 ] && [ "${BASH_REMATCH[2]}" -ge 7 ]; }
}

_sh_desired() {   # the drop-in content for this sshd (R49: < 8.7 spells it ChallengeResponseAuthentication)
  if _sh_kbd_known; then cat "$OPS_SYS_DIR/sshd/50-dots.conf"
  else sed 's/^\([[:space:]]*\)KbdInteractiveAuthentication\b/\1ChallengeResponseAuthentication/' "$OPS_SYS_DIR/sshd/50-dots.conf"; fi
}

# _sh_check: every guard. 1 = do not ask/apply, with _sh_st (ok|warn) and _sh_msg set.
_sh_check() {
  local conf
  _sh_st=ok; _sh_msg=""; _sh_keys_why=""
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
  if _sh_sshd_on && ! _sh_keys_ok; then
    _sh_st=warn
    if [ -f "$OPS_SSHD_DIR/50-dots.conf" ]; then _sh_msg=$_SH_ACTIVE_NOKEYS; else _sh_msg=$_SH_LOCKOUT; fi
    [ -z "$_sh_keys_why" ] || _sh_msg+=" ($_sh_keys_why)"
    return 1
  fi
  return 0
}

_sh_same() {   # 0 = the installed drop-in equals the desired content
  [ -f "$1" ] && [ "$(_sh_desired | sha256sum)" = "$(sha256sum < "$1")" ]
}

job_main() {
  local dst="$OPS_SSHD_DIR/50-dots.conf" ask="$OPS_ROOT_STATE/ask-ssh-harden.json" eff bad="" k keys why
  if ! _sh_check; then rm -f "$ask"; ops_state ssh-harden "$_sh_st" "$_sh_msg"; return 0; fi
  if _sh_same "$dst"; then
    rm -f "$ask"
    # the first value sshd reads wins: an earlier drop-in (e.g. 50-cloud-init.conf) can still override ours
    keys="permitrootlogin passwordauthentication"
    if _sh_kbd_known; then keys+=" kbdinteractiveauthentication"; else keys+=" challengeresponseauthentication"; fi
    eff=$(sshd -T 2>/dev/null) || eff=""
    if [ -n "$eff" ]; then
      for k in $keys; do
        grep -qx "$k no" <<< "$eff" || bad+="${bad:+, }$(grep -m1 "^$k " <<< "$eff" || echo "$k ?")"
      done
    fi
    if [ -n "$bad" ]; then ops_state ssh-harden warn "50-dots.conf in place but overridden by an earlier file: $bad"
    else ops_state ssh-harden ok "hardened (50-dots.conf in place)"; fi
    return 0
  fi
  if _sh_sshd_on; then why="sshd is on and $(head -n 1 "$OPS_OWNER_FILE") has authorized_keys"; else why="sshd is not enabled"; fi
  ops_ask ssh-harden "Harden sshd? Installs $dst ($(_sh_desired | grep -v '^[[:space:]]*\(#\|$\)' | paste -sd, - | sed 's/,/, /g'): key-only login). Checked: $why. Validated with sshd -t before reload; removed again if invalid." "root:ssh-harden apply"
  ops_state ssh-harden warn "hardening awaits approval"
}
