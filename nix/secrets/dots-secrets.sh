# dots-secrets: one-time, stateful steps for the KeePassXC vault (see nix/secrets.nix).
#   init            create the vault (master password + key file) and its groups
#   import-ssh      put every private key in ~/.ssh into the vault (agent: add on unlock, remove on lock)
#   switch-secrets  move the Secret Service from gnome-keyring to KeePassXC, copying every item
#   move-tokens     move CLI tokens off plaintext files (gh, docker)
#   status          one screen: what holds which secret right now
set -euo pipefail

DB=${DOTS_SECRETS_DB:-$HOME/Secrets/secrets.kdbx}
KEY=${DOTS_SECRETS_KEY:-${XDG_CONFIG_HOME:-$HOME/.config}/dots-secrets/secrets.keyx}
INI=${XDG_CONFIG_HOME:-$HOME/.config}/keepassxc/keepassxc.ini
SOCK=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/ssh-agent.socket
PW=""

die() { echo "dots-secrets: $*" >&2; exit 1; }
ask_pw() {
  [ -n "$PW" ] && return
  read -rsp "Vault master password: " PW; echo
  printf '%s\n' "$PW" | keepassxc-cli ls -q -k "$KEY" "$DB" >/dev/null 2>&1 || die "wrong password or key file"
}
kpx() { local cmd=$1; shift; printf '%s\n' "$PW" | keepassxc-cli "$cmd" -q -k "$KEY" "$DB" "$@"; }

cmd_init() {
  [ -e "$DB" ] && die "$DB already exists"
  mkdir -p "$(dirname "$DB")" "$(dirname "$KEY")"
  chmod 700 "$(dirname "$DB")" "$(dirname "$KEY")"
  echo "Choose a master password you can type from memory (a 5+ word passphrase)."
  keepassxc-cli db-create -q -p --set-key-file "$KEY" "$DB"
  chmod 600 "$KEY" "$DB"
  ask_pw
  for g in SSH Tokens Web "Secret Service"; do kpx mkdir "$g"; done
  local list=${XDG_CONFIG_HOME:-$HOME/.config}/dots-ops/vault-paths
  if [ -d "$(dirname "$list")" ] && ! grep -qxF "$DB" "$list" 2>/dev/null; then
    echo "$DB" >> "$list"; echo "Added the vault (not the key file) to dots-ops vault-backup."
  fi
  cat <<EOF

Vault:    $DB
Key file: $KEY

Do now:
  1. Copy the KEY FILE to a USB stick you keep offline. Lose it and the vault is gone.
  2. systemctl --user start keepassxc   (tray icon), open the vault with password + key file.
  3. dots-secrets import-ssh
EOF
}

KEEAGENT='<?xml version="1.0" encoding="UTF-8"?>
<EntrySettings>
  <AllowUseOfSshKey>true</AllowUseOfSshKey>
  <AddAtDatabaseOpen>true</AddAtDatabaseOpen>
  <RemoveAtDatabaseClose>true</RemoveAtDatabaseClose>
  <UseConfirmConstraintWhenAdding>false</UseConfirmConstraintWhenAdding>
  <UseLifetimeConstraintWhenAdding>false</UseLifetimeConstraintWhenAdding>
  <LifetimeConstraintDuration>600</LifetimeConstraintDuration>
  <Location>
    <SelectedType>attachment</SelectedType>
    <AttachmentName>@NAME@</AttachmentName>
    <SaveAttachmentToTempFile>false</SaveAttachmentToTempFile>
    <FileName />
  </Location>
</EntrySettings>'

private_keys() {
  local f
  for f in "$HOME"/.ssh/*; do
    [ -f "$f" ] || continue
    case ${f##*/} in *.pub|known_hosts*|config*|authorized_keys*|*.sock|*.old) continue ;; esac
    head -n1 "$f" 2>/dev/null | grep -q -- '-----BEGIN .*PRIVATE KEY-----' && echo "$f"
  done
}

