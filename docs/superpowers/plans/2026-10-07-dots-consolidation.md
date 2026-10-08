# dots Consolidation Implementation Plan (rev 2)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One repo (`dots`) — chezmoi for every file, Nix/home-manager for every package — gives the work PC's setup, minimalized (foot, zsh on antidote + zimfw modules, no rofi, one multiplexer), identically on Arch, Ubuntu, Debian, Fedora/RHEL/Rocky and NixOS, absorbing `ubuntu-dots`, `hyprland-config`, `tmux-config`.

**Architecture:** `.chezmoiroot` = `home/` (chezmoi source state). `nix/` is a home-manager flake that installs packages only. chezmoi `run_once_`/`run_onchange_` scripts do the root layer per distro and run `home-manager switch` when `nix/` changes. Live work-PC files are imported with `chezmoi add`, then templated/normalized under tests. Multiplexer is a data switch (`tmux` default, `herdr` on trial).

**Tech Stack:** chezmoi ≥2.50 (age encryption, templates), Nix (Determinate ≥2.34) + home-manager (nixos-unstable), nix-gl-host / nixGL, foot (barsmonster fork), Hyprland (latest, Lua), tmux / Herdr 0.9.3, bash, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-10-07-dots-consolidation-design.md` (rev 2)

## Global Constraints

- Precedence: work-PC live files (2026-10-07) > `tmux-config@archdesk` (tmux only) > repos; rev-2 tool replacements (kitty→foot, oh-my-zsh→antidote + zimfw modules, rofi→fzf, Hyprland→latest) override live.
- chezmoi owns files, Nix owns packages; no path managed by both (`tests/overlap.sh`).
- PATH contract: `$HOME/.local/bin:$HOME/.nix-profile/bin` precede `/usr/bin` in `environment.d`, `hyprland.lua` and `.zshenv`.
- Rendered files must not contain `/home/devsupreme`, `/home/linuxbrew`, `/snap/`, `.cargo/bin`, `/run/user/1001`, `/usr/bin/{task,timew,python3,kubectl,tmux,gh,kitty,swww}`, `kitty`, `rofi`, `oh-my-zsh`.
- Git identity everywhere: `Shaik Noorullah <snoorullah@proficientnow.com>` (clone lives under `~/work/` so `~/.gitconfig-work` applies).
- No plaintext secrets in git; owner runs secret-handling steps; never print secret contents.
- `signoz-tunnel.service` is not managed.
- System: `x86_64-linux`; HM `home.stateVersion = "25.11"`.
- Commit after each task; push branch `consolidate` to `origin` (`snoorullah/dots`); never push `main`.

## Review Focus

1. **Existing plain files at managed paths** (every current machine) → `chezmoi apply` must not silently destroy local edits: cutover runs `chezmoi diff` first and the matrix pre-creates a stale `~/.config/waybar/config.jsonc` that apply must replace. Test: Task 11 `distro-matrix.sh`.
2. **Scripts launched by Hyprland/waybar/systemd** get the PATH contract, not a login shell → pinned tools must win over `/usr/bin`. Test: Task 4 `in-home.sh` with a fake `task` (exit 99) placed *after* the Nix bin dir, plus a check that `10-dots-path.conf` orders Nix before `/usr/bin`.
3. **Fresh machine with no user data** (`~/.task`, `~/.cache/adhd`, `salah.log`, `prayer-times.conf`, `~/walls`) → status scripts exit 0 with sane output. Test: Task 4 `in-home.sh` on an empty render.
4. **Wrong GPU branch** (NVIDIA env on a mesa box = black screen; missing on NVIDIA = broken VA-API). Test: Task 2 `placement.sh` renders both `gpu=nvidia` and `gpu=mesa` and asserts `LIBVA_DRIVER_NAME` only in the nvidia render.
5. **No age key** (CI, a new machine before the key is copied) → `chezmoi apply` must succeed and skip secrets, not abort. Test: Task 3 renders without a key and asserts `.secrets` absent and exit 0.

---

## File Structure (end state)

```
.chezmoiroot                         "home"
home/.chezmoi.toml.tmpl              data: gpu (auto), multiplexer, footLigatures, timetrack; age
home/.chezmoiignore                  templated: secrets w/o key, multiplexer-specific files, timetrack
home/.chezmoidata/palette.yaml       Dracula palette used by foot, herdr, hyprland templates
home/.chezmoiscripts/
  run_once_before_00-system.sh.tmpl  root layer per distro family (skips NixOS)
  run_onchange_before_10-nix.sh.tmpl home-manager switch when nix/ changes
  run_onchange_after_20-systemd.sh.tmpl daemon-reload + enable units when unit files change
  run_once_after_30-userdata.sh.tmpl data dirs, prayer-times.conf, ~/walls clone
