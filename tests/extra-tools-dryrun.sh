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
  "npm install -g --prefix $h/.local claude-mem@13.3.0"
  "npm install -g --prefix $h/.local figma-cli@1.0.0"
  "npm install -g --prefix $h/.local vercel@50.42.0"
  "npm install -g --prefix $h/.local nx@22.6.5"
  "install --locked --root $h/.local --version 0.1.1 yaml-validator-cli"
  "pipx install --force cli-anything-hub==0.3.0"
  "pipx install --force schemathesis==4.19.0"
  "pipx install --force semgrep==1.159.0"
  "uv tool install --force --python 3.14.3 claude-code-tools==1.12.0"
  "rm -f $h/.local/bin/vault"
  "env GOBIN=$h/.local/bin GOTOOLCHAIN=auto GOTELEMETRY=off go install mvdan.cc/sh/v3/cmd/gosh@v3.12.0"
  "go install github.com/alchemmist/lazy-tmux/cmd/lazy-tmux@v0.2.0"
  "go install github.com/pyrod3v/gitman/cmd/gitman@v1.2.1-0.20250212142239-5b2bd5927b4b"
  "go install github.com/peltho/tufw/cmd/tufw@v0.2.4"
  "go install github.com/slackapi/slack-cli@v0.0.0-20260911210516-fcb07820d230"
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
# `personal: true` tools: rendered for personal machines (above), absent from the orgManaged render
org="$work/extra-tools-org.sh"
HOME="$work/home" chezmoi execute-template --source "$root/home" --config "$root/tests/data-workpc-ubuntu.toml" \
  < "$root/home/.chezmoiscripts/run_onchange_after_90-extra-tools.sh.tmpl" > "$org" || { echo "EXTRA: org render failed"; fail=1; }
bash -n "$org" || { echo "EXTRA: org bash -n failed"; fail=1; }
for p in $(yq -r '.extraTools[] | select(type == "!!seq") | .[] | select(.personal == true) | (.name // .crate)' "$root/home/.chezmoidata/extra-tools.yaml"); do
  grep -qF "\"$p\"" "$script" || { echo "EXTRA: personal tool $p missing from the personal render"; fail=1; }
  ! grep -qF "\"$p\"" "$org" || { echo "EXTRA: personal tool $p rendered on an orgManaged machine"; fail=1; }
done
grep -q '^npm_tool "agent-browser"' "$org" || { echo "EXTRA: org render lost the all-machines tools"; fail=1; }
# exclude_bins (I4): the uv tool's vault link is removed right after its install, and only that tool's
grep -A1 -F 'uv tool install --force --python 3.14.3 claude-code-tools==' <<<"$out" | grep -qF "rm -f $h/.local/bin/vault" \
  || { echo "EXTRA: vault link not removed right after the claude-code-tools install"; fail=1; }
[ "$(grep -cF 'rm -f ' <<<"$out")" = 1 ] || { echo "EXTRA: rm -f for a tool without exclude_bins"; fail=1; }
# drop_bins for real (extracted from the render): removes only a symlink into the tool's dir
db="$work/drop"; mkdir -p "$db/bin" "$db/tools/t/bin" "$db/other"
touch "$db/tools/t/bin/vault" "$db/tools/t/bin/keep" "$db/other/vault2"
ln -s "$db/tools/t/bin/vault" "$db/bin/vault"; ln -s "$db/tools/t/bin/keep" "$db/bin/keep"
ln -s "$db/other/vault2" "$db/bin/vault2"; echo real > "$db/bin/vault3"
( DRY=0 BIN="$db/bin"
  log() { :; }; run() { "$@"; }
  eval "$(sed -n '/^drop_bins() {/,/^}/p' "$script")"
  drop_bins "$db/tools/t" vault vault2 vault3 missing )
[ ! -e "$db/bin/vault" ] && [ ! -L "$db/bin/vault" ] || { echo "EXTRA: drop_bins kept the tool's own vault link"; fail=1; }
[ -L "$db/bin/keep" ] || { echo "EXTRA: drop_bins removed a link it was not asked to"; fail=1; }
[ -L "$db/bin/vault2" ] || { echo "EXTRA: drop_bins removed a link into another dir"; fail=1; }
[ -f "$db/bin/vault3" ] || { echo "EXTRA: drop_bins removed a real file"; fail=1; }
rm -rf "$db"
# nothing executed: the throwaway HOME must stay empty
if [ -n "$(find "$work/home" -mindepth 1 -print -quit)" ]; then echo "EXTRA: dry run touched HOME:"; find "$work/home" | head; fail=1; fi
[ "$fail" = 0 ] && echo "extra-tools dryrun ok" || { echo "$out" | head -80; exit 1; }