cmd_import_ssh() {
  local remove=0; [ "${1:-}" = --remove-originals ] && remove=1
  [ -e "$DB" ] || die "no vault; run: dots-secrets init"
  ask_pw
  local f n tmp have
  have=$(kpx ls SSH 2>/dev/null || true)
  tmp=$(mktemp -p "${XDG_RUNTIME_DIR:-/tmp}" keeagent.XXXXXX); trap 'rm -f "$tmp"' RETURN
  while IFS= read -r f; do
    n=${f##*/}
    if grep -qxF "$n" <<<"$have"; then echo "skip  $n (already in vault)"; continue; fi
    if ssh-keygen -y -P '' -f "$f" >/dev/null 2>&1; then
      kpx add "SSH/$n" --notes "Imported from $f on $(date +%F)"
    else
      local pp; read -rsp "Passphrase for $n: " pp; echo
      printf '%s\n%s\n' "$PW" "$pp" | keepassxc-cli add -q -p -k "$KEY" "$DB" "SSH/$n" --notes "Imported from $f on $(date +%F)"
    fi
    kpx attachment-import "SSH/$n" "$n" "$f"
    printf '%s' "${KEEAGENT/@NAME@/$n}" > "$tmp"
    kpx attachment-import "SSH/$n" KeeAgent.settings "$tmp"
    echo "added $n"
  done < <(private_keys)

  echo "Lock and unlock the vault in KeePassXC, then: ssh-add -l"
  [ $remove = 1 ] || { echo "Originals kept. When ssh-add -l lists them: dots-secrets import-ssh --remove-originals"; return; }

  local listed; listed=$(SSH_AUTH_SOCK=$SOCK ssh-add -l 2>/dev/null || true)
  while IFS= read -r f; do
    local fp; fp=$(ssh-keygen -lf "$f" 2>/dev/null | awk '{print $2}')
    if [ -n "$fp" ] && grep -qF "$fp" <<<"$listed"; then
      [ -e "$f.pub" ] || ssh-keygen -y -f "$f" > "$f.pub"
      shred -u "$f"; echo "removed $f (agent has it; $f.pub kept for IdentityFile)"
    else
      echo "KEPT  $f: not in the agent yet (vault unlocked?)"
    fi
  done < <(private_keys)
  echo "In ~/.ssh/config point IdentityFile at the .pub file and add IdentitiesOnly yes."
}

cmd_switch_secrets() {
  [ -e "$DB" ] || die "no vault; run: dots-secrets init"
  @PY@ @MIGRATE@ "$INI"
}

cmd_move_tokens() {
  local who; who=$(busctl --user status org.freedesktop.secrets 2>/dev/null | grep -o 'Comm=.*' || true)
  case $who in *keepassxc*) ;; *) die "Secret Service is not KeePassXC yet ($who); run switch-secrets first" ;; esac
  if command -v gh >/dev/null && grep -q oauth_token "$HOME/.config/gh/hosts.yml" 2>/dev/null; then
    local tok; tok=$(gh auth token -h github.com)
    printf '%s' "$tok" | gh auth login -h github.com --with-token
    if grep -q oauth_token "$HOME/.config/gh/hosts.yml"; then echo "gh: token still in hosts.yml"; else echo "gh: token moved to the vault"; fi
  else echo "gh: nothing in plaintext"; fi
  local dc=$HOME/.docker/config.json
  mkdir -p "$HOME/.docker"
  if [ -s "$dc" ]; then
    @PY@ -c 'import json,sys;p=sys.argv[1];c=json.load(open(p));c["credsStore"]="secretservice";json.dump(c,open(p,"w"),indent=2)' "$dc"
  else echo '{ "credsStore": "secretservice" }' > "$dc"; fi
  echo "docker: credsStore=secretservice (run docker login again for each registry)"
  echo "manual: ~/.npmrc token, ~/.azure token cache (az has no libsecret support in nixpkgs)"
}

cmd_status() {
  local who keys
  who=$(busctl --user status org.freedesktop.secrets 2>/dev/null | grep -o 'Comm=.*' | cut -d= -f2 || true)
  keys=$(SSH_AUTH_SOCK=$SOCK ssh-add -l 2>/dev/null | grep -c '^[0-9]' || true)
  printf '%-16s %s\n' \
    vault "$( [ -e "$DB" ] && echo "$DB ($(stat -c %a "$DB"))" || echo missing)" \
    key-file "$( [ -e "$KEY" ] && echo "$KEY ($(stat -c %a "$KEY"))" || echo missing)" \
    keepassxc "$(systemctl --user is-active keepassxc 2>/dev/null)" \
    secret-service "${who:-none}" \
    ssh-agent "$(systemctl --user is-active ssh-agent 2>/dev/null), $keys key(s)" \
    SSH_AUTH_SOCK "${SSH_AUTH_SOCK:-unset}" \
    clip-filter "$(pgrep -f dots-clip-store >/dev/null && echo on || echo OFF)" \
    keys-on-disk "$(private_keys | wc -l)"
}

case ${1:-status} in
  init) cmd_init ;;
  import-ssh) shift; cmd_import_ssh "$@" ;;
  switch-secrets) cmd_switch_secrets ;;
  move-tokens) cmd_move_tokens ;;
  status) cmd_status ;;
  *) sed -n '2,7p' "$0"; exit 2 ;;
esac
