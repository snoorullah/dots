#!/usr/bin/env bash
# usage: tests/extra-tools-dryrun.sh — renders the extra-tools installer and runs it with DOTS_DRY_RUN=1 in a throwaway HOME;
# asserts every tool's install command is printed and nothing real executes.
set -uo pipefail
root="$(git rev-parse --show-toplevel)"; fail=0
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
cfg="$work/cfg.toml"; cat "$root/tests/data-nvidia-tmux.toml" > "$cfg"
script="$work/extra-tools.sh"
HOME="$work/home" chezmoi execute-template --source "$root/home" --config "$cfg" \
  < "$root/home/.chezmoiscripts/run_onchange_after_90-extra-tools.sh.tmpl" > "$script" || { echo "EXTRA: render failed"; exit 1; }
bash -n "$script" || { echo "EXTRA: bash -n failed"; exit 1; }
head -2 "$script" | grep -qE '^# pins: [0-9a-f]{64}$' || { echo "EXTRA: pins hash line missing"; fail=1; }
mkdir -p "$work/home"
# the dry run must not need any toolchain; real installs are never invoked
out="$(env -u XDG_CONFIG_HOME -u XDG_DATA_HOME -u PIPX_HOME -u PIPX_BIN_DIR HOME="$work/home" DOTS_DRY_RUN=1 bash "$script" 2>&1)"; rc=$?
# an aether package missing from the profile is a skip (non-zero) on a real run; a dry run must exit 0
[ "$rc" = 0 ] || { echo "EXTRA: dry run exited $rc"; fail=1; }
h="$work/home"
want=(
  "npm install -g --prefix $h/.local agent-browser@"
  "npm install -g --prefix $h/.local dev-browser@"
  "--ignore-scripts @earendil-works/pi-coding-agent@"
  "@mariozechner/pi-mom@"
  "@tmustier/pi-usage-extension@"
  "install --locked --root $h/.local --version 0.3.28 linear-cli"
  "install --locked --root $h/.local --version 0.1.0 tttui"
  "pipx install --force ytm-player=="
  "uv tool install --force --python 3.12.5 syncall==1.8.8"
  "<rev from $h/.nix-profile/share/aether/REV>"
  "running unverified vendor installer"
  "env SHELL=/bin/sh bash "
  "https://x.ai/cli/install.sh"
  "$h/.nix-profile/share/aether/firefox -CreateProfile aether"
  "ln -sfn $h/.nix-profile/share/aether/overlay/chrome "
  "$h/.nix-profile/share/aether/overlay/prefs/user.js"
  "$h/.nix-profile/share/aether/overlay/config/aether.toml"
)
for w in "${want[@]}"; do grep -qF -- "$w" <<<"$out" || { echo "EXTRA: missing in dry-run output: $w"; fail=1; }; done
# Nix owns these now; the script must not touch them, and must not create a launcher or checkout
for bad in hyprpm hyprcapture kdeconnect argonaut --launcher-only "git " cmake aether.desktop ".local/bin/aether"; do
  ! grep -qF -- "$bad" <<<"$out" || { echo "EXTRA: unexpected '$bad' in dry-run output"; fail=1; }
done
# nothing executed: the throwaway HOME must stay empty
if [ -n "$(find "$work/home" -mindepth 1 -print -quit)" ]; then echo "EXTRA: dry run touched HOME:"; find "$work/home" | head; fail=1; fi
[ "$fail" = 0 ] && echo "extra-tools dryrun ok" || { echo "$out" | head -80; exit 1; }