home/dot_config/…, home/dot_local/bin/…, home/dot_zshrc.tmpl, home/dot_zshenv.tmpl, …
home/dot_config/tmux/                tmux-config@archdesk (subtree, renamed to chezmoi attrs)
home/dot_config/herdr/config.toml.tmpl
nix/flake.nix, nix/flake.lock        homeConfigurations.{nvidia,mesa}; nixosConfigurations.nixos-laptop
nix/home.nix                         home.packages, fonts, GL wrapping — no files
nix/pkgs/{overlay,otter-launcher,adhanpy,foot-ligatures}.nix, nix/pkgs/tmux-plugins.json
nix/hosts/nixos-laptop/              NixOS system config
tests/{render,placement,lint,overlap,in-home,distro-matrix}.sh
tests/{expected-targets,expected-commands}.txt, tests/data-*.toml
tools/{pin-tmux-plugins,kitty-theme-to-foot}.sh
docs/{install,herdr-trial}.md
.github/workflows/ci.yml
```

---

### Task 1: Repo restructure, chezmoi + Nix skeletons, test harness (red)

**Files:**
- Move: `home/` → `nix/legacy-home/` (mined in later tasks, deleted in Task 10); `hosts/laptop/` → `nix/hosts/nixos-laptop/`
- Delete: `flake.nix`, `flake.lock`, `home.nix`, `hosts/archdesk/`, `docs/superpowers/{plans,specs}/2026-06-*`, `docs/superpowers/{plans,specs}/2026-07-01-*`, `docs/laptop-install.md`
- Create: `.chezmoiroot`, `home/.chezmoi.toml.tmpl`, `home/.chezmoiignore`, `home/.chezmoidata/palette.yaml`, `nix/flake.nix`, `nix/home.nix`, `nix/pkgs/overlay.nix`, `tests/*`

**Interfaces:**
- Produces: chezmoi data keys `.gpu` (`nvidia|mesa|nixos`), `.multiplexer` (`tmux|herdr`), `.footLigatures` (bool), `.timetrack` (bool), `.palette.*`; flake outputs `homeConfigurations.{nvidia,mesa}` (impure user/home), `nixosConfigurations.nixos-laptop`, `checks.x86_64-linux.deps-{nvidia,mesa}`; scripts `tests/render.sh <data-file> <out-dir>`.

- [ ] **Step 1: Restructure**

```bash
git mv home nix/legacy-home
git mv hosts/laptop nix/hosts/nixos-laptop
git rm -rq hosts/archdesk flake.nix flake.lock home.nix docs/laptop-install.md
git rm -q docs/superpowers/plans/2026-06-* docs/superpowers/plans/2026-07-01-* docs/superpowers/specs/2026-06-* docs/superpowers/specs/2026-07-01-*
printf 'home\n' > .chezmoiroot
mkdir -p home/.chezmoidata home/.chezmoiscripts tests tools
```

- [ ] **Step 2: `home/.chezmoi.toml.tmpl`**

```
{{- $gpu := "mesa" -}}
{{- if stat "/etc/NIXOS" -}}
{{-   $gpu = "nixos" -}}
{{- else if lookPath "lspci" -}}
{{-   if regexMatch "(?i)nvidia" (output "lspci") -}}{{ $gpu = "nvidia" }}{{- end -}}
{{- end -}}
{{- $mux := promptChoiceOnce . "multiplexer" "Multiplexer" (list "tmux" "herdr") "tmux" -}}
{{- $key := joinPath .chezmoi.homeDir ".config/chezmoi/key.txt" }}
sourceDir = {{ .chezmoi.sourceDir | quote }}
{{- if stat $key }}
encryption = "age"
[age]
  identity = {{ $key | quote }}
  recipient = "AGE_RECIPIENT"
{{- end }}
[data]
  gpu = {{ $gpu | quote }}
  multiplexer = {{ $mux | quote }}
  footLigatures = true
  timetrack = false
  hasAgeKey = {{ if stat $key }}true{{ else }}false{{ end }}
```
`AGE_RECIPIENT` is replaced in Task 3 Step 1 with the key's public half.

- [ ] **Step 3: `home/.chezmoiignore` and palette**

`home/.chezmoiignore`:
```
README.md
{{- if not .hasAgeKey }}
.secrets
.kube/config
.kube/onprem-s2a.yaml
.kube/ovh-k8s.conf
{{- end }}
{{- if ne .multiplexer "herdr" }}
.config/herdr
.config/systemd/user/herdr.service
{{- end }}
{{- if ne .multiplexer "tmux" }}
.config/tmux
.tmux.conf
.config/systemd/user/tmux.service
.config/otter-launcher/scripts/otter-tmux.sh
{{- end }}
{{- if not .timetrack }}
.config/systemd/user/timetrack-*
.config/timetrack
{{- end }}
```
`home/.chezmoidata/palette.yaml` (values from live `~/.config/kitty/current-theme.conf`; Task 6 Step 1 verifies them):
```yaml
palette:
  bg: "#282a36"
  fg: "#f8f8f2"
  sel: "#44475a"
  comment: "#6272a4"
  cyan: "#8be9fd"
  green: "#50fa7b"
  orange: "#ffb86c"
  pink: "#ff79c6"
  purple: "#bd93f9"
  red: "#ff5555"
  yellow: "#f1fa8c"
```

- [ ] **Step 4: Nix skeleton**

`nix/flake.nix`:
```nix
{
  description = "dots — packages for one user setup on every Linux (files are chezmoi's)";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = { url = "github:nix-community/home-manager"; inputs.nixpkgs.follows = "nixpkgs"; };
    nix-gl-host  = { url = "github:numtide/nix-gl-host";        inputs.nixpkgs.follows = "nixpkgs"; };
    nixgl        = { url = "github:nix-community/nixGL";        inputs.nixpkgs.follows = "nixpkgs"; };
    zen-browser  = { url = "github:0xc000022070/zen-browser-flake"; inputs.nixpkgs.follows = "nixpkgs"; };
    herdr.url    = "github:ogulcancelik/herdr/v0.9.3";
  };
  outputs = inputs@{ self, nixpkgs, home-manager, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; config.allowUnfree = true; overlays = [ (import ./pkgs/overlay.nix) ]; };
      mkHome = gpu: home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        extraSpecialArgs = { inherit inputs gpu; };
        modules = [ ./home.nix {
          home.username = builtins.getEnv "USER";
          home.homeDirectory = builtins.getEnv "HOME";
        } ];
      };
      act = gpu: (mkHome gpu).activationPackage;
      depsCheck = gpu: pkgs.runCommand "deps-${gpu}" { } ''
        fail=0
        while read -r c; do [ -z "$c" ] && continue
          [ -x "${act gpu}/home-path/bin/$c" ] || { echo "NO-CMD $c"; fail=1; }
        done < ${../tests/expected-commands.txt}
        [ $fail = 0 ] && touch $out
      '';
    in {
      homeConfigurations = { nvidia = mkHome "nvidia"; mesa = mkHome "mesa"; };
      nixosConfigurations.nixos-laptop = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit inputs; };
        modules = [
          ./hosts/nixos-laptop/configuration.nix
          home-manager.nixosModules.home-manager
          { nixpkgs.overlays = [ (import ./pkgs/overlay.nix) ];
            home-manager = { useGlobalPkgs = true; useUserPackages = true;
              extraSpecialArgs = { inherit inputs; gpu = "nixos"; };
              users.devsupreme = import ./home.nix; }; }
        ];
      };
      checks.${system} = { deps-nvidia = depsCheck "nvidia"; deps-mesa = depsCheck "mesa"; };
      packages.${system} = { inherit (pkgs) otter-launcher; };
    };
}
```
`nix/home.nix` (filled in Task 5):
```nix
{ pkgs, lib, gpu, inputs, ... }: {
  home.stateVersion = "25.11";
  programs.home-manager.enable = true;
  targets.genericLinux.enable = gpu != "nixos";
  home.packages = [ ];
}
```
`nix/pkgs/overlay.nix`:
```nix
final: prev: { }
```

- [ ] **Step 5: Test harness**

`tests/data-nvidia-tmux.toml` (and the same with `gpu = "mesa"` → `tests/data-mesa-tmux.toml`, and `multiplexer = "herdr"` → `tests/data-nvidia-herdr.toml`):
```toml
[data]
  gpu = "nvidia"
  multiplexer = "tmux"
  footLigatures = true
  timetrack = false
  hasAgeKey = false
```
`tests/render.sh`:
```bash
#!/usr/bin/env bash
# usage: tests/render.sh <data.toml> <out-dir>  — renders chezmoi source into out-dir (no scripts, no secrets)
set -euo pipefail
root="$(git rev-parse --show-toplevel)"; data="$1"; out="$2"
mkdir -p "$out"
cfg="$(mktemp)"; cat "$data" > "$cfg"
chezmoi apply --source "$root/home" --destination "$out" --config "$cfg" \
  --exclude=scripts,encrypted --force --no-tty
```
`tests/placement.sh`:
```bash
#!/usr/bin/env bash
# usage: tests/placement.sh — renders each data file and checks expected targets + GPU branch
set -uo pipefail
root="$(git rev-parse --show-toplevel)"; fail=0
for data in "$root"/tests/data-*.toml; do
  out="$(mktemp -d)"; bash "$root/tests/render.sh" "$data" "$out" || { echo "RENDER-FAIL $data"; fail=1; continue; }
  mux=$(sed -nE 's/ *multiplexer = "(.*)"/\1/p' "$data"); gpu=$(sed -nE 's/ *gpu = "(.*)"/\1/p' "$data")
  while read -r mode tag path; do
    case "$mode" in ""|\#*) continue ;; esac
    [ "$tag" = all ] || [ "$tag" = "$mux" ] || continue
    f="$out/$path"
    [ -e "$f" ] || { echo "MISSING[$gpu/$mux] $path"; fail=1; continue; }
    [ "$mode" != x ] || [ -x "$f" ] || { echo "NOT-EXEC[$gpu/$mux] $path"; fail=1; }
  done < "$root/tests/expected-targets.txt"
  h="$out/.config/hypr/hyprland.lua"
  if [ -f "$h" ]; then
    if [ "$gpu" = nvidia ]; then grep -q LIBVA_DRIVER_NAME "$h" || { echo "GPU: nvidia render lacks nvidia env"; fail=1; }
    else ! grep -q LIBVA_DRIVER_NAME "$h" || { echo "GPU: $gpu render has nvidia env"; fail=1; }; fi
  fi
done
exit $fail
```
`tests/lint.sh`:
```bash
#!/usr/bin/env bash
set -uo pipefail
root="$(git rev-parse --show-toplevel)"; out="$(mktemp -d)"
bash "$root/tests/render.sh" "$root/tests/data-nvidia-tmux.toml" "$out"
pat='/home/devsupreme|/home/linuxbrew|/snap/|\.cargo/bin|/run/user/1001|/usr/bin/(task|timew|python3|kubectl|tmux|gh|kitty|swww)\b|\bkitty\b|\brofi\b|oh-my-zsh'
if grep -rIlE "$pat" "$out"; then echo "LINT: files above contain forbidden patterns"; exit 1; fi
echo "lint ok"
```
`tests/overlap.sh`:
```bash
#!/usr/bin/env bash
set -uo pipefail
root="$(git rev-parse --show-toplevel)"; out="$(mktemp -d)"
bash "$root/tests/render.sh" "$root/tests/data-nvidia-tmux.toml" "$out"
act=$(USER=devsupreme HOME=/home/devsupreme nix build --impure --no-link --print-out-paths "$root/nix#homeConfigurations.nvidia.activationPackage")
comm -12 <(cd "$out" && find . -type f -o -type l | sort) <(cd "$act/home-files" && find -L . -type f | sort) | tee /dev/stderr | grep -q . && { echo "OVERLAP above"; exit 1; }
echo "no overlap"
```
`tests/expected-targets.txt` — `mode tag path`, tag = `all|tmux|herdr`:
```
f all .config/hypr/hyprland.lua
f all .config/hypr/hypridle.conf
f all .config/hypr/hyprlock.conf
f all .config/waybar/config.jsonc
f all .config/waybar/style.css
f all .config/foot/foot.ini
f all .config/foot/popup.ini
f all .config/otter-launcher/config.toml
f all .config/otter-launcher/git-profiles.conf
f all .config/otter-launcher/images/otter.png
x all .config/otter-launcher/scripts/_otter-fzf.sh
x all .config/otter-launcher/scripts/otter-app.sh
x all .config/otter-launcher/scripts/otter-banner.sh
x all .config/otter-launcher/scripts/otter-bookmarks.sh
x all .config/otter-launcher/scripts/otter-files.sh
x all .config/otter-launcher/scripts/otter-git.sh
x all .config/otter-launcher/scripts/otter-header.sh
x all .config/otter-launcher/scripts/otter-media.sh
x all .config/otter-launcher/scripts/otter-obsidian.sh
x all .config/otter-launcher/scripts/otter-power.sh
x all .config/otter-launcher/scripts/otter-projects.sh
x all .config/otter-launcher/scripts/otter-run.sh
x all .config/otter-launcher/scripts/otter-stats.sh
x all .config/otter-launcher/scripts/otter-systemd.sh
x all .config/otter-launcher/scripts/otter-tabs.sh
x tmux .config/otter-launcher/scripts/otter-tmux.sh
x all .config/otter-launcher/scripts/otter-win.sh
x all .config/otter-launcher/scripts/otter-ytm.sh
f all .config/otter-launcher/scripts/zen-utils.sh
f all .config/yazi/theme.toml
f all .config/yazi/Dracula.tmTheme
f all .config/clipse/config.json
f all .config/clipse/custom_theme.json
f all .config/mako/config
f all .config/swayosd/style.css
f all .config/starship.toml
x all .config/starship/scripts/pipeline.sh
f all .config/gtk-3.0/settings.ini
f all .config/gtk-4.0/settings.ini
f all .config/qtengine/config.json
f all .config/nvim/init.lua
f all .config/adhd/iqamah.conf
f all .config/timewarrior/timewarrior.cfg
f all .config/onprem-kube-tunnel.conf
f all .config/environment.d/10-dots-path.conf
f all .config/zsh/aliases.zsh
f all .zsh_plugins.txt
f all .config/git/config
f all .taskrc
x all .task/hooks/on-modify.timewarrior
f all .zshrc
f all .zshenv
f tmux .tmux.conf
f tmux .config/tmux/tmux.conf
f herdr .config/herdr/config.toml
x all .local/bin/adhd-block-pick.sh
x all .local/bin/adhd-break.sh
x all .local/bin/adhd-break-end.sh
x all .local/bin/adhd-capture.sh
x all .local/bin/adhd-focus.sh
x all .local/bin/adhd-salah-pick.sh
x all .local/bin/adhd-prayer-times.sh
x all .local/bin/adhd-salah-schedule.sh
x all .local/bin/adhd-salah-nudge.sh
x all .local/bin/keybind-help.sh
x all .local/bin/screenshot.sh
x all .local/bin/yazi-launch.sh
x all .local/bin/tw-tui
x all .local/bin/wallpaper
x all .local/bin/waybar-ctx.sh
x all .local/bin/waybar-kube.sh
x all .local/bin/waybar-project.sh
x all .local/bin/waybar-salah.sh
x all .local/bin/waybar-tracking.sh
x all .local/bin/ctx
x all .local/bin/kube-tunnel.sh
x all .local/bin/start-hyprland-dots
f all .config/systemd/user/adhd-prayer-times.service
f all .config/systemd/user/adhd-prayer-times.timer
f all .config/systemd/user/adhd-salah-schedule.service
f all .config/systemd/user/adhd-salah-schedule.timer
f all .config/systemd/user/aw-server.service
f all .config/systemd/user/awatcher.service
f all .config/systemd/user/foot-server.service
f all .config/systemd/user/hyprpolkitagent.service
f all .config/systemd/user/onprem-kube-tunnel.service
f all .config/systemd/user/ovh-k8s-tunnel.service
f tmux .config/systemd/user/tmux.service
f herdr .config/systemd/user/herdr.service
```
`tests/expected-commands.txt`:
```
Hyprland
hyprctl
hypridle
waybar
mako
swayosd-server
swayosd-client
swww
swww-daemon
foot
footclient
chafa
otter-launcher
clipse
yazi
fzf
task
timew
taskwarrior-tui
k9s
kubectl
starship
zsh
tmux
herdr
grim
slurp
wl-copy
playerctl
brightnessctl
nm-applet
bluetuith
jq
notify-send
eza
zoxide
gh
nvim
aw-server
awatcher
python3
git
zen
code
obsidian
chezmoi
```
`chmod +x tests/*.sh`.

- [ ] **Step 6: Run (expect red)**

```bash
(cd nix && nix flake lock)
bash tests/placement.sh | tail -5; echo "placement exit=$?"
(cd nix && nix flake check --impure 2>&1 | grep -c NO-CMD)
```
Expected: placement prints `MISSING…` lines (nothing imported yet); `nix flake check` reports `NO-CMD` lines. Evaluation itself must succeed — fix any eval error before committing.

- [ ] **Step 7: Commit**

```bash
git add -A && git commit -m "refactor: chezmoi root + packages-only nix flake skeleton; render/placement/lint/overlap tests (red)"
```

---

### Task 2: Import live files with `chezmoi add`

**Files:** Create `home/**` (chezmoi source state for every non-generated `all`/`tmux` target except foot, herdr, environment.d, aliases.zsh, start-hyprland-dots, foot-server/herdr/hyprpolkitagent units — later tasks create those).

**Interfaces:** Produces chezmoi-named source files (`dot_`, `executable_`, `private_`) mirroring the live work PC.

- [ ] **Step 1: Add live files**

```bash
cfg=$(mktemp); : > "$cfg"
add() { chezmoi --source "$PWD/home" --destination "$HOME" --config "$cfg" add --follow "$@"; }
add ~/.config/hypr/hyprland.lua ~/.config/hypr/hypridle.conf ~/.config/hypr/hyprlock.conf \
    ~/.config/waybar ~/.config/otter-launcher ~/.config/yazi/theme.toml ~/.config/yazi/Dracula.tmTheme \
    ~/.config/clipse/config.json ~/.config/clipse/custom_theme.json ~/.config/mako/config \
    ~/.config/swayosd/style.css ~/.config/starship.toml ~/.config/starship/scripts/pipeline.sh \
    ~/.config/gtk-3.0 ~/.config/gtk-4.0 ~/.config/qtengine ~/.config/nvim ~/.config/adhd/iqamah.conf \
    ~/.config/timewarrior/timewarrior.cfg ~/.config/onprem-kube-tunnel.conf ~/.taskrc \
    ~/.task/hooks/on-modify.timewarrior ~/.zshrc ~/.zshenv ~/.tmux.conf
for s in adhd-block-pick.sh adhd-break.sh adhd-break-end.sh adhd-capture.sh adhd-focus.sh adhd-salah-pick.sh \
         adhd-prayer-times.sh adhd-salah-schedule.sh adhd-salah-nudge.sh keybind-help.sh screenshot.sh \
         yazi-launch.sh tw-tui wallpaper waybar-ctx.sh waybar-kube.sh waybar-project.sh waybar-salah.sh \
         waybar-tracking.sh ctx kube-tunnel.sh; do add ~/.local/bin/$s; done
for u in adhd-prayer-times.service adhd-prayer-times.timer adhd-salah-schedule.service adhd-salah-schedule.timer \
         aw-server.service awatcher.service onprem-kube-tunnel.service ovh-k8s-tunnel.service tmux.service; do
  add ~/.config/systemd/user/$u; done
```

- [ ] **Step 2: Remove what must not be committed or is obsolete**

```bash
find home -name '*.bak' -o -name 'wtfrc-intercept*' -o -name 'clipboard_history.json' | xargs -r rm -f
rm -f home/dot_config/nvim/plugin/wtfrc-coach.lua
grep -rIlE 'BEGIN (OPENSSH|RSA|EC) PRIVATE KEY|AGE-SECRET-KEY|ghp_[A-Za-z0-9]{20}|xox[bp]-' home || echo "no secrets"
```
Expected: `no secrets` (`.zshrc` only *sources* `~/.secrets`).

- [ ] **Step 3: Fix the known dangling references**

Delete the line calling `adhd-tasks-export.sh` in `home/dot_task/hooks/executable_on-modify.timewarrior`; delete the `timetrack-datasette` module from `home/dot_config/otter-launcher/config.toml`.
```bash
grep -rn 'adhd-tasks-export\|timetrack-datasette' home || echo clean
```

- [ ] **Step 4: Run placement**

```bash
bash tests/placement.sh 2>&1 | grep -E 'MISSING|NOT-EXEC' | sort -u
```
Expected: only the targets created by later tasks remain: `.config/foot/*`, `.config/herdr/config.toml`, `.config/environment.d/10-dots-path.conf`, `.config/zsh/aliases.zsh`, `.config/git/config`, `.config/tmux/tmux.conf`, `.local/bin/start-hyprland-dots`, units `foot-server`, `herdr`, `hyprpolkitagent`. `tests/lint.sh` fails (expected red for Task 4).

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat(chezmoi): import live work-PC files verbatim (2026-10-07)"
```

---

### Task 3: Secrets with chezmoi age (owner runs Step 1–2)

> **Superseded 2026-10-07 (owner):** the repo is public, so secrets stay out of it entirely — see spec D8 and `docs/install.md` §2. Steps below are kept for history only; do not run them.

**Files:** Modify `home/.chezmoi.toml.tmpl` (recipient); create `home/encrypted_private_dot_secrets.age`, `home/dot_kube/encrypted_private_config.age`, `home/dot_kube/encrypted_private_onprem-s2a.yaml.age`, `home/dot_kube/encrypted_private_ovh-k8s.conf.age`.

- [ ] **Step 1 (owner): set the recipient**

```bash
PUB=$(nix shell nixpkgs#age -c age-keygen -y ~/.config/chezmoi/key.txt)
sed -i "s/AGE_RECIPIENT/$PUB/" home/.chezmoi.toml.tmpl
grep -c 'recipient = "age1' home/.chezmoi.toml.tmpl
```
Expected: `1`.

- [ ] **Step 2 (owner): add encrypted files**

```bash
cfg=$(mktemp); chezmoi --source "$PWD/home" execute-template --init < home/.chezmoi.toml.tmpl > "$cfg"
chezmoi --source "$PWD/home" --config "$cfg" add --encrypt ~/.secrets ~/.kube/config ~/.kube/onprem-s2a.yaml ~/.kube/ovh-k8s.conf
grep -L 'age-encryption.org' home/encrypted_private_dot_secrets.age home/dot_kube/encrypted_* || echo "all encrypted"
```
Expected: `all encrypted`.

- [ ] **Step 3: Test the no-key path (Review Focus 5)**

```bash
out=$(mktemp -d); bash tests/render.sh tests/data-nvidia-tmux.toml "$out"; echo exit=$?
test ! -e "$out/.secrets" && echo "secrets skipped"
```
Expected: `exit=0`, `secrets skipped`.

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "feat(secrets): chezmoi age-encrypted ~/.secrets and kubeconfigs; skipped without key"
```

---

### Task 4: Normalize to the PATH contract; templates for host paths

**Files:**
- Create: `home/dot_config/environment.d/10-dots-path.conf.tmpl`, `tests/in-home.sh`
- Modify (convert to `.tmpl` where noted): `home/dot_local/bin/*`, `home/dot_config/otter-launcher/scripts/*`, `home/dot_config/waybar/config.jsonc`, `home/dot_config/otter-launcher/config.toml`, `home/dot_config/yazi/theme.toml`, `home/dot_config/mako/config`, `home/dot_config/starship/scripts/executable_pipeline.sh`, `home/dot_config/systemd/user/*`

**Interfaces:** Produces `10-dots-path.conf` = `PATH=$HOME/.local/bin:$HOME/.nix-profile/bin:…`.

- [ ] **Step 1: Write the failing behavioural test**

`tests/in-home.sh`:
```bash
#!/usr/bin/env bash
# usage: HOME=<rendered-or-real home> NIXBIN=<dir with pinned tools> tests/in-home.sh
# Review Focus 2, 3: PATH contract with a hostile /usr/bin-like dir *after* Nix; empty user data.
set -uo pipefail
fail=0; B="$HOME/.local/bin"; NIXBIN="${NIXBIN:-$HOME/.nix-profile/bin}"
fake="$(mktemp -d)"; printf '#!/bin/sh\nexit 99\n' > "$fake/task"; chmod +x "$fake/task"
P="$B:$NIXBIN:$fake:/usr/bin:/bin"
grep -qE '^PATH=\$\{?HOME\}?/\.local/bin:\$\{?HOME\}?/\.nix-profile/bin:' "$HOME/.config/environment.d/10-dots-path.conf" \
  || { echo "FAIL environment.d PATH order"; fail=1; }
run() { env -i HOME="$HOME" USER="${USER:-u}" XDG_RUNTIME_DIR=/tmp PATH="$P" "$@"; }
for s in waybar-salah.sh waybar-ctx.sh waybar-tracking.sh waybar-project.sh waybar-kube.sh; do
  out="$(run "$B/$s" 2>/dev/null)"
  printf '%s' "$out" | run jq -e '.text != null' >/dev/null || { echo "FAIL $s -> '$out'"; fail=1; }
done
run "$B/adhd-focus.sh" status >/dev/null || { echo "FAIL adhd-focus.sh status"; fail=1; }
exit $fail
```
Run against a render + built packages:
```bash
out=$(mktemp -d); bash tests/render.sh tests/data-nvidia-tmux.toml "$out"
act=$(cd nix && USER=$USER HOME=$HOME nix build --impure --no-link --print-out-paths .#homeConfigurations.nvidia.activationPackage)
HOME=$out NIXBIN=$act/home-path/bin bash tests/in-home.sh; echo exit=$?
```
Expected now: FAIL (no environment.d file; packages empty until Task 5 — re-run there).

- [ ] **Step 2: environment.d**

`home/dot_config/environment.d/10-dots-path.conf.tmpl`:
```
PATH=${HOME}/.local/bin:${HOME}/.nix-profile/bin:/usr/local/bin:/usr/bin:/bin
XDG_DATA_DIRS=${HOME}/.nix-profile/share:/usr/local/share:/usr/share
KUBECONFIG=${HOME}/.kube/onprem-s2a.yaml
```
Delete the old live `20-kubeconfig.conf` if `chezmoi add` imported it (`git rm -q home/dot_config/environment.d/20-kubeconfig.conf 2>/dev/null; true`).

- [ ] **Step 3: Strip absolute tool paths from scripts**

```bash
files=$(ls home/dot_local/bin/* home/dot_config/otter-launcher/scripts/* home/dot_config/starship/scripts/*)
sed -i -E \
  -e 's#/home/linuxbrew/\.linuxbrew/bin/(task|python3|pactl)#\1#g' \
  -e 's#"?\$\{TASK_BIN:-[^}]*\}"?#task#g' \
  -e 's#/usr/bin/(timew|python3|task|kubectl|tmux|swww)\b#\1#g' \
  -e 's#(\$HOME|~)/\.cargo/bin/##g' \
  -e 's#(\$HOME|~)/\.fzf/bin:?##g' \
  -e 's#/run/user/1001#${XDG_RUNTIME_DIR}#g' \
  -e '/^export PATH=.*(linuxbrew|\.fzf|\.cargo).*$/d' $files
grep -nE '/home/linuxbrew|/usr/bin/(task|timew|python3)|\.cargo/bin|/run/user/1001' $files || echo clean
```
Expected: `clean`. Review `git diff --stat` and spot-check `git diff home/dot_local/bin/executable_adhd-focus.sh` (paths only).

- [ ] **Step 4: Template host paths in configs**

```bash
for f in home/dot_config/waybar/config.jsonc home/dot_config/otter-launcher/config.toml home/dot_config/yazi/theme.toml home/dot_config/mako/config; do
  sed -i 's#/home/devsupreme#{{ .chezmoi.homeDir }}#g' "$f"; git mv "$f" "$f.tmpl"; done
sed -i -E 's#/home/devsupreme#%h#g; s#/usr/bin/(tmux|ssh|kubectl)#%h/.nix-profile/bin/\1#g' home/dot_config/systemd/user/*
grep -rn '/home/devsupreme' home --include='*.tmpl' --include='*.service' || echo clean
```
In `mako/config.tmpl` the icon line becomes `icon-path={{ .chezmoi.homeDir }}/.nix-profile/share/icons/Papirus-Dark`.

- [ ] **Step 5: Commit** (in-home goes green after Task 5)

```bash
bash tests/lint.sh || true
git add -A && git commit -m "feat: PATH contract via environment.d; strip host tool paths; template home paths"
```

---

### Task 5: Packages (Nix), incl. otter-launcher, adhanpy, foot fork, Herdr

**Files:** Create `nix/pkgs/otter-launcher.nix`, `nix/pkgs/adhanpy.nix`, `nix/pkgs/foot-ligatures.nix`; modify `nix/pkgs/overlay.nix`, `nix/home.nix`, `home/dot_local/bin/executable_adhd-prayer-times.sh`.

**Interfaces:** Produces `pkgs.otter-launcher`, `pkgs.dotsAdhanPython`, `pkgs.foot-ligatures`; HM profile contains every command in `tests/expected-commands.txt`.

- [ ] **Step 1: otter-launcher (crates.io 0.7.5 = live)**

`nix/pkgs/otter-launcher.nix`:
```nix
{ lib, rustPlatform, fetchCrate }:
rustPlatform.buildRustPackage rec {
  pname = "otter-launcher"; version = "0.7.5";
  src = fetchCrate { inherit pname version; hash = lib.fakeHash; };
  cargoHash = lib.fakeHash;
  meta.mainProgram = "otter-launcher";
}
```

- [ ] **Step 2: adhanpy (version from the live venv)**

```bash
~/.local/share/adhd/venv/bin/pip show adhanpy | grep Version
```
`nix/pkgs/adhanpy.nix` (set `version` to that output):
```nix
{ python3Packages, fetchPypi, lib }:
python3Packages.buildPythonPackage rec {
  pname = "adhanpy"; version = "1.0.5";
  pyproject = true;
  src = fetchPypi { inherit pname version; hash = lib.fakeHash; };
  build-system = [ python3Packages.setuptools ];
  pythonImportsCheck = [ "adhanpy" ];
}
```

- [ ] **Step 3: foot with ligatures (fork, pinned)**

```bash
git ls-remote https://codeberg.org/barsmonster/foot HEAD   # copy the sha
```
`nix/pkgs/foot-ligatures.nix` (put the sha in `rev`):
```nix
{ foot, fetchFromGitea, lib }:
foot.overrideAttrs (_: {
  pname = "foot-ligatures";
  src = fetchFromGitea { domain = "codeberg.org"; owner = "barsmonster"; repo = "foot"; rev = "SHA_FROM_LS_REMOTE"; hash = lib.fakeHash; };
})
```
Replace `SHA_FROM_LS_REMOTE` with the sha printed above before building.

- [ ] **Step 4: Overlay**

```nix
final: prev: {
  otter-launcher  = final.callPackage ./otter-launcher.nix { };
  foot-ligatures  = final.callPackage ./foot-ligatures.nix { };
  dotsAdhanPython = final.python3.withPackages (ps: [ (final.callPackage ./adhanpy.nix { python3Packages = ps; }) ]);
}
```
Resolve each `lib.fakeHash` by building and pasting the `got:` hash:
```bash
cd nix && nix build .#otter-launcher 2>&1 | grep 'got:'; cd ..
```

- [ ] **Step 5: `nix/home.nix` package set**

```nix
{ config, pkgs, lib, gpu, inputs, ... }:
let
  glhost = inputs.nix-gl-host.packages.${pkgs.system}.default;
  wrapNvidia = drv: pkgs.symlinkJoin {
    name = "${drv.name}-nixglhost"; paths = [ drv ]; nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''for b in $out/bin/*; do t=$(readlink -f "$b"); rm "$b"; makeWrapper ${glhost}/bin/nixglhost "$b" --add-flags "$t"; done'';
  };
  # GPU-dependent GL wrapper (spec D2): nvidia → nix-gl-host, mesa → nixGL, nixos → none.
  gl = drv:
    if gpu == "nvidia" then wrapNvidia drv
    else if gpu == "mesa" then config.lib.nixGL.wrap drv
    else drv;
in {
  home.stateVersion = "25.11";
  programs.home-manager.enable = true;
  targets.genericLinux.enable = gpu != "nixos";
  targets.genericLinux.nixGL = lib.mkIf (gpu == "mesa") { packages = inputs.nixgl.packages; defaultWrapper = "mesa"; };
  fonts.fontconfig.enable = true;
  home.packages = with pkgs; [
    (gl hyprland)
    hypridle hyprpolkitagent xdg-desktop-portal-hyprland hyprpicker
    waybar mako swayosd swww foot-ligatures chafa otter-launcher clipse yazi ffmpegthumbnailer unar file fd
    grim slurp wl-clipboard playerctl brightnessctl networkmanagerapplet bluetuith libnotify papirus-icon-theme
    taskwarrior3 timewarrior taskwarrior-tui aw-server-rust awatcher dotsAdhanPython
    zsh antidote starship zoxide fzf eza bat ripgrep jq gh neovim git chezmoi
    tmux inputs.herdr.packages.${pkgs.system}.default
    kubectl k9s openssh
    inputs.zen-browser.packages.${pkgs.system}.default vscode obsidian slack thunderbird
    nerd-fonts.jetbrains-mono nerd-fonts.fantasque-sans-mono victor-mono material-symbols noto-fonts noto-fonts-color-emoji
    kdePackages.breeze kdePackages.breeze-icons
  ];
}
```
Verify the herdr flake output name first:
```bash
nix flake show github:ogulcancelik/herdr/v0.9.3 2>/dev/null | grep -A3 packages
```
If the default package attribute differs, use the name shown.

- [ ] **Step 6: Point prayer times at the Nix python**

In `home/dot_local/bin/executable_adhd-prayer-times.sh` delete the venv bootstrap (`VDIR=…` and the `if [ ! -x "$VDIR/bin/python" ] … fi` block) and replace `"$VDIR/bin/python" -` with `python3 -`.

- [ ] **Step 7: Checks**

```bash
(cd nix && nix flake check --impure 2>&1 | grep NO-CMD || echo "deps green")
out=$(mktemp -d); bash tests/render.sh tests/data-nvidia-tmux.toml "$out"
act=$(cd nix && nix build --impure --no-link --print-out-paths .#homeConfigurations.nvidia.activationPackage)
HOME=$out NIXBIN=$act/home-path/bin bash tests/in-home.sh; echo in-home=$?
bash tests/overlap.sh
```
Expected: `deps green` (foot/herdr/chafa present; Task 6 adds the foot configs), `in-home=0`, `no overlap`. Typical fix: an empty-home waybar script errors → add a guard printing `{"text":""}`.

- [ ] **Step 8: Commit**

```bash
git add -A && git commit -m "feat(nix): packages-only HM: otter-launcher, adhanpy, foot-ligatures, herdr, GL wrapping"
```

---

### Task 6: Terminal → foot (kitty removed)

**Files:** Create `tools/kitty-theme-to-foot.sh`, `home/dot_config/foot/foot.ini.tmpl`, `home/dot_config/foot/popup.ini.tmpl`, `home/dot_config/systemd/user/foot-server.service`; modify every file invoking `kitty`; delete kitty configs.

**Interfaces:** Popup invocation everywhere: `foot -a <app-id> -c ~/.config/foot/popup.ini <cmd…>`; main terminal: `footclient`.

- [ ] **Step 1: Confirm palette against the live kitty theme**

```bash
grep -E '^(foreground|background|selection_background|color[0-9]+)\s' ~/.config/kitty/current-theme.conf
```
Make `home/.chezmoidata/palette.yaml` match these values exactly (live wins).

- [ ] **Step 2: foot configs**

`home/dot_config/foot/foot.ini.tmpl`:
```ini
font=JetBrainsMono Nerd Font:size=11
pad=10x8
term=foot
{{- if .footLigatures }}
[tweak]
ligatures=yes
{{- end }}
[colors]
alpha=0.92
foreground={{ trimPrefix "#" .palette.fg }}
background={{ trimPrefix "#" .palette.bg }}
selection-background={{ trimPrefix "#" .palette.sel }}
regular0=21222c
regular1={{ trimPrefix "#" .palette.red }}
regular2={{ trimPrefix "#" .palette.green }}
regular3={{ trimPrefix "#" .palette.yellow }}
regular4={{ trimPrefix "#" .palette.purple }}
regular5={{ trimPrefix "#" .palette.pink }}
regular6={{ trimPrefix "#" .palette.cyan }}
regular7={{ trimPrefix "#" .palette.fg }}
bright0={{ trimPrefix "#" .palette.comment }}
bright1=ff6e6e
bright2=69ff94
bright3=ffffa5
bright4=d6acff
bright5=ff92df
bright6=a4ffff
bright7=ffffff
[key-bindings]
spawn-terminal=none
```
(`spawn-terminal=none`: no terminal-level window spawning; tmux/herdr own multiplexing.) If the live kitty `color0`–`color15` differ from the Dracula values above, copy the live values.

`home/dot_config/foot/popup.ini.tmpl` (replaces kitty `otter.conf`, `tasktui.conf`, `bluetuith.conf`; background images dropped, glass via alpha + Hyprland blur):
```ini
[main]
include=~/.config/foot/foot.ini
pad=18x14
[colors]
alpha=0.80
```
`home/dot_config/systemd/user/foot-server.service`:
```ini
[Unit]
Description=foot terminal server
PartOf=graphical-session.target
[Service]
ExecStart=%h/.nix-profile/bin/foot --server
Restart=on-failure
[Install]
WantedBy=graphical-session.target
```

- [ ] **Step 3: Replace every kitty invocation**

```bash
grep -rlE '\bkitty\b' home | sort
```
Rewrite rules (apply to each listed file; `.lua` binds, waybar `on-click`, otter `config.toml.tmpl` and scripts, `keybind-help.sh`, `wallpaper`):
- `kitty --class X --config ~/.config/kitty/<any>.conf -e CMD…` → `foot -a X -c ~/.config/foot/popup.ini CMD…`
- `kitty --class X -e CMD…` → `foot -a X -c ~/.config/foot/popup.ini CMD…`
- bare `kitty` (Super+Return, autostart) → `footclient`
- `kitty +kitten icat … FILE` (wallpaper preview, otter banner) → `chafa -f sixel -s "${FZF_PREVIEW_COLUMNS}x${FZF_PREVIEW_LINES}" FILE`
```bash
git rm -rq home/dot_config/kitty 2>/dev/null; true
grep -rnE '\bkitty\b' home || echo "kitty gone"
```
Hyprland window rules keep matching the same names because foot's `-a` sets the Wayland app-id that Hyprland's `class` matches.

- [ ] **Step 4: Tests**

```bash
bash tests/lint.sh && bash tests/placement.sh | grep -E 'foot' || echo "foot targets present"
```
Expected: `lint ok` may still fail only on `rofi`/`oh-my-zsh` (Task 7).

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat(foot): replace kitty — foot (ligature fork), popup.ini glass popups, chafa sixel previews"
```

---

### Task 7: zsh on antidote + zimfw modules, no rofi, git identity

**Files:** Modify `home/dot_zshrc` → `home/dot_zshrc.tmpl`, `home/dot_zshenv` → `home/dot_zshenv.tmpl`, `home/dot_local/bin/executable_adhd-capture.sh`, `home/dot_config/hypr/hyprland.lua`; create `home/dot_zsh_plugins.txt`, `tools/pin-zsh-plugins.sh`, `home/dot_config/zsh/aliases.zsh`, `home/dot_config/git/config.tmpl`, `home/dot_config/git/work`.

- [ ] **Step 1: `.zshenv`**

`home/dot_zshenv.tmpl`:
```zsh
# PATH contract (spec): local scripts, then pinned Nix tools, then the distro.
typeset -U path PATH
path=($HOME/.local/bin(N-/) $HOME/.nix-profile/bin(N-/) $path)
[ -r "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"
export KUBECONFIG="$HOME/.kube/onprem-s2a.yaml"
export EDITOR=nvim VISUAL=nvim
```

- [ ] **Step 2: Plugin list with pins — `.zsh_plugins.txt`**

`home/dot_zsh_plugins.txt` (order matters: completion after everything that adds to `fpath`; fast-syntax-highlighting last). `PIN` is replaced by Step 3:
```
zimfw/environment                          pin:PIN
zimfw/input                                pin:PIN
zimfw/utility                              pin:PIN
zimfw/git                                  pin:PIN
zsh-users/zsh-autosuggestions              pin:PIN
MichaelAquilina/zsh-you-should-use         pin:PIN
zimfw/completion                           pin:PIN
zdharma-continuum/fast-syntax-highlighting pin:PIN
```

- [ ] **Step 3: Resolve pins — `tools/pin-zsh-plugins.sh`**

```bash
#!/usr/bin/env bash
# Replaces each "pin:PIN" with the current HEAD commit of that repo (re-run to bump all pins).
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
f=home/dot_zsh_plugins.txt; tmp=$(mktemp)
while read -r repo rest; do
  [ -z "$repo" ] && continue
  sha=$(git ls-remote "https://github.com/$repo" HEAD | cut -f1)
  printf '%-42s pin:%s\n' "$repo" "$sha"
done < <(sed -E 's/ +pin:[^ ]*//' "$f") > "$tmp"
mv "$tmp" "$f"; grep -c 'pin:[0-9a-f]\{40\}' "$f"
```
```bash
bash tools/pin-zsh-plugins.sh
```
Expected: `8`.

- [ ] **Step 4: `.zshrc` on antidote**

Rewrite `home/dot_zshrc.tmpl` keeping every live behaviour that is not oh-my-zsh: history-disabled block (live 2026-09-22), starship + zoxide init, fzf keybindings, kubectl completion, `~/.secrets` sourcing, user aliases:
```zsh
# ~/.zshrc — antidote (Nix) + pinned zimfw modules (~/.zsh_plugins.txt, chezmoi).
zstyle ':zim:git' aliases-prefix 'g'                                     # oh-my-zsh-style gs, gc, gp…
zstyle ':zim:completion' dumpfile "${XDG_CACHE_HOME:-$HOME/.cache}/zcompdump"
zstyle ':antidote:bundle' use-friendly-names 'yes'
source "$HOME/.nix-profile/share/antidote/antidote.zsh"
antidote load "$HOME/.zsh_plugins.txt" "${XDG_CACHE_HOME:-$HOME/.cache}/zsh_plugins.zsh"
bindkey -v; export KEYTIMEOUT=1
source "$HOME/.config/zsh/aliases.zsh"
[[ -r ~/.secrets ]] && source ~/.secrets
(( $+commands[kubectl] )) && source <(kubectl completion zsh)
(( $+commands[fzf] ))     && source <(fzf --zsh)
eval "$(zoxide init zsh)"
eval "$(starship init zsh)"
# --- live: history disabled (2026-09-22) — copied verbatim from the old .zshrc ---
HISTSIZE=0
setopt no_share_history no_inc_append_history no_append_history no_extended_history
```
Confirm the antidote path in the built profile (adjust the `source` line if it differs):
```bash
act=$(cd nix && nix build --impure --no-link --print-out-paths .#homeConfigurations.nvidia.activationPackage)
find -L $act/home-path/share -name antidote.zsh
```
Move every non-oh-my-zsh alias/function from the old `.zshrc` into `home/dot_config/zsh/aliases.zsh` (git aliases now come from `zimfw/git`), plus replacements for dropped oh-my-zsh plugins actually used:
```zsh
alias ls='eza' ll='eza -l --git' la='eza -la --git' cat='bat --paging=never' lg='lazygit' k='kubectl'
copyfile() { wl-copy < "$1"; }
web()      { xdg-open "https://duckduckgo.com/?q=${*// /+}"; }
```

- [ ] **Step 5: Shell checks**

```bash
zsh -n home/dot_zshrc.tmpl && echo syntax-ok
grep -nE 'oh-my-zsh|ZSH_CUSTOM|plugins=\(|asdf|envman|linuxbrew|batcat' home/dot_zshrc.tmpl || echo clean
out=$(mktemp -d); bash tests/render.sh tests/data-nvidia-tmux.toml "$out"
mkdir -p "$out/.nix-profile"; ln -s "$act/home-path/share" "$out/.nix-profile/share"; ln -s "$act/home-path/bin" "$out/.nix-profile/bin"
HOME=$out PATH=$act/home-path/bin:$PATH zsh -i -c 'alias gs >/dev/null && whence -w compinit && echo zsh-ok' 2>&1 | tail -3
```
Expected: `syntax-ok`, `clean`, `zsh-ok` with no error lines (first run downloads the 8 pinned repos into `~/.cache/antidote`).
Startup-time check after Task 10 cutover: `for i in 1 2 3; do /usr/bin/time -f %e zsh -i -c exit; done` → each < 0.15 s.

- [ ] **Step 6: rofi → fzf capture**

In `home/dot_local/bin/executable_adhd-capture.sh` replace the rofi block (the `theme=…rofi…` line and both `rofi -dmenu` lines) with:
```bash
text=$(fzf --print-query --prompt='  capture › ' --height=100% --reverse --no-info < /dev/null | head -1) || true
[ -n "$text" ] || exit 0
```
In `hyprland.lua` change the `Super+Shift+A` bind to `foot -a capture -c ~/.config/foot/popup.ini ~/.local/bin/adhd-capture.sh` and add a float + center + `size 700 120` window rule for class `capture`. Delete the `rofi` layer rule.

- [ ] **Step 7: git config (work identity)**

`home/dot_config/git/config.tmpl` (replaces `~/.gitconfig`; remove `home/dot_gitconfig` if it was imported):
```ini
[user]
	name = Shaik Noorullah
	email = snoorullah@proficientnow.com
[init]
	defaultBranch = main
[credential "https://github.com"]
	helper =
	helper = !gh auth git-credential
[credential "https://gist.github.com"]
	helper =
	helper = !gh auth git-credential
[includeIf "gitdir:~/work/"]
	path = ~/.config/git/work
```
`home/dot_config/git/work`:
```ini
[user]
	name = Shaik Noorullah
	email = snoorullah@proficientnow.com
```
```bash
grep -rn 'shaiknooru247' home && echo FAIL || echo "no gmail"
bash tests/lint.sh
```
Expected: `no gmail`, `lint ok`.

- [ ] **Step 8: Commit**

```bash
git add -A && git commit -m "feat(shell): antidote + pinned zimfw modules (bindkey -v); rofi→fzf capture; work git identity"
```

---

### Task 8: Hyprland — latest, templated, ported to 0.56

**Files:** `home/dot_config/hypr/hyprland.lua` → `hyprland.lua.tmpl`; create `home/dot_local/bin/executable_start-hyprland-dots`, `home/dot_config/systemd/user/hyprpolkitagent.service`.

- [ ] **Step 1: Template the env block**

At the top of `hyprland.lua.tmpl`, replace the literal env lines (NVIDIA vars, `KUBECONFIG`, `XDG_DATA_DIRS`) with:
```lua
local HOME = os.getenv("HOME")
hl.env("PATH", HOME .. "/.local/bin:" .. HOME .. "/.nix-profile/bin:/usr/local/bin:/usr/bin:/bin")
hl.env("XDG_DATA_DIRS", HOME .. "/.nix-profile/share:/usr/local/share:/usr/share")
hl.env("KUBECONFIG", HOME .. "/.kube/onprem-s2a.yaml")
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "auto")
{{- if eq .gpu "nvidia" }}
hl.env("LIBVA_DRIVER_NAME", "nvidia")
hl.env("__GLX_VENDOR_LIBRARY_NAME", "nvidia")
hl.env("NVD_BACKEND", "direct")
{{- end }}
```
Then:
```bash
f=home/dot_config/hypr/hyprland.lua.tmpl
sed -i -E -e 's#"\$HOME/\.nix-profile/bin/([a-z-]+)"#"\1"#g' -e 's#/home/devsupreme/#~/#g' "$f"
grep -nE '/home/devsupreme|\.nix-profile/bin/' "$f" || echo clean
```

- [ ] **Step 2: Session launcher and polkit unit**

`home/dot_local/bin/executable_start-hyprland-dots`:
```sh
#!/bin/sh
# Display-manager session entry (run_once system script installs hyprland-dots.desktop → here).
export PATH="$HOME/.local/bin:$HOME/.nix-profile/bin:$PATH"
exec start-hyprland "$@"
```
`home/dot_config/systemd/user/hyprpolkitagent.service`:
```ini
[Unit]
Description=Hyprland polkit agent
PartOf=graphical-session.target
[Service]
ExecStart=%h/.nix-profile/libexec/hyprpolkitagent
Restart=on-failure
[Install]
WantedBy=graphical-session.target
```
Check the libexec path: `ls $act/home-path/libexec/ | grep polkit` (fix the path to what exists).

- [ ] **Step 3: Verify/port to the new Hyprland**

```bash
out=$(mktemp -d); bash tests/render.sh tests/data-nvidia-tmux.toml "$out"
act=$(cd nix && nix build --impure --no-link --print-out-paths .#homeConfigurations.nvidia.activationPackage)
HOME=$out $act/home-path/bin/Hyprland --verify-config -c "$out/.config/hypr/hyprland.lua" 2>&1 | tail -20
```
Expected: `config ok`. For each error, look up the renamed/removed field in the release notes of every version after 0.55.4 (`https://github.com/hyprwm/Hyprland/releases`), fix `hyprland.lua.tmpl`, re-run. List each change in the commit message.

- [ ] **Step 4: Placement (GPU branch, Review Focus 4)**

```bash
bash tests/placement.sh | grep GPU || echo "gpu branch ok"
```

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat(hypr): latest Hyprland, templated env/GPU block, session launcher; port config to <version>"
```

---

### Task 9: Multiplexer module — tmux default, Herdr trial

**Files:** Create `home/dot_config/tmux/**` (subtree), `tools/pin-tmux-plugins.sh`, `nix/pkgs/tmux-plugins.json`, `home/dot_config/herdr/config.toml.tmpl`, `home/dot_config/systemd/user/herdr.service`, `docs/herdr-trial.md`; modify `nix/pkgs/overlay.nix`, `nix/home.nix`, `home/dot_tmux.conf`.

**Interfaces:** chezmoi data `.multiplexer`; Nix `pkgs.dotsTmuxPluginFarm` at `~/.nix-profile/share/tmux-plugins/<dir>`; `~/.config/tmux/plugins` → symlink to it.

- [ ] **Step 1: Import tmux-config@archdesk with history**

```bash
git remote add tmux-upstream https://github.com/shaiknoorullah/tmux-config.git
git fetch tmux-upstream archdesk
git subtree add --prefix=home/dot_config/tmux tmux-upstream archdesk -m "chore(tmux): import tmux-config@archdesk with history"
cd home/dot_config/tmux
for f in $(git ls-files 'scripts/*.sh' install.sh); do [ -x "$f" ] && git mv "$f" "$(dirname $f)/executable_$(basename $f)"; done
git rm -q install.sh README.md 2>/dev/null; true     # chezmoi + nix replace the installer
cd -
```
`home/dot_tmux.conf` keeps its live content (`source-file ~/.config/tmux/tmux.conf` + local overrides).

- [ ] **Step 2: Pin plugins (15 `@plugin`s; 6 pinned in plugins.lock, 9 from the live checkouts)**

`plugins.lock@archdesk`:
```
tmux-continuum 0698e8f4b17d6454c71bf5212895ec055c578da0
tmux-prefix-highlight 06cbb4ecd3a0a918ce355c70dc56d79debd455c7
tmux-resurrect cff343cf9e81983d3da0c8562b01616f12e8d548
tmux-sensible 25cb91f42d020f675bb0a2ce3fbd3a5d96119efa
tmux-yank acfd36e4fcba99f8310a7dfb432111c242fe7392
tpm 99469c4a9b1ccf77fade25842dc7bafbc8ce9946
```
`tools/pin-tmux-plugins.sh`:
```bash
#!/usr/bin/env bash
# Writes nix/pkgs/tmux-plugins.json for every @plugin in tmux.conf (rev: plugins.lock, else live checkout).
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
cfg=home/dot_config/tmux; live="$HOME/tmux-config/plugins"; out=nix/pkgs/tmux-plugins.json
printf '[' > $out; sep=
grep -oE "@plugin '[^']+'" $cfg/tmux.conf | sed -E "s/@plugin '([^']+)'/\1/" | while read -r slug; do
  owner=${slug%/*}; repo=${slug#*/}
  rev=$(awk -v r="$repo" '$1==r{print $2}' $cfg/plugins.lock)
  [ -n "$rev" ] || rev=$(git -C "$live/$repo" rev-parse HEAD)
  hash=$(nix run nixpkgs#nix-prefetch-github -- --rev "$rev" "$owner" "$repo" | nix run nixpkgs#jq -- -r .hash)
  printf '%s{"dir":"%s","owner":"%s","repo":"%s","rev":"%s","hash":"%s"}' "$sep" "$repo" "$owner" "$repo" "$rev" "$hash" >> $out; sep=,
done
printf ']\n' >> $out
nix run nixpkgs#jq -- length $out
```
```bash
bash tools/pin-tmux-plugins.sh
```
Expected: `15`.

- [ ] **Step 3: Plugin farm in Nix + symlink from chezmoi**

Add to `nix/pkgs/overlay.nix`:
```nix
  dotsTmuxPluginFarm = final.linkFarm "dots-tmux-plugins" (map (p: {
    name = "share/tmux-plugins/${p.dir}";
    path = final.fetchFromGitHub { inherit (p) owner repo rev hash; };
  }) (builtins.fromJSON (builtins.readFile ./tmux-plugins.json)));
```
Add `dotsTmuxPluginFarm` to `home.packages`. Create the chezmoi symlink `home/dot_config/tmux/symlink_plugins` containing:
```
{{ .chezmoi.homeDir }}/.nix-profile/share/tmux-plugins
```
(rename to `symlink_plugins.tmpl`). TPM never fetches; resurrect/continuum/etc. load from the farm.

- [ ] **Step 4: Herdr config (trial)**

Start from Herdr's defaults, then apply the decisions below:
```bash
act=$(cd nix && nix build --impure --no-link --print-out-paths .#homeConfigurations.nvidia.activationPackage)
$act/home-path/bin/herdr --default-config > home/dot_config/herdr/config.toml.tmpl
```
Edit `home/dot_config/herdr/config.toml.tmpl`:
```toml
[keys]
prefix = "ctrl+space"            # same prefix as tmux-config

[[keys.command]]
key = "prefix+p"
type = "popup"
command = "~/.config/tmux/scripts/pass-menu.sh"

[[keys.command]]
key = "prefix+S"
type = "popup"
command = "~/.config/tmux/scripts/ssh-menu.sh"

[theme.custom]
sidebar_bg = "{{ .palette.bg }}"
accent = "{{ .palette.purple }}"

[ui]
tab_bar_right = [
  { type = "command", command = "~/.config/tmux/scripts/task-status.sh", interval_seconds = 15 },
  { type = "command", command = "~/.config/tmux/scripts/git-status.sh", interval_seconds = 10 },
  { type = "datetime", format = "%H:%M" },
]
```
Keep the default `[session]` restore keys enabled. The tmux-config scripts used here live under `.config/tmux` — move these four (`pass-menu`, `ssh-menu`, `task-status`, `git-status`) to `home/dot_config/dots-mux/` and point both tmux.conf and herdr at the new path, so they exist whichever multiplexer is selected:
```bash
grep -nE 'tmux (display|send|list|show)' home/dot_config/tmux/scripts/executable_{pass-menu,ssh-menu,task-status,git-status}.sh
```
Any `tmux …` call found must be guarded with `[ -n "$TMUX" ] &&` so the script also runs under Herdr.

`home/dot_config/systemd/user/herdr.service`:
```ini
[Unit]
Description=Herdr agent multiplexer server
[Service]
ExecStart=%h/.nix-profile/bin/herdr server
Restart=on-failure
[Install]
WantedBy=default.target
```
Confirm the server subcommand name with `herdr --help` and fix `ExecStart` to match.

- [ ] **Step 5: Trial protocol — `docs/herdr-trial.md`**

```markdown
# Herdr trial (7 days) — keep exactly one multiplexer afterwards

Switch:  `sed -i 's/multiplexer = "tmux"/multiplexer = "herdr"/' ~/.config/chezmoi/chezmoi.toml && chezmoi apply`
Back:    `sed -i 's/multiplexer = "herdr"/multiplexer = "tmux"/' ~/.config/chezmoi/chezmoi.toml && chezmoi apply`
(`promptChoiceOnce` keeps the stored value, so `chezmoi init` will not reset it.)

| # | Criterion | Pass if | Result |
|---|---|---|---|
| 1 | vi copy mode + yank | search, select, yank to wl-clipboard work from keyboard | |
| 2 | Claude agents state | sidebar shows working/blocked/idle correctly for 3+ concurrent Claude Code panes | |
| 3 | Restore | after reboot, agents resume with their original flags (incl. `--dangerously-skip-permissions`, `-c`) | |
| 4 | Notifications | a blocked agent produces a mako toast within 10 s | |
| 5 | Popups | pass-menu and ssh-menu work from prefix keys | |
| 6 | nvim | working without tmux-config's "hide status when nvim focused" is acceptable | |
| 7 | Memory | `ps -o rss= -C herdr` with 6 agents ≤ 200 MB | |
| 8 | Stability | no crash in `journalctl --user -u herdr` over 7 days | |

Decision: Herdr wins only if 1–5 and 8 pass. Record the decision and date here, then run Task 12.
```

- [ ] **Step 6: Tests**

```bash
bash tests/placement.sh && bash tests/lint.sh && bash tests/overlap.sh
```
Expected: all pass for both `data-nvidia-tmux.toml` and `data-nvidia-herdr.toml`.

- [ ] **Step 7: Commit**

```bash
git add -A && git commit -m "feat(mux): tmux-config@archdesk + nix-pinned plugin farm; herdr trial config + protocol"
```

---

### Task 10: Services, user data, root layer, NixOS, docs

**Files:** Create `home/.chezmoiscripts/run_once_before_00-system.sh.tmpl`, `run_onchange_before_10-nix.sh.tmpl`, `run_onchange_after_20-systemd.sh.tmpl`, `run_once_after_30-userdata.sh.tmpl`, `system/keyd/default.conf`, `docs/install.md`; modify `nix/hosts/nixos-laptop/configuration.nix`; delete `nix/legacy-home/` after moving the laptop timetrack lib to `nix/pkgs/timetrack/`.

- [ ] **Step 1: Root layer per distro**

`home/.chezmoiscripts/run_once_before_00-system.sh.tmpl`:
```bash
#!/usr/bin/env bash
# Root-level pieces. Runs once per machine. NixOS: handled by nix/hosts.
set -euo pipefail
{{- $id := .chezmoi.osRelease.id }}{{ $like := .chezmoi.osRelease.idLike | default "" }}
{{- if eq $id "nixos" }}
exit 0
{{- end }}
command -v nix >/dev/null || { curl -fsSL https://install.determinate.systems/nix | sh -s -- install --no-confirm; }
{{- if or (eq $id "arch") (contains "arch" $like) }}
sudo pacman -S --needed --noconfirm greetd greetd-tuigreet pipewire pipewire-pulse wireplumber polkit keyd hyprlock docker xdg-desktop-portal-gtk
{{-   if eq .gpu "nvidia" }}
sudo pacman -S --needed --noconfirm nvidia-open-dkms nvidia-utils
{{-   end }}
printf 'auth include system-login\n' | sudo tee /etc/pam.d/hyprlock >/dev/null
{{- else if or (eq $id "ubuntu") (eq $id "debian") (contains "debian" $like) }}
sudo apt-get update && sudo apt-get install -y greetd pipewire pipewire-pulse wireplumber policykit-1 keyd docker.io xdg-desktop-portal-gtk software-properties-common
command -v hyprlock >/dev/null || { sudo add-apt-repository -y ppa:cppiber/hyprland && sudo apt-get install -y hyprlock; }
{{-   if eq .gpu "nvidia" }}
command -v nvidia-smi >/dev/null || sudo ubuntu-drivers install || true
{{-   end }}
printf '@include common-auth\n' | sudo tee /etc/pam.d/hyprlock >/dev/null
{{- else if or (eq $id "fedora") (contains "fedora" $like) (contains "rhel" $like) }}
sudo dnf install -y greetd tuigreet pipewire wireplumber polkit keyd docker xdg-desktop-portal-gtk || true
sudo dnf copr enable -y solopasha/hyprland && sudo dnf install -y hyprlock
printf 'auth include system-auth\n' | sudo tee /etc/pam.d/hyprlock >/dev/null
{{- end }}
sudo install -Dm644 /dev/stdin /usr/share/wayland-sessions/hyprland-dots.desktop <<EOF
[Desktop Entry]
Name=Hyprland (dots)
Exec={{ .chezmoi.homeDir }}/.local/bin/start-hyprland-dots
Type=Application
EOF
sudo install -Dm644 {{ joinPath .chezmoi.workingTree "system/keyd/default.conf" | quote }} /etc/keyd/default.conf
sudo systemctl enable --now keyd
```
```bash
mkdir -p system/keyd && sudo cat /etc/keyd/default.conf > system/keyd/default.conf
```

- [ ] **Step 2: Nix switch on change**

`home/.chezmoiscripts/run_onchange_before_10-nix.sh.tmpl`:
```bash
#!/usr/bin/env bash
# nix inputs hash: {{ include (joinPath .chezmoi.workingTree "nix/flake.lock") | sha256sum }}
# nix module hash: {{ include (joinPath .chezmoi.workingTree "nix/home.nix") | sha256sum }} {{ include (joinPath .chezmoi.workingTree "nix/pkgs/overlay.nix") | sha256sum }}
set -euo pipefail
{{- if ne .gpu "nixos" }}
[ -e /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ] && . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
nix run home-manager/master -- switch --impure --flake {{ joinPath .chezmoi.workingTree "nix" | quote }}#{{ .gpu }} -b pre-dots
{{- end }}
```

- [ ] **Step 3: systemd and user data**

`home/.chezmoiscripts/run_onchange_after_20-systemd.sh.tmpl`:
```bash
#!/usr/bin/env bash
# units hash: {{ output "sh" "-c" (printf "cat %s/dot_config/systemd/user/* | sha256sum" .chezmoi.sourceDir) }}
set -uo pipefail
systemctl --user daemon-reload
systemctl --user enable --now adhd-prayer-times.timer adhd-salah-schedule.timer aw-server.service onprem-kube-tunnel.service ovh-k8s-tunnel.service foot-server.service
{{- if eq .multiplexer "tmux" }}
systemctl --user enable --now tmux.service; systemctl --user disable --now herdr.service 2>/dev/null || true
{{- else }}
systemctl --user enable --now herdr.service; systemctl --user disable --now tmux.service 2>/dev/null || true
{{- end }}
```
`home/.chezmoiscripts/run_once_after_30-userdata.sh.tmpl` (Review Focus 3):
```bash
#!/usr/bin/env bash
set -uo pipefail
mkdir -p "$HOME/.task" "$HOME/.cache/adhd" "$HOME/.local/share/adhd" "$HOME/.kube"
touch "$HOME/.local/share/adhd/salah.log"
[ -s "$HOME/.config/adhd/prayer-times.conf" ] || "$HOME/.local/bin/adhd-prayer-times.sh" || true
[ -d "$HOME/walls/.git" ] || git clone --depth 1 https://github.com/snoorullah/walls.git "$HOME/walls" || echo "walls: clone later"
```

- [ ] **Step 4: Laptop timetrack and NixOS host**

```bash
git mv nix/legacy-home/modules/timetrack/files/timetrack-lib nix/pkgs/timetrack
git rm -rq nix/legacy-home
```
In `nix/hosts/nixos-laptop/configuration.nix` keep the existing system config; ensure `programs.hyprland.enable = true;`, `programs.hyprlock.enable = true;`, `services.keyd.enable = true;` and `environment.systemPackages = [ pkgs.chezmoi ];`.
```bash
cd nix && nix build .#nixosConfigurations.nixos-laptop.config.system.build.toplevel --dry-run && cd ..
```

- [ ] **Step 5: `docs/install.md`**

Sections: (1) `sh -c "$(curl -fsLS get.chezmoi.io)" -- -b ~/.local/bin`; (2) copy the age key to `~/.config/chezmoi/key.txt` (optional; without it secrets are skipped); (3) `chezmoi init --apply snoorullah/dots`; (4) log out → pick "Hyprland (dots)"; (5) update: `chezmoi update`; (6) review before apply: `chezmoi diff`; (7) rollback: `home-manager generations` + `*.pre-dots`, `chezmoi` keeps nothing destructive without `--force`; (8) NixOS: `sudo nixos-rebuild switch --flake ~/.local/share/chezmoi/nix#nixos-laptop` then `chezmoi apply`.

- [ ] **Step 6: Commit**

```bash
bash tests/placement.sh && bash tests/lint.sh && bash tests/overlap.sh
git add -A && git commit -m "feat: chezmoi run scripts (root layer per distro, nix switch, systemd, userdata); nixos host; install docs"
```

---

### Task 11: CI — flake check, render tests, distro matrix

**Files:** Create `tests/distro-matrix.sh`, `.github/workflows/ci.yml`.

- [ ] **Step 1: `tests/distro-matrix.sh` (runs as root in a fresh container)**

```bash
#!/usr/bin/env bash
# Review Focus 1, 3, 5: fresh distro, stale pre-existing file, no age key.
set -euo pipefail
. /etc/os-release
case " $ID ${ID_LIKE:-} " in
  *" arch "*)   pacman -Sy --noconfirm curl xz sudo git ;;
  *" debian "*|*" ubuntu "*) apt-get update && apt-get install -y curl xz-utils sudo git ;;
  *) dnf install -y curl xz sudo git shadow-utils ;;
esac
useradd -m tester; echo 'tester ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/tester
curl -fsSL https://install.determinate.systems/nix | sh -s -- install linux --init none --no-confirm
cp -r /src /home/tester/dots && chown -R tester /home/tester/dots
su - tester -c '
  set -e; . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
  mkdir -p ~/.config/waybar && echo stale > ~/.config/waybar/config.jsonc
  sh -c "$(curl -fsLS get.chezmoi.io)" -- -b ~/.local/bin
  ~/.local/bin/chezmoi init --apply --force --promptChoice multiplexer=tmux --source ~/dots/home \
     --exclude=scripts                               # root layer needs a real init system; covered on hosts
  nix run home-manager/master -- switch --impure --flake ~/dots/nix#mesa -b pre-dots
  ! grep -q stale ~/.config/waybar/config.jsonc
  test ! -e ~/.secrets
  bash ~/dots/tests/in-home.sh'
```

- [ ] **Step 2: `.github/workflows/ci.yml`**

```yaml
name: ci
on: [push, pull_request]
jobs:
  checks:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: DeterminateSystems/nix-installer-action@main
      - run: nix profile install nixpkgs#chezmoi
      - run: cd nix && nix flake check --impure
      - run: bash tests/placement.sh && bash tests/lint.sh && USER=runner bash tests/overlap.sh
  distro:
    runs-on: ubuntu-latest
    strategy:
      fail-fast: false
      matrix:
        image: [ "ubuntu:24.04", "debian:12", "archlinux:latest", "fedora:41", "rockylinux:9" ]
    steps:
      - uses: actions/checkout@v4
      - run: docker run --rm -v "$PWD:/src:ro" ${{ matrix.image }} bash /src/tests/distro-matrix.sh
```

- [ ] **Step 3: Run one distro locally, then push**

```bash
docker run --rm -v "$PWD:/src:ro" archlinux:latest bash /src/tests/distro-matrix.sh; echo exit=$?
git add -A && git commit -m "test: CI — flake check, render tests, 5-distro matrix"
git push -u origin consolidate
gh run watch --repo snoorullah/dots
```
Expected: `exit=0`; all CI jobs green.

---

### Task 12: Cutover, trial decision, archive (owner present)

- [ ] **Step 1: Work PC — point chezmoi at the repo and review the diff**

```bash
cp ~/.config/chezmoi/chezmoi.toml ~/.config/chezmoi/chezmoi.toml.pre-dots
chezmoi init --source ~/work/dots-consolidation/dots/.claude/worktrees/consolidate/home
chezmoi diff | tee /tmp/dots-cutover.diff | grep -E '^diff --git' | wc -l
```
Read `/tmp/dots-cutover.diff`. Every hunk must be one of: kitty→foot, rofi→fzf, oh-my-zsh→antidote + zimfw modules, PATH/template normalization, Hyprland 0.56 port, removed dangling refs. Anything else → fix in the repo, re-run.

- [ ] **Step 2: Apply**

```bash
nix profile remove Waybar                      # old nix-profile waybar duplicate
chezmoi apply
HYPRLAND_INSTANCE_SIGNATURE=$(ls -t $XDG_RUNTIME_DIR/hypr | head -1) hyprctl reload && hyprctl configerrors
HOME=$HOME bash ~/work/dots-consolidation/dots/.claude/worktrees/consolidate/tests/in-home.sh
```
Expected: no config errors; `in-home` exit 0. Log out → "Hyprland (dots)". Rollback: `cp chezmoi.toml.pre-dots chezmoi.toml`, restore `*.pre-dots`, previous HM generation.

- [ ] **Step 3: Remove superseded system copies (owner confirms each)**

```bash
sudo apt remove taskwarrior kitty rofi                          # task 2.6.2, apt kitty, (rofi built from source: sudo rm /usr/local/bin/rofi)
rm -rf ~/.local/kitty.app ~/.local/bin/kitty ~/.config/oh-my-zsh
rm -f ~/.local/bin/{clipse,aw-server,awatcher,starship} ~/.local/opt/k9s-*
sudo rm -f /usr/bin/swww /usr/bin/swww-daemon
systemctl --user disable --now clip-prune.timer; rm -f ~/.config/systemd/user/clip-prune.*
```

- [ ] **Step 4: archdesk and laptop**

```bash
mkdir -p ~/.config/chezmoi && cp <age key> ~/.config/chezmoi/key.txt
sh -c "$(curl -fsLS get.chezmoi.io)" -- -b ~/.local/bin
~/.local/bin/chezmoi init --branch consolidate --apply snoorullah/dots
```

- [ ] **Step 5: Herdr trial and decision**

Run the 7-day protocol in `docs/herdr-trial.md`. Then remove the loser in one commit: delete its files under `home/dot_config/{tmux,herdr}`, its unit, its `.chezmoiignore` block, its package line in `nix/home.nix`, the `multiplexer` prompt in `.chezmoi.toml.tmpl`, and (if Herdr wins) `tools/pin-tmux-plugins.sh`, `nix/pkgs/tmux-plugins.json`, `dotsTmuxPluginFarm`, `.tmux.conf` and the `otter-tmux.sh` entry. Re-run all tests.

- [ ] **Step 6: Merge and archive**

Open PR `consolidate → main` on `snoorullah/dots`; merge after review. Archive `ubuntu-dots`, `hyprland-config`, `tmux-config` (both accounts) with a README line "Moved to github.com/snoorullah/dots".

---

## Execution notes

- Tasks 1–10 build on each other (data keys, PATH contract, package set); run in order. Task 11 needs push access. Task 3 Steps 1–2 and Task 12 need the owner (secrets, sudo, logout).
