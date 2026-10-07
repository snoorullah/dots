#!/usr/bin/env bash
# usage: tests/extra-tools-dryrun.sh — renders the extra-tools installer and runs it with DOTS_DRY_RUN=1 in a throwaway HOME;
# asserts every tool's install command is printed and nothing real executes.
set -uo pipefail
root="$(git rev-parse --show-toplevel)"; fail=0
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
cfg="$work/cfg.toml"; cat "$root/tests/data-nvidia-tmux.toml" > "$cfg"
script="$work/extra-tools.sh"
HOME="$work/home" chezmoi execute-template --source "$root/home" --config "$cfg" \
  < "$root/home/.chezmoiscripts/run_onchange_after_25-extra-tools.sh.tmpl" > "$script" || { echo "EXTRA: render failed"; exit 1; }
bash -n "$script" || { echo "EXTRA: bash -n failed"; exit 1; }
head -2 "$script" | grep -qE '^# pins: [0-9a-f]{64}$' || { echo "EXTRA: pins hash line missing"; fail=1; }
mkdir -p "$work/home"
# the dry run must not need any toolchain; real installs are never invoked
out="$(env -u XDG_CONFIG_HOME -u XDG_DATA_HOME -u PIPX_HOME -u PIPX_BIN_DIR -u HYPRLAND_INSTANCE_SIGNATURE HOME="$work/home" DOTS_DRY_RUN=1 bash "$script" 2>&1)"; rc=$?
[ "$rc" = 0 ] || { echo "EXTRA: dry run exited $rc"; echo "$out"; fail=1; }
want=(
  'npm install -g --prefix '"$work"'/home/.local agent-browser@'
  'npm install -g --prefix '"$work"'/home/.local dev-browser@'
  '--ignore-scripts @earendil-works/pi-coding-agent@'
  '@mariozechner/pi-mom@'
  '@tmustier/pi-usage-extension@'
  'install --locked --root '"$work"'/home/.local --version 0.3.28 linear-cli'
  'install --locked --root '"$work"'/home/.local --version 0.1.0 tttui'
  'pipx install --force ytm-player=='
  'pipx install --force --python python3.12 syncall=='
  'curl -fsSL -o '
  'sha256sum -c -'
  'install -Dm755 '
)
want+=(
  'argonaut-2.10.0-linux-amd64.tar.gz'
  'https://x.ai/cli/install.sh'
  'hyprpm add https://github.com/gfhdhytghd/HyprCapture 73a519e9643338e580a594f543dc738782bdbf19'
  'hyprpm enable hyprcapture'
  'hyprpm reload -n'
  'cmake --install'
  'fetch -q --depth 1 origin 5e085656802eec3e26ecf0e4c55c2a771036cf36'
  'overlay/install.sh --launcher-only'
  'firefox -CreateProfile aether'
  'ln -sfn '
  'user.js'
  'aether.toml'
)
for w in "${want[@]}"; do grep -qF -- "$w" <<<"$out" || { echo "EXTRA: missing in dry-run output: $w"; fail=1; }
done
# nothing executed: the throwaway HOME must hold no installed tools or state beyond what mktemp made
if [ -n "$(find "$work/home" -mindepth 1 -print -quit)" ]; then echo "EXTRA: dry run touched HOME:"; find "$work/home" | head; fail=1; fi
[ "$fail" = 0 ] && echo "extra-tools dryrun ok" || { echo "$out" | head -80; exit 1; }
