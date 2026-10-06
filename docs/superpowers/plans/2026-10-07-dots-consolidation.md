# dots Consolidation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One Nix/home-manager repo (`dots`) reproduces the work PC's current desktop + shell setup identically on Arch, Ubuntu, Debian, Fedora/RHEL/Rocky and NixOS, absorbing `ubuntu-dots`, `hyprland-config` and `tmux-config`.

**Architecture:** A standalone home-manager flake owns everything under `$HOME` (configs, scripts as `writeShellApplication`, packages, user services, Hyprland itself), pinned by `flake.lock`. A thin per-distro `bootstrap/` script (or `nixosModules.base` on NixOS) does only the root-level parts: Nix, GPU driver, PAM, session file, display manager, keyd. Live files from the work PC are snapshotted verbatim first, then normalized under tests.

**Tech Stack:** Nix flakes (Determinate Nix ≥2.34), home-manager (nixos-unstable), nix-gl-host / nixGL, sops-nix (age), Hyprland (latest release, Lua config), bash, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-10-07-dots-consolidation-design.md`

## Global Constraints

- Precedence: work-PC live files (2026-10-07) > `tmux-config@archdesk` (2026-10-04, tmux only) > repos.
- Hyprland: **latest release** from nixpkgs-unstable (0.56.2 at time of writing), same build on every host via `flake.lock`.
- Every `~/.local/bin` script ships via `writeShellApplication` with explicit `runtimeInputs`.
- Managed files must not contain: `/home/linuxbrew`, `/home/devsupreme`, `/snap/`, `.cargo/bin`, `.nix-profile/bin`, `/run/user/1001`, `/usr/bin/{task,timew,python3,kubectl,tmux,gh,kitty,swww}`.
- Git identity everywhere: `Shaik Noorullah <snoorullah@proficientnow.com>`. Commit with that identity (the clone lives under `~/work/`, so `~/.gitconfig-work` applies).
- No secret material in git except sops-encrypted files. Never print secret contents in logs.
- `home.stateVersion = "25.11"`. System: `x86_64-linux`.
- Commit after each task; push branch `consolidate` to `origin` (`snoorullah/dots`). Never push to `main`.

## Review Focus

1. **Pre-existing plain files at managed paths** (every current machine has them) → `home-manager switch` must not abort; it must move them to `*.pre-dots` and continue. Test: Task 10 matrix pre-creates `~/.config/waybar/config.jsonc` and `~/.zshrc`.
2. **Scripts launched from Hyprland/waybar/systemd with a system-only PATH** (Hyprland's session PATH has no nix dirs) → must still work. Test: Task 4 `in-home.sh` runs every waybar script under `env -i PATH=/usr/bin:/bin` and validates JSON.
3. **Fresh machine with no user data** (`~/.task`, `~/.cache/adhd`, `salah.log`, `prayer-times.conf`, `~/walls` absent) → status scripts exit 0 and print sane output, not errors. Test: Task 4 `in-home.sh` runs on an empty `$HOME` in the matrix.
4. **Non-NVIDIA host receives NVIDIA env vars / GL wrapper** → black screen. Test: Task 6 flake check asserts `host.lua` for `archlaptop`/`generic` contains no `LIBVA_DRIVER_NAME`, and `workpc` does.
5. **Distro binaries shadowing pinned ones** (Ubuntu's `/usr/bin/task` is taskwarrior 2.6.2; the data is a 3.x DB) → scripts must use the pinned tool. Test: Task 4 `in-home.sh` puts a fake `task` that exits 99 first on PATH and asserts `adhd-focus.sh status` still succeeds.

---

## File Structure (end state)

```
flake.nix                      inputs + outputs (homeConfigurations.<host>, nixosConfigurations, checks, packages)
lib/default.nix                mkPkgs, mkHome, mkHomes, mkNixos
hosts/default.nix              host table: user, system, gpu, distro
hosts/nixos-laptop/            NixOS system config (existing laptop config, moved)
pkgs/overlay.nix               otter-launcher, adhanpy python env, tmux plugins
pkgs/otter-launcher.nix
pkgs/adhanpy.nix
home/default.nix               imports all modules; username/homeDirectory from host
home/modules/options.nix       dots.* options (host passthrough, timetrack.enable)
home/modules/files.nix         deploys home/files/** verbatim (mirror of $HOME)
home/modules/scripts.nix       home/scripts/* → writeShellApplication → ~/.local/bin
home/modules/packages.nix      every binary the setup calls
home/modules/gl.nix            GL wrapping per host.gpu
home/modules/hypr.nix          Hyprland pkg + session wrapper + generated host.lua + hypridle/polkit services
home/modules/shell.nix         zsh (oh-my-zsh from nix), starship, zoxide, fzf, nix-paths.zsh
home/modules/git.nix           identity, gh credential helper, includeIf work
home/modules/tmux.nix          tmux + pinned plugins + config/ subtree
home/modules/services.nix      systemd user units (adhd timers, aw, tmux, tunnels)
home/modules/adhd.nix          data dirs, walls clone, prayer-times venv replacement
home/modules/timetrack.nix     laptop-only timetrack units (dots.timetrack.enable, default false)
home/modules/secrets.nix       sops-nix: ~/.secrets, kubeconfigs
home/modules/fonts.nix, theme.nix, apps.nix, dev.nix, editors.nix
home/files/**                  verbatim live configs, path = path under $HOME
home/scripts/*                 live ~/.local/bin scripts (bodies only, no shebang PATH hacks)
home/modules/tmux/config/      git subtree of tmux-config@archdesk
secrets/*.yaml, .sops.yaml     sops-encrypted
bootstrap/{common,apt,pacman,dnf}.sh   system layer
tests/expected-targets.txt     mode + path under $HOME
tests/expected-commands.txt    commands that must be in home-path/bin
tests/checks.nix               flake checks: placement, deps, lint, host-gpu
tests/in-home.sh               runs inside a real switched $HOME (matrix + local)
tests/live-diff.sh             built vs live $HOME on the work PC
tests/allowed-diffs.txt
tools/snapshot-live.sh         copies live files listed in expected-targets into home/files|scripts
.github/workflows/matrix.yml
docs/install.md
```

Removed: `home.nix`, `home/laptop.nix`, `home/modules/desktop/files/**` (superseded by `home/files/**`), caelestia inputs, `docs/superpowers/{plans,specs}/2026-06-*caelestia*`, `hosts/archdesk/files/zsh/*` (after Task 7).

---

### Task 1: Flake skeleton, host table, and test harness

**Files:**
- Modify: `flake.nix` (replace)
- Create: `lib/default.nix`, `hosts/default.nix`, `home/default.nix`, `home/modules/options.nix`, `home/modules/files.nix`, `tests/checks.nix`, `tests/expected-targets.txt`, `tests/expected-commands.txt`
- Move: `hosts/laptop/` → `hosts/nixos-laptop/`

**Interfaces:**
- Produces: `homeConfigurations.<host>` for `workpc archdesk archlaptop generic`; `nixosConfigurations.nixos-laptop`; module arg `host = { name user system gpu distro home }`; option `dots.timetrack.enable`; checks `placement-<host>`, `deps-<host>`, `lint-<host>`.

- [ ] **Step 1: Write the host table**

`hosts/default.nix`:
```nix
# One entry per machine. gpu: "nvidia" | "mesa" | "nixos". user = null → $USER (needs --impure).
{
  workpc       = { user = "devsupreme"; system = "x86_64-linux"; gpu = "nvidia"; distro = "ubuntu"; };
  archdesk     = { user = "devsupreme"; system = "x86_64-linux"; gpu = "nvidia"; distro = "arch";   }; # verify on box: Task 12 step 1
  archlaptop   = { user = "devsupreme"; system = "x86_64-linux"; gpu = "mesa";   distro = "arch";   }; # verify on box: Task 12 step 1
  generic      = { user = null;         system = "x86_64-linux"; gpu = "mesa";   distro = "any";    };
  nixos-laptop = { user = "devsupreme"; system = "x86_64-linux"; gpu = "nixos";  distro = "nixos";  };
}
```

- [ ] **Step 2: Write `lib/default.nix`**

```nix
{ inputs }:
let
  inherit (inputs) nixpkgs home-manager;
  lib = nixpkgs.lib;
in rec {
  mkPkgs = system: import nixpkgs {
    inherit system;
    config.allowUnfree = true;
    overlays = [ (import ../pkgs/overlay.nix) ];
  };

  resolveHost = name: h:
    let user = if h.user != null then h.user else builtins.getEnv "USER";
        home = if h.user != null then "/home/${h.user}" else builtins.getEnv "HOME";
    in h // { inherit name user home; };

  mkHome = name: h:
    let host = resolveHost name h; in
    home-manager.lib.homeManagerConfiguration {
      pkgs = mkPkgs host.system;
      extraSpecialArgs = { inherit inputs host; };
      modules = [ ../home inputs.sops-nix.homeManagerModules.sops ];
    };

  mkHomes = hosts: lib.mapAttrs mkHome (lib.filterAttrs (_: h: h.distro != "nixos") hosts);

  mkNixos = name: h:
    let host = resolveHost name h; in
    nixpkgs.lib.nixosSystem {
      system = host.system;
      specialArgs = { inherit inputs host; };
      modules = [
        ../hosts/${name}/configuration.nix
        home-manager.nixosModules.home-manager
        {
          nixpkgs.overlays = [ (import ../pkgs/overlay.nix) ];
          home-manager = {
            useGlobalPkgs = true;
            useUserPackages = true;
            extraSpecialArgs = { inherit inputs host; };
            sharedModules = [ inputs.sops-nix.homeManagerModules.sops ];
            users.${host.user} = import ../home;
          };
        }
      ];
    };
}
```

- [ ] **Step 3: Replace `flake.nix`**

```nix
{
  description = "dots — one user setup on every Linux";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = { url = "github:nix-community/home-manager"; inputs.nixpkgs.follows = "nixpkgs"; };
    nix-gl-host  = { url = "github:numtide/nix-gl-host";        inputs.nixpkgs.follows = "nixpkgs"; };
    nixgl        = { url = "github:nix-community/nixGL";        inputs.nixpkgs.follows = "nixpkgs"; };
    sops-nix     = { url = "github:Mic92/sops-nix";             inputs.nixpkgs.follows = "nixpkgs"; };
    zen-browser  = { url = "github:0xc000022070/zen-browser-flake"; inputs.nixpkgs.follows = "nixpkgs"; };
  };

  outputs = inputs@{ self, nixpkgs, ... }:
    let
      dots  = import ./lib { inherit inputs; };
      hosts = import ./hosts;
      pkgs  = dots.mkPkgs "x86_64-linux";
    in {
      homeConfigurations = dots.mkHomes hosts;
      nixosConfigurations.nixos-laptop = dots.mkNixos "nixos-laptop" hosts.nixos-laptop;
      packages.x86_64-linux = { inherit (pkgs) otter-launcher; };
      checks.x86_64-linux = import ./tests/checks.nix { inherit self pkgs; lib = nixpkgs.lib; };
    };
}
```
`pkgs/overlay.nix` starts as `final: prev: { }` (filled in Task 5) so evaluation works now:
```nix
final: prev: { }
```

- [ ] **Step 4: Write `home/default.nix`, `options.nix`, `files.nix`**

`home/default.nix`:
```nix
{ host, lib, ... }: {
  imports = [ ./modules/options.nix ./modules/files.nix ];
  home.username = host.user;
  home.homeDirectory = host.home;
  home.stateVersion = "25.11";
  programs.home-manager.enable = true;
  targets.genericLinux.enable = host.distro != "nixos";
  xdg.enable = true;
}
```
`home/modules/options.nix`:
```nix
{ lib, ... }: {
  options.dots.timetrack.enable = lib.mkEnableOption "laptop timetrack CLI + logind/rollup/sync units";
}
```
`home/modules/files.nix` — deploys `home/files/**` verbatim; the path under `home/files/` is the path under `$HOME`:
```nix
{ lib, ... }:
let
  root = ../files;
  rel  = p: lib.removePrefix "${toString root}/" (toString p);
  all  = if builtins.pathExists root then lib.filesystem.listFilesRecursive root else [ ];
in {
  home.file = lib.listToAttrs (map (p: lib.nameValuePair (rel p) { source = p; }) all);
}
```

- [ ] **Step 5: Write the target and command lists (the spec of "what must exist")**

`tests/expected-targets.txt` (mode `f` = file, `x` = executable). Full list from the 2026-10-07 live inventory:
```
f .config/hypr/hyprland.lua
f .config/hypr/hypridle.conf
f .config/hypr/hyprlock.conf
f .config/hypr/host.lua
f .config/waybar/config.jsonc
f .config/waybar/style.css
f .config/kitty/kitty.conf
f .config/kitty/current-theme.conf
f .config/kitty/otter.conf
f .config/kitty/tasktui.conf
f .config/kitty/bluetuith.conf
f .config/kitty/images/bluetuith-bg.png
f .config/otter-launcher/config.toml
f .config/otter-launcher/git-profiles.conf
f .config/otter-launcher/images/otter-bg.png
f .config/otter-launcher/images/otter-full.png
f .config/otter-launcher/images/otter.png
x .config/otter-launcher/scripts/_otter-fzf.sh
x .config/otter-launcher/scripts/otter-app.sh
x .config/otter-launcher/scripts/otter-banner.sh
x .config/otter-launcher/scripts/otter-bookmarks.sh
x .config/otter-launcher/scripts/otter-files.sh
x .config/otter-launcher/scripts/otter-git.sh
x .config/otter-launcher/scripts/otter-header.sh
x .config/otter-launcher/scripts/otter-media.sh
x .config/otter-launcher/scripts/otter-obsidian.sh
x .config/otter-launcher/scripts/otter-power.sh
x .config/otter-launcher/scripts/otter-projects.sh
x .config/otter-launcher/scripts/otter-run.sh
x .config/otter-launcher/scripts/otter-stats.sh
x .config/otter-launcher/scripts/otter-systemd.sh
x .config/otter-launcher/scripts/otter-tabs.sh
x .config/otter-launcher/scripts/otter-tmux.sh
x .config/otter-launcher/scripts/otter-win.sh
x .config/otter-launcher/scripts/otter-ytm.sh
f .config/otter-launcher/scripts/zen-utils.sh
f .config/yazi/theme.toml
f .config/yazi/Dracula.tmTheme
f .config/clipse/config.json
f .config/clipse/custom_theme.json
f .config/mako/config
f .config/swayosd/style.css
f .config/starship.toml
x .config/starship/scripts/pipeline.sh
f .config/gtk-3.0/settings.ini
f .config/gtk-3.0/gtk.css
f .config/gtk-4.0/settings.ini
f .config/gtk-4.0/gtk.css
f .config/qtengine/config.json
f .config/qtengine/caelestia.colors
f .config/nvim/init.lua
f .config/adhd/iqamah.conf
f .config/timewarrior/timewarrior.cfg
f .config/onprem-kube-tunnel.conf
f .taskrc
x .task/hooks/on-modify.timewarrior
f .tmux.conf
f .config/tmux/tmux.conf
f .zshrc
f .zshenv
f .config/zsh/nix-paths.zsh
f .config/git/config
x .local/bin/adhd-block-pick.sh
x .local/bin/adhd-break.sh
x .local/bin/adhd-break-end.sh
x .local/bin/adhd-capture.sh
x .local/bin/adhd-focus.sh
x .local/bin/adhd-salah-pick.sh
x .local/bin/adhd-prayer-times.sh
x .local/bin/adhd-salah-schedule.sh
x .local/bin/adhd-salah-nudge.sh
x .local/bin/keybind-help.sh
x .local/bin/screenshot.sh
x .local/bin/yazi-launch.sh
x .local/bin/tw-tui
x .local/bin/wallpaper
x .local/bin/waybar-ctx.sh
x .local/bin/waybar-kube.sh
x .local/bin/waybar-project.sh
x .local/bin/waybar-salah.sh
x .local/bin/waybar-tracking.sh
x .local/bin/ctx
x .local/bin/kube-tunnel.sh
f .config/systemd/user/adhd-prayer-times.timer
f .config/systemd/user/adhd-salah-schedule.timer
f .config/systemd/user/aw-server.service
f .config/systemd/user/awatcher.service
f .config/systemd/user/tmux.service
f .config/systemd/user/onprem-kube-tunnel.service
f .config/systemd/user/ovh-k8s-tunnel.service
f .config/systemd/user/signoz-tunnel.service
f .config/systemd/user/hyprpolkitagent.service
```
`tests/expected-commands.txt` (must exist in the HM profile `home-path/bin`):
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
kitty
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
rofi
python3
git
zen
code
obsidian
```

- [ ] **Step 6: Write `tests/checks.nix`**

```nix
{ self, pkgs, lib }:
let
  hostsToCheck = [ "workpc" "archdesk" "archlaptop" ];  # generic needs --impure; covered by the matrix
  act = h: self.homeConfigurations.${h}.activationPackage;
  forbidden = "/home/linuxbrew|/home/devsupreme|/snap/|\\.cargo/bin|\\.nix-profile/bin|/run/user/1001|/usr/bin/(task|timew|python3|kubectl|tmux|gh|kitty|swww)\\b";
  perHost = h: {
    "placement-${h}" = pkgs.runCommand "placement-${h}" { } ''
      fail=0
      while read -r mode path; do
        case "$mode" in ""|\#*) continue ;; esac
        f="${act h}/home-files/$path"
        if [ ! -e "$f" ]; then echo "MISSING $path"; fail=1; continue; fi
        if [ "$mode" = x ] && [ ! -x "$f" ]; then echo "NOT-EXEC $path"; fail=1; fi
      done < ${../tests/expected-targets.txt}
      [ $fail = 0 ] && touch $out
    '';
    "deps-${h}" = pkgs.runCommand "deps-${h}" { } ''
      fail=0
      while read -r c; do
        [ -z "$c" ] && continue
        [ -x "${act h}/home-path/bin/$c" ] || { echo "NO-CMD $c"; fail=1; }
      done < ${../tests/expected-commands.txt}
      [ $fail = 0 ] && touch $out
    '';
    "lint-${h}" = pkgs.runCommand "lint-${h}" { } ''
      if ${pkgs.gnugrep}/bin/grep -rIlE '${forbidden}' -R ${act h}/home-files/; then
        echo "portability lint: the files above contain host-specific paths"; exit 1
      fi
      touch $out
    '';
  };
in lib.foldl' (a: h: a // perHost h) { } hostsToCheck
```

- [ ] **Step 7: Move the NixOS host and run checks (expect failure)**

```bash
git mv hosts/laptop hosts/nixos-laptop
nix flake lock
nix flake check 2>&1 | tail -20
```
Expected: evaluation succeeds; `placement-workpc` FAILS with many `MISSING …` lines and `deps-workpc` FAILS with `NO-CMD …` (nothing is deployed yet). If evaluation itself fails, fix that before continuing.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "feat(flake): host table, mkHome/mkNixos, placement/deps/lint checks (red)"
```

---

### Task 2: Import tmux-config@archdesk with history

**Files:**
- Create: `home/modules/tmux/config/` (git subtree), `home/modules/tmux.nix`, `tools/pin-tmux-plugins.sh`, `pkgs/tmux-plugins.json`
- Modify: `pkgs/overlay.nix` (tmux plugins), `home/default.nix` (import)

**Interfaces:**
- Consumes: `home/files` mechanism (Task 1).
- Produces: `~/.config/tmux` = the subtree; `programs.tmux` disabled (config is file-based); `pkgs.dotsTmuxPlugins` attrset.

- [ ] **Step 1: Add the subtree from the archdesk branch**

```bash
git remote add tmux-upstream https://github.com/shaiknoorullah/tmux-config.git
git fetch tmux-upstream archdesk
git subtree add --prefix=home/modules/tmux/config tmux-upstream archdesk -m "chore(tmux): import tmux-config@archdesk with history"
git log --oneline -3 -- home/modules/tmux/config
```
Expected: last commits include `fix(archdesk): restore Claude panes with their original flags`.

- [ ] **Step 2: Generate the plugin pin file**

`tmux.conf@archdesk` declares 15 `@plugin`s; `plugins.lock` pins 6 of them:
```
tmux-continuum 0698e8f4b17d6454c71bf5212895ec055c578da0
tmux-prefix-highlight 06cbb4ecd3a0a918ce355c70dc56d79debd455c7
tmux-resurrect cff343cf9e81983d3da0c8562b01616f12e8d548
tmux-sensible 25cb91f42d020f675bb0a2ce3fbd3a5d96119efa
tmux-yank acfd36e4fcba99f8310a7dfb432111c242fe7392
tpm 99469c4a9b1ccf77fade25842dc7bafbc8ce9946
```
The other 9 (tmux-sessionx, tmux-project, tmux-fzf, extrakto, tmux-thumbs, tmux-command-palette, tmux-task-monitor, tmux-notify, tmux-browser) are pinned to the commit checked out on the work PC. `tools/pin-tmux-plugins.sh`:
```bash
#!/usr/bin/env bash
# Writes pkgs/tmux-plugins.json: [{dir, owner, repo, rev, hash}] for every @plugin in tmux.conf.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
cfg=home/modules/tmux/config
live="$HOME/tmux-config/plugins"
echo '[' > pkgs/tmux-plugins.json; first=1
grep -oE "@plugin '[^']+'" "$cfg/tmux.conf" | sed -E "s/@plugin '([^']+)'/\1/" | while read -r slug; do
  owner=${slug%/*}; repo=${slug#*/}
  rev=$(awk -v r="$repo" '$1==r{print $2}' "$cfg/plugins.lock")
  [ -n "$rev" ] || rev=$(git -C "$live/$repo" rev-parse HEAD)
  hash=$(nix run nixpkgs#nix-prefetch-github -- --rev "$rev" "$owner" "$repo" | nix run nixpkgs#jq -- -r .hash)
  [ $first = 1 ] || echo ',' >> pkgs/tmux-plugins.json; first=0
  printf '{"dir":"%s","owner":"%s","repo":"%s","rev":"%s","hash":"%s"}' "$repo" "$owner" "$repo" "$rev" "$hash" >> pkgs/tmux-plugins.json
done
echo ']' >> pkgs/tmux-plugins.json
nix run nixpkgs#jq -- length pkgs/tmux-plugins.json
```
```bash
bash tools/pin-tmux-plugins.sh
```
Expected: prints `15`.

- [ ] **Step 3: Package plugins in `pkgs/overlay.nix`**

Replace `final: prev: { }` with:
```nix
final: prev: {
  # [{ dir; pkg }] — dir is the folder name tmux-config expects under ~/.config/tmux/plugins/
  dotsTmuxPlugins = map (p: {
    inherit (p) dir;
    pkg = prev.fetchFromGitHub { inherit (p) owner repo rev hash; };
  }) (builtins.fromJSON (builtins.readFile ./tmux-plugins.json));
}
```
(Plugins are plain source trees; tmux-config sources them by path, so no `mkTmuxPlugin` build is needed.)

- [ ] **Step 4: Write `home/modules/tmux.nix`**

TPM stays for its keybinds but never fetches: every plugin is pre-linked into `~/.config/tmux/plugins/<dir>`, exactly where tmux-config expects it.
```nix
{ pkgs, lib, ... }: {
  home.packages = [ pkgs.tmux pkgs.eza pkgs.wl-clipboard pkgs.fzf pkgs.gitMinimal ];
  xdg.configFile = {
    "tmux" = { source = ./tmux/config; recursive = true; };
  } // lib.listToAttrs (map (p: lib.nameValuePair "tmux/plugins/${p.dir}" { source = p.pkg; }) pkgs.dotsTmuxPlugins);
}
```
Add `./modules/tmux.nix` to `home/default.nix` imports.

- [ ] **Step 5: Run placement for tmux paths**

```bash
nix build .#checks.x86_64-linux.placement-workpc 2>&1 | grep -E 'tmux' || echo "tmux targets present"
```
Expected: no `MISSING .config/tmux/tmux.conf` line.

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat(tmux): pinned plugins from plugins.lock; deploy tmux-config@archdesk"
```

---

### Task 3: Snapshot live configs verbatim

**Files:**
- Create: `tools/snapshot-live.sh`, `home/files/**`, `home/scripts/*`, `reference/systemd-user/*`

**Interfaces:**
- Consumes: `tests/expected-targets.txt`.
- Produces: `home/files/<path>` for every `.config`/dotfile target; `home/scripts/<name>` for every `.local/bin` target; originals of systemd units in `reference/systemd-user/` (ported to Nix in Task 8). Generated targets (`.config/hypr/host.lua`, `.config/zsh/nix-paths.zsh`, `.config/git/config`, `.config/tmux/*`, systemd units) are skipped here.

- [ ] **Step 1: Write `tools/snapshot-live.sh`**

```bash
#!/usr/bin/env bash
# Copy the live files listed in tests/expected-targets.txt into the repo, verbatim.
# .local/bin/* -> home/scripts/, systemd units -> reference/systemd-user/, rest -> home/files/.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
skip='^(\.config/hypr/host\.lua|\.config/zsh/nix-paths\.zsh|\.config/git/config|\.config/tmux/.*)$'
missing=0
while read -r mode path; do
  case "$mode" in ""|\#*) continue ;; esac
  [[ "$path" =~ $skip ]] && continue
  src="$HOME/$path"
  [[ -e "$src" ]] || { echo "LIVE-MISSING $path"; missing=1; continue; }
  case "$path" in
    .local/bin/*)            dst="home/scripts/${path#.local/bin/}" ;;
    .config/systemd/user/*)  dst="reference/systemd-user/${path##*/}"; cp "${src%.timer}.service" "reference/systemd-user/" 2>/dev/null || true ;;
    *)                       dst="home/files/$path" ;;
  esac
  mkdir -p "$(dirname "$dst")"
  cp -L --preserve=mode "$src" "$dst"
done < tests/expected-targets.txt
# whole trees that the target list samples one file from
for d in .config/nvim .config/gtk-3.0 .config/gtk-4.0; do
  rsync -a --exclude '*.bak' --exclude 'lazy-lock.json.bak' "$HOME/$d/" "home/files/$d/"
done
exit $missing
```

- [ ] **Step 2: Run it on the work PC**

```bash
mkdir -p reference/systemd-user && bash tools/snapshot-live.sh; echo "exit=$?"
git status --short | wc -l
```
Expected: `exit=0`. If `LIVE-MISSING .config/systemd/user/hyprpolkitagent.service` appears, that is correct (it does not exist live; Task 6 creates it): remove that line from the check by re-running after Task 6, and continue.

- [ ] **Step 3: Remove what must not be committed**

```bash
grep -rIlE 'BEGIN (OPENSSH|RSA|EC) PRIVATE KEY|AGE-SECRET-KEY|ghp_[A-Za-z0-9]{20}|xox[bp]-' home reference || echo "no secrets"
rm -f home/files/.config/nvim/plugin/wtfrc-coach.lua   # unrelated local coach hook
```
Expected: `no secrets`. `.zshrc` sources `~/.secrets` but does not contain it.

- [ ] **Step 4: Fix the known dangling references in the snapshot**

In `home/files/.task/hooks/on-modify.timewarrior` delete the line that calls `adhd-tasks-export.sh` (script removed 2026-10-06). In `home/files/.config/otter-launcher/config.toml` delete the module whose `cmd` is `~/.local/bin/timetrack-datasette` (binary absent).
```bash
grep -n 'adhd-tasks-export' home/files/.task/hooks/on-modify.timewarrior
grep -n 'timetrack-datasette' home/files/.config/otter-launcher/config.toml
```
Expected after edits: no output.

- [ ] **Step 5: Run placement (expect only generated targets missing)**

```bash
nix build .#checks.x86_64-linux.placement-workpc 2>&1 | grep -E 'MISSING|NOT-EXEC'
```
Expected: only `.config/hypr/host.lua`, `.config/zsh/nix-paths.zsh`, `.config/git/config`, `.local/bin/*` and `.config/systemd/user/*` remain MISSING (Tasks 4–8 create them). `lint-workpc` FAILS (snapshot still has `/home/devsupreme` etc.) — that is the expected red for Task 4.

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat(files): snapshot live work-PC configs verbatim (2026-10-07)"
```

---

### Task 4: Scripts become self-contained (`writeShellApplication`)

**Files:**
- Create: `home/modules/scripts.nix`, `tests/in-home.sh`
- Modify: every file in `home/scripts/`, otter scripts under `home/files/.config/otter-launcher/scripts/`, `home/files/.config/waybar/config.jsonc`, `home/files/.config/otter-launcher/config.toml`, `home/files/.config/yazi/theme.toml`, `home/files/.config/mako/config`, `home/files/.config/starship/scripts/pipeline.sh`

**Interfaces:**
- Consumes: `home/scripts/*` (Task 3).
- Produces: `~/.local/bin/<name>` for every script, each a store wrapper whose PATH = its `runtimeInputs` + `~/.local/bin` (so scripts can call each other).

- [ ] **Step 1: Write `tests/in-home.sh` (the failing behavioural test)**

```bash
#!/usr/bin/env bash
# Runs against a real switched $HOME. Proves scripts work with a system-only PATH,
# on an empty home, and with a hostile `task` earlier on PATH (Review Focus 2,3,5).
set -uo pipefail
fail=0; B="$HOME/.local/bin"
JQ="$(nix build --no-link --print-out-paths nixpkgs#jq)/bin/jq"
fake="$(mktemp -d)"; printf '#!/bin/sh\nexit 99\n' > "$fake/task"; chmod +x "$fake/task"
run() { env -i HOME="$HOME" USER="$USER" XDG_RUNTIME_DIR="/tmp" PATH="$fake:/usr/bin:/bin" "$@"; }
for s in waybar-salah.sh waybar-ctx.sh waybar-tracking.sh waybar-project.sh waybar-kube.sh; do
  out="$(run "$B/$s" 2>/dev/null)"
  printf '%s' "$out" | "$JQ" -e '.text != null' >/dev/null || { echo "FAIL $s -> '$out'"; fail=1; }
done
run "$B/adhd-focus.sh" status >/dev/null || { echo "FAIL adhd-focus.sh status"; fail=1; }
for f in .config/hypr/hyprland.lua .config/waybar/config.jsonc .taskrc; do
  [ -e "$HOME/$f" ] || { echo "FAIL missing $f"; fail=1; }
done
exit $fail
```

- [ ] **Step 2: Write `home/modules/scripts.nix`**

```nix
{ config, pkgs, lib, ... }:
let
  common = with pkgs; [ coreutils gnugrep gnused gawk findutils procps util-linux libnotify jq python3 ];
  deps = with pkgs; {
    "adhd-block-pick.sh"   = [ taskwarrior3 fzf ];
    "adhd-break.sh"        = [ taskwarrior3 timewarrior systemd hyprland ];
    "adhd-break-end.sh"    = [ taskwarrior3 timewarrior hyprland ];
    "adhd-capture.sh"      = [ taskwarrior3 rofi curl ];
    "adhd-focus.sh"        = [ taskwarrior3 timewarrior ];
    "adhd-salah-pick.sh"   = [ fzf ];
    "adhd-prayer-times.sh" = [ dotsAdhanPython ];
    "adhd-salah-schedule.sh" = [ systemd ];
    "adhd-salah-nudge.sh"  = [ ];
    "keybind-help.sh"      = [ fzf less ];
    "screenshot.sh"        = [ grim slurp wl-clipboard hyprland ];
    "yazi-launch.sh"       = [ yazi ];
    "tw-tui"               = [ taskwarrior3 taskwarrior-tui ];
    "wallpaper"            = [ fzf kitty swww ];
    "waybar-ctx.sh"        = [ taskwarrior3 procps ];
    "waybar-kube.sh"       = [ kubectl ];
    "waybar-project.sh"    = [ hyprland tmux git ];
    "waybar-salah.sh"      = [ ];
    "waybar-tracking.sh"   = [ timewarrior ];
    "ctx"                  = [ taskwarrior3 fzf ];
    "kube-tunnel.sh"       = [ kubectl openssh ];
  };
  mk = name: inputs: pkgs.writeShellApplication {
    inherit name;
    runtimeInputs = common ++ inputs;
    # $HOME at runtime (not baked) so scripts find their siblings in any home, incl. test homes
    text = ''export PATH="$HOME/.local/bin:$PATH"
'' + builtins.readFile ../scripts/${name};
    checkPhase = "";            # live scripts predate shellcheck; keep behaviour, skip lint
    bashOptions = [ ];          # scripts set their own `set` flags
  };
in {
  home.file = lib.mapAttrs' (n: i: lib.nameValuePair ".local/bin/${n}" {
    source = "${mk n i}/bin/${n}";
  }) deps;
}
```
Add `./modules/scripts.nix` to `home/default.nix` imports. (`dotsAdhanPython` arrives in Task 5; until then use `[ python3 ]` for `adhd-prayer-times.sh` and switch it in Task 5 Step 3.)

- [ ] **Step 3: Strip host paths from script bodies**

For each file in `home/scripts/` and `home/files/.config/otter-launcher/scripts/` apply these rewrites (the wrapper now provides the tools on PATH):
```bash
cd home
sed -i -E \
  -e 's#/home/linuxbrew/\.linuxbrew/bin/(task|python3|pactl)#\1#g' \
  -e 's#"?\$\{TASK_BIN:-[^}]*\}"?#task#g' \
  -e 's#/usr/bin/(timew|python3|task|kubectl|tmux|kitty|swww)\b#\1#g' \
  -e 's#(\$HOME|~)/\.cargo/bin/##g' \
  -e 's#(\$HOME|~)/\.fzf/bin:?##g' \
  -e 's#/run/user/1001#${XDG_RUNTIME_DIR}#g' \
  -e '/^export PATH=.*(linuxbrew|\.fzf|\.cargo|\.local\/bin).*$/d' \
  scripts/* files/.config/otter-launcher/scripts/*.sh files/.config/starship/scripts/pipeline.sh
sed -i -E 's#^\#!.*$##' scripts/*        # wrapper supplies the shebang
cd ..
grep -rnE '/home/linuxbrew|/usr/bin/(task|timew|python3)|\.cargo/bin|/run/user/1001' home/scripts home/files/.config/otter-launcher/scripts || echo clean
```
Expected: `clean`. Review the diff (`git diff --stat`, then `git diff home/scripts/adhd-focus.sh`) to confirm only paths changed.

- [ ] **Step 4: Replace `/home/devsupreme` in config files with runtime-resolved forms**

- `home/files/.config/waybar/config.jsonc`: replace `/home/devsupreme/.local/bin/` with `~/.local/bin/` (waybar expands `~` in `exec`), and the absolute `k9s` path with `k9s`.
- `home/files/.config/otter-launcher/config.toml`: replace `/home/devsupreme/` with `~/` (otter-launcher runs `cmd` through `sh -c`).
- `home/files/.config/yazi/theme.toml:32`: replace `/home/devsupreme/.config/yazi/Dracula.tmTheme` with `~/.config/yazi/Dracula.tmTheme`.
- `home/files/.config/mako/config:24`: delete the `icon-path=/home/devsupreme/.nix-profile/share/icons/Papirus*` line. Task 9 regenerates it from Nix as `${pkgs.papirus-icon-theme}/share/icons/Papirus-Dark`.
```bash
grep -rnE '/home/devsupreme' home/files --include='*.jsonc' --include='*.toml' --include=config || echo clean
```
Expected: `clean` (hyprland.lua is handled in Task 6, .zshrc in Task 7).

- [ ] **Step 5: Build and run behavioural test locally in a throwaway HOME**

Never run `activate` here: the workpc activation package targets the real `/home/devsupreme`. Copy the built files into a temp home instead:
```bash
nix build .#homeConfigurations.workpc.activationPackage -o /tmp/dots-act
export TESTHOME=$(mktemp -d)
cp -rL /tmp/dots-act/home-files/. "$TESTHOME/"
HOME=$TESTHOME USER=devsupreme bash tests/in-home.sh; echo "in-home exit=$?"
```
Expected: `in-home exit=0`. Typical failures and fixes: a waybar script prints an error on an empty home → add a guard in `home/scripts/<name>` (e.g. `[ -f "$f" ] || { printf '{"text":""}\n'; exit 0; }`); a script calls a tool not in its `runtimeInputs` → add it in `scripts.nix`.

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat(scripts): writeShellApplication wrappers; drop linuxbrew/usr/bin/cargo paths"
```

---

### Task 5: Packages — every binary from Nix

**Files:**
- Create: `pkgs/otter-launcher.nix`, `pkgs/adhanpy.nix`, `home/modules/packages.nix`
- Modify: `pkgs/overlay.nix`, `home/modules/scripts.nix` (adhan), `home/modules/apps.nix`, `home/modules/dev.nix`, `home/modules/editors.nix`

**Interfaces:**
- Produces: `pkgs.otter-launcher`, `pkgs.dotsAdhanPython` (python3 with `adhanpy`), all commands in `tests/expected-commands.txt`.

- [ ] **Step 1: Package otter-launcher (crates.io 0.7.5, the live version)**

`pkgs/otter-launcher.nix`:
```nix
{ lib, rustPlatform, fetchCrate }:
rustPlatform.buildRustPackage rec {
  pname = "otter-launcher";
  version = "0.7.5";
  src = fetchCrate { inherit pname version; hash = lib.fakeHash; };
  cargoHash = lib.fakeHash;
  meta.mainProgram = "otter-launcher";
}
```
```bash
nix build .#otter-launcher 2>&1 | grep -E 'got:' | head -2   # paste first hash into src.hash, rebuild, paste cargoHash
nix build .#otter-launcher && ./result/bin/otter-launcher --version
```
Expected: prints `0.7.5`.

- [ ] **Step 2: Package adhanpy**

`pkgs/adhanpy.nix`:
```nix
{ python3Packages, fetchPypi, lib }:
python3Packages.buildPythonPackage rec {
  pname = "adhanpy";
  version = "1.0.5";            # match: ~/.local/share/adhd/venv/bin/pip show adhanpy | grep Version
  pyproject = true;
  src = fetchPypi { inherit pname version; hash = lib.fakeHash; };
  build-system = [ python3Packages.setuptools ];
  pythonImportsCheck = [ "adhanpy" ];
}
```
Before building, set `version` to the live value:
```bash
~/.local/share/adhd/venv/bin/pip show adhanpy | grep Version
```

`pkgs/overlay.nix` — add next to `dotsTmuxPlugins`:
```nix
  otter-launcher = final.callPackage ./otter-launcher.nix { };
  dotsAdhanPython = final.python3.withPackages (ps: [ (final.callPackage ./adhanpy.nix { python3Packages = ps; }) ]);
```

- [ ] **Step 3: Point `adhd-prayer-times.sh` at the Nix python**

In `home/scripts/adhd-prayer-times.sh` delete the venv bootstrap block (`VDIR=…`, `if [ ! -x "$VDIR/bin/python" ] … fi`) and replace `"$VDIR/bin/python" -` with `python3 -`. In `scripts.nix` set `"adhd-prayer-times.sh" = [ dotsAdhanPython ];`.
```bash
nix build .#homeConfigurations.workpc.activationPackage -o /tmp/dots-act
HOME=$(mktemp -d) /tmp/dots-act/home-files/.local/bin/adhd-prayer-times.sh && echo ok
```
Expected: `wrote …/.config/adhd/prayer-times.conf` then `ok`.

- [ ] **Step 4: Write `home/modules/packages.nix`**

```nix
{ pkgs, inputs, host, ... }: {
  home.packages = with pkgs; [
    # desktop
    waybar mako swayosd swww kitty otter-launcher clipse yazi ffmpegthumbnailer unar file fd
    grim slurp wl-clipboard playerctl brightnessctl networkmanagerapplet bluetuith libnotify
    hyprpicker rofi papirus-icon-theme
    # tasks / time
    taskwarrior3 timewarrior taskwarrior-tui aw-server-rust awatcher
    # shell + cli
    zsh starship zoxide fzf eza bat ripgrep jq gh neovim git fastfetch
    # k8s
    kubectl k9s
    # apps (live: zen, code, obsidian, slack, thunderbird)
    inputs.zen-browser.packages.${host.system}.default
    vscode obsidian slack thunderbird
  ];
}
```
Remove from `apps.nix`/`dev.nix`/`editors.nix` any package now listed here (avoid duplicates); keep their other contents. Add `./modules/packages.nix ./modules/apps.nix ./modules/dev.nix ./modules/editors.nix` to imports.

- [ ] **Step 5: Run deps check**

```bash
nix build .#checks.x86_64-linux.deps-workpc 2>&1 | grep NO-CMD || echo "deps green"
```
Expected: only `NO-CMD Hyprland`, `NO-CMD hyprctl`, `NO-CMD hypridle` remain (Task 6). Fix any other `NO-CMD` by adding the package that provides it (`nix-locate bin/<cmd>` if unsure).

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat(pkgs): otter-launcher + adhanpy derivations; all desktop/cli binaries from nix"
```

---

### Task 6: Hyprland — latest release, GL wrapping, host.lua, 0.56 port

**Files:**
- Create: `home/modules/gl.nix`, `home/modules/hypr.nix`
- Modify: `home/files/.config/hypr/hyprland.lua`, `home/files/.config/hypr/hypridle.conf`, `tests/checks.nix` (gpu check)

**Interfaces:**
- Consumes: `host.gpu`, `pkgs.hyprland` (nixpkgs-unstable latest).
- Produces: `glWrap :: drv -> drv` via `config.lib.dots.glWrap`; `~/.config/hypr/host.lua` defining a Lua table `HOST = { home=…, path=…, data_dirs=…, env={…} }`; `~/.local/bin/start-hyprland-dots` session launcher; user units `hyprpolkitagent.service`, `hypridle.service`.

- [ ] **Step 1: Write the failing gpu check (Review Focus 4)**

Append to `perHost` in `tests/checks.nix`:
```nix
    "gpu-env-${h}" = pkgs.runCommand "gpu-env-${h}" { } ''
      f=${act h}/home-files/.config/hypr/host.lua
      if [ "${h}" = workpc ] || [ "${h}" = archdesk ]; then
        grep -q LIBVA_DRIVER_NAME "$f" || { echo "nvidia host lacks nvidia env"; exit 1; }
      else
        ! grep -q LIBVA_DRIVER_NAME "$f" || { echo "non-nvidia host has nvidia env"; exit 1; }
      fi
      touch $out
    '';
```
```bash
nix build .#checks.x86_64-linux.gpu-env-archlaptop 2>&1 | tail -2
```
Expected: FAIL (host.lua does not exist yet).

- [ ] **Step 2: Write `home/modules/gl.nix`**

```nix
{ config, pkgs, lib, inputs, host, ... }:
let
  nvidia = pkgs: drv: pkgs.symlinkJoin {
    name = "${drv.name}-nixglhost"; paths = [ drv ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      for b in $out/bin/*; do
        t=$(readlink -f "$b"); rm "$b"
        makeWrapper ${inputs.nix-gl-host.packages.${host.system}.default}/bin/nixglhost "$b" --add-flags "$t"
      done'';
  };
in {
  targets.genericLinux.nixGL = lib.mkIf (host.gpu == "mesa") {
    packages = inputs.nixgl.packages;
    defaultWrapper = "mesa";
  };
  lib.dots.glWrap =
    if host.gpu == "nvidia" then nvidia pkgs
    else if host.gpu == "mesa" then config.lib.nixGL.wrap
    else (drv: drv);
}
```

- [ ] **Step 3: Write `home/modules/hypr.nix`**

```nix
{ config, pkgs, lib, host, ... }:
let
  wrap = config.lib.dots.glWrap;
  hypr = wrap pkgs.hyprland;
  profileBin = "${config.home.profileDirectory}/bin";
  nvidiaEnv = lib.optionalString (host.gpu == "nvidia") ''
    LIBVA_DRIVER_NAME = "nvidia",
    __GLX_VENDOR_LIBRARY_NAME = "nvidia",
    NVD_BACKEND = "direct",'';
in {
  home.packages = [ hypr (wrap pkgs.kitty) pkgs.hypridle pkgs.hyprpolkitagent pkgs.xdg-desktop-portal-hyprland ];

  xdg.configFile."hypr/host.lua".text = ''
    -- generated by dots (home/modules/hypr.nix) for host "${host.name}" — do not edit
    HOST = {
      home = "${config.home.homeDirectory}",
      path = "${config.home.homeDirectory}/.local/bin:${profileBin}:/usr/local/bin:/usr/bin:/bin",
      data_dirs = "${config.home.profileDirectory}/share:/usr/local/share:/usr/share",
      env = {
        ${nvidiaEnv}
        ELECTRON_OZONE_PLATFORM_HINT = "auto",
        KUBECONFIG = "${config.home.homeDirectory}/.kube/onprem-s2a.yaml",
      },
    }
  '';

  home.file.".local/bin/start-hyprland-dots" = {
    executable = true;
    text = ''
      #!/bin/sh
      # Session entry for display managers (bootstrap installs a .desktop pointing here).
      export PATH="${config.home.homeDirectory}/.local/bin:${profileBin}:$PATH"
      exec ${hypr}/bin/start-hyprland "$@"
    '';
  };

  systemd.user.services.hyprpolkitagent = {
    Unit = { Description = "Hyprland polkit agent"; PartOf = [ "graphical-session.target" ]; };
    Service = { ExecStart = "${pkgs.hyprpolkitagent}/libexec/hyprpolkitagent"; Restart = "on-failure"; };
  };
}
```
Add `./modules/gl.nix ./modules/hypr.nix` to imports.

- [ ] **Step 4: Make `hyprland.lua` read host.lua instead of hard-coded values**

At the top of `home/files/.config/hypr/hyprland.lua` (after the header comment) add:
```lua
dofile(os.getenv("HOME") .. "/.config/hypr/host.lua")
for k, v in pairs(HOST.env) do hl.env(k, v) end
hl.env("PATH", HOST.path)
hl.env("XDG_DATA_DIRS", HOST.data_dirs)
```
Then delete the now-duplicated literal `hl.env(...)` lines for `LIBVA_DRIVER_NAME`, `__GLX_VENDOR_LIBRARY_NAME`, `NVD_BACKEND`, `ELECTRON_OZONE_PLATFORM_HINT`, `KUBECONFIG`, `XDG_DATA_DIRS`, and apply:
```bash
f=home/files/.config/hypr/hyprland.lua
sed -i -E \
  -e 's#"\$HOME/\.nix-profile/bin/([a-z-]+)"#"\1"#g' \
  -e 's#/home/devsupreme/\.local/bin/#~/.local/bin/#g' \
  -e 's#"/home/devsupreme/#"~/#g' \
  -e 's#systemctl --user start hyprpolkitagent\.service#systemctl --user start hyprpolkitagent.service#' "$f"
grep -nE '/home/devsupreme|\.nix-profile' "$f" || echo clean
```
Expected: `clean`. (Commands run via `sh -c`, so `~` expands; binaries resolve through `HOST.path`.)

- [ ] **Step 5: Verify the config against the new Hyprland**

```bash
nix build .#homeConfigurations.workpc.activationPackage -o /tmp/dots-act
H=$(mktemp -d); mkdir -p $H/.config; cp -rL /tmp/dots-act/home-files/.config/hypr $H/.config/
HOME=$H /tmp/dots-act/home-path/bin/Hyprland --verify-config -c $H/.config/hypr/hyprland.lua 2>&1 | tail -20
```
Expected: `config ok`. For each reported error, read the Hyprland 0.56 release notes (`https://github.com/hyprwm/Hyprland/releases`) for the renamed/removed field and fix it in `hyprland.lua`. Repeat until ok. Record each change in the commit message.

- [ ] **Step 6: Run gpu, deps, lint checks**

```bash
for c in gpu-env-workpc gpu-env-archlaptop deps-workpc lint-workpc placement-workpc; do
  nix build .#checks.x86_64-linux.$c >/dev/null 2>&1 && echo "PASS $c" || echo "FAIL $c"; done
```
Expected: all PASS except possibly `lint-workpc` / `placement-workpc` (zsh/git/units, Tasks 7–8).

- [ ] **Step 7: Commit**

```bash
git add -A && git commit -m "feat(hypr): latest Hyprland via nix, GL wrap per host.gpu, generated host.lua; port config to 0.56"
```

---

### Task 7: Shell and git

**Files:**
- Create: `home/modules/shell.nix` (replace existing), `home/modules/git.nix`
- Modify: `home/files/.zshrc`, `home/files/.zshenv`
- Delete: `hosts/archdesk/files/zsh/` (reference no longer needed)

**Interfaces:**
- Produces: `~/.config/zsh/nix-paths.zsh` exporting `ZSH`, `ZSH_CUSTOM`, plugin dirs; `~/.config/git/config` (HM `programs.git`).

- [ ] **Step 1: Write `home/modules/shell.nix`**

```nix
{ config, pkgs, ... }:
let
  custom = pkgs.linkFarm "omz-custom" [
    { name = "plugins/zsh-autosuggestions";     path = "${pkgs.zsh-autosuggestions}/share/zsh-autosuggestions"; }
    { name = "plugins/zsh-syntax-highlighting"; path = "${pkgs.zsh-syntax-highlighting}/share/zsh-syntax-highlighting"; }
    { name = "plugins/forgit";                  path = "${pkgs.zsh-forgit}/share/zsh/zsh-forgit"; }
  ];
in {
  home.packages = [ pkgs.zsh pkgs.oh-my-zsh pkgs.starship pkgs.zoxide pkgs.fzf pkgs.bat ];
  xdg.configFile."zsh/nix-paths.zsh".text = ''
    # generated by dots — sourced first by ~/.zshrc
    export ZSH="${pkgs.oh-my-zsh}/share/oh-my-zsh"
    export ZSH_CUSTOM="${custom}"
    export KUBECONFIG="$HOME/.kube/onprem-s2a.yaml"
  '';
  systemd.user.sessionVariables.KUBECONFIG = "${config.home.homeDirectory}/.kube/onprem-s2a.yaml";
}
```
(`programs.zsh` stays disabled: `.zshrc`/`.zshenv` are deployed verbatim from `home/files`.)

- [ ] **Step 2: Normalize `.zshrc` / `.zshenv`**

In `home/files/.zshrc`:
- First line: `source "$HOME/.config/zsh/nix-paths.zsh"`.
- Delete the lines that set `ZSH=`/`ZSH_CUSTOM=` to `~/.config/oh-my-zsh`.
- Delete dead sources: `~/.asdf/asdf.sh`, `~/.config/envman/load.sh`, linuxbrew `shellenv`, `~/.bun/_bun`, LM Studio PATH, `/etc/profile.d/nix.sh` (HM's session vars cover it), the microk8s aliases.
- Replace `batcat` with `bat`; `PNPM_HOME=/home/devsupreme/...` → `PNPM_HOME="$HOME/.local/share/pnpm"`.
- Keep `[[ -r ~/.secrets ]] && source ~/.secrets`.
In `home/files/.zshenv`: replace `. "$HOME/.cargo/env"` with `[ -r "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"`; delete the `KUBECONFIG` export (now in nix-paths.zsh / session vars).
```bash
grep -nE '/home/devsupreme|linuxbrew|asdf|envman|batcat' home/files/.zshrc home/files/.zshenv || echo clean
zsh -n home/files/.zshrc && echo syntax-ok
```
Expected: `clean`, `syntax-ok`.

- [ ] **Step 3: Write `home/modules/git.nix` (work identity, D10)**

```nix
{ pkgs, ... }: {
  programs.git = {
    enable = true;
    userName = "Shaik Noorullah";
    userEmail = "snoorullah@proficientnow.com";
    extraConfig = {
      credential."https://github.com".helper = [ "" "!${pkgs.gh}/bin/gh auth git-credential" ];
      credential."https://gist.github.com".helper = [ "" "!${pkgs.gh}/bin/gh auth git-credential" ];
      init.defaultBranch = "main";
    };
    includes = [ { condition = "gitdir:~/work/"; contents.user = { name = "Shaik Noorullah"; email = "snoorullah@proficientnow.com"; }; } ];
  };
}
```
Remove the old `programs.git` block (with `shaiknooru247@gmail.com`) from the previous `shell.nix`. Add `./modules/shell.nix ./modules/git.nix` to imports.
```bash
grep -rn 'shaiknooru247' home/ && echo "FAIL gmail still present" || echo "no gmail"
```
Expected: `no gmail`.

- [ ] **Step 4: Delete the archdesk zsh reference and run checks**

```bash
git rm -rq hosts/archdesk/files/zsh
for c in placement-workpc lint-workpc; do nix build .#checks.x86_64-linux.$c >/dev/null 2>&1 && echo PASS $c || echo FAIL $c; done
```
Expected: `lint-workpc` PASS; `placement-workpc` only missing `.config/systemd/user/*` (Task 8).

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat(shell,git): oh-my-zsh from nix, verbatim zshrc minus dead sources; work git identity"
```

---

### Task 8: User services, adhd data, wallpapers, timetrack option

**Files:**
- Create: `home/modules/services.nix`, `home/modules/adhd.nix`
- Modify: `home/modules/timetrack.nix` (gate on option), `reference/systemd-user/*` (read only, delete at end)

**Interfaces:**
- Produces: units `adhd-prayer-times.{service,timer}`, `adhd-salah-schedule.{service,timer}`, `aw-server`, `awatcher`, `tmux`, `onprem-kube-tunnel`, `ovh-k8s-tunnel`, `signoz-tunnel`; activation `dotsDataDirs`, `dotsWalls`.

- [ ] **Step 1: Port units from `reference/systemd-user/` to `home/modules/services.nix`**

Open each reference unit and translate field-for-field; replace absolute binaries with Nix paths:
```nix
{ config, pkgs, ... }:
let h = config.home.homeDirectory; bin = "${h}/.local/bin"; in {
  systemd.user.services = {
    adhd-prayer-times = { Unit.Description = "Regenerate prayer-times.conf"; Service = { Type = "oneshot"; ExecStart = "${bin}/adhd-prayer-times.sh"; }; };
    adhd-salah-schedule = { Unit.Description = "Arm today's salah nudges"; Service = { Type = "oneshot"; ExecStart = "${bin}/adhd-salah-schedule.sh"; }; };
    aw-server = { Unit.Description = "ActivityWatch server"; Service = { ExecStart = "${pkgs.aw-server-rust}/bin/aw-server"; Restart = "on-failure"; }; Install.WantedBy = [ "default.target" ]; };
    awatcher = { Unit = { Description = "ActivityWatch window watcher"; Requires = [ "aw-server.service" ]; After = [ "aw-server.service" ]; };
                 Service = { ExecStart = "${pkgs.awatcher}/bin/awatcher"; Restart = "on-failure"; }; };   # static: started by hyprland.lua
    tmux = { Unit = { Description = "tmux default session (detached)"; Documentation = "man:tmux(1)"; };
             Service = { Type = "forking"; ExecStart = "${pkgs.tmux}/bin/tmux new-session -d";
                         ExecStop = [ "${h}/.config/tmux/plugins/tmux-resurrect/scripts/save.sh" "${pkgs.tmux}/bin/tmux kill-server" ];
                         KillMode = "control-group"; RestartSec = 2; };
             Install.WantedBy = [ "default.target" ]; };
    onprem-kube-tunnel = {
      Unit = { Description = "SSH forward to the on-prem k8s API (10.10.10.10:6443, via any PVE host)"; After = [ "network-online.target" ]; Wants = [ "network-online.target" ]; };
      Service = { Type = "simple"; ExecStart = "${bin}/kube-tunnel.sh ${h}/.config/onprem-kube-tunnel.conf"; Restart = "always"; RestartSec = 5; };
      Install.WantedBy = [ "default.target" ]; };
    ovh-k8s-tunnel = {
      Unit = { Description = "SSH tunnel to OVH MicroK8s API (via pve-01)"; After = [ "network-online.target" ]; Wants = [ "network-online.target" ]; };
      Service = { Type = "simple"; Restart = "always"; RestartSec = 5;
        ExecStart = "${pkgs.openssh}/bin/ssh -N -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -i %h/.ssh/ovh_key -L 127.0.0.1:16443:192.168.0.10:16443 root@148.113.49.6"; };
      Install.WantedBy = [ "default.target" ]; };
    signoz-tunnel = {
      Unit = { Description = "SigNoz API port-forward (OVH cluster) for signoz-mcp-server"; After = [ "network-online.target" ]; Wants = [ "network-online.target" ]; StartLimitIntervalSec = 0; };
      Service = { Environment = "KUBECONFIG=%h/.kube/config"; Restart = "always"; RestartSec = 5;
        ExecStart = "${pkgs.kubectl}/bin/kubectl --context ovh -n signoz port-forward --address 127.0.0.1 svc/signoz 18080:8080"; };
      Install.WantedBy = [ "default.target" ]; };
  };
  systemd.user.timers = {
    adhd-prayer-times   = { Timer = { OnCalendar = "*-*-* 00:05:00"; OnBootSec = "2min"; Persistent = true; }; Install.WantedBy = [ "timers.target" ]; };
    adhd-salah-schedule = { Timer = { OnCalendar = "*-*-* 00:12:00"; OnStartupSec = "45"; Persistent = true; }; Install.WantedBy = [ "timers.target" ]; };
  };
}
```
These match the live units of 2026-10-07 with only binary paths changed. `~/.ssh/ovh_key` stays user data (not managed). Confirm nothing else differs:
```bash
grep -hE '^(ExecStart|ExecStop|Restart|Environment)' reference/systemd-user/*.service
```

- [ ] **Step 2: Write `home/modules/adhd.nix` (fresh-machine data, Review Focus 3)**

```nix
{ config, lib, pkgs, ... }: {
  home.activation.dotsDataDirs = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run mkdir -p "$HOME/.task" "$HOME/.cache/adhd" "$HOME/.local/share/adhd" "$HOME/.kube"
    run touch "$HOME/.local/share/adhd/salah.log"
    [ -s "$HOME/.config/adhd/prayer-times.conf" ] || run "$HOME/.local/bin/adhd-prayer-times.sh" || true
  '';
  home.activation.dotsWalls = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ ! -d "$HOME/walls/.git" ]; then
      run ${pkgs.git}/bin/git clone --depth 1 https://github.com/snoorullah/walls.git "$HOME/walls" || echo "walls clone skipped (offline)"
    fi
  '';
}
```

- [ ] **Step 3: Gate laptop timetrack on the option (D7)**

In `home/modules/timetrack.nix` wrap the whole `config` in `lib.mkIf config.dots.timetrack.enable { … }`, delete every reference to `adhd-salah-tasks` (home.file, service, timer), and remove the `home.file` entries for scripts now provided by `scripts.nix` (adhd-*.sh) and the `.taskrc`/hook (now in `home/files`). Remove `rofi` from its packages (now in packages.nix).
```bash
grep -rn 'adhd-salah-tasks' home/ && echo FAIL || echo "salah-tasks gone"
```

- [ ] **Step 4: Imports, build, all checks**

Add `./modules/services.nix ./modules/adhd.nix ./modules/timetrack.nix` to imports.
```bash
git rm -rq reference
nix flake check 2>&1 | tail -5
```
Expected: all checks pass.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat(services): user units in nix; fresh-machine data dirs + walls clone; timetrack opt-in"
```

---

### Task 9: Secrets, fonts, theme, cleanup of obsolete material

**Files:**
- Create: `home/modules/secrets.nix`, `home/modules/fonts.nix`, `home/modules/theme.nix`, `.sops.yaml`, `secrets/secrets.yaml`, `secrets/kube.yaml`
- Delete: `home.nix`, `home/laptop.nix`, `home/modules/desktop/` (files superseded), caelestia docs, `flake.lock` caelestia entry (via `nix flake lock`)

- [ ] **Step 1 (owner runs — keeps secrets out of agent logs): create the sops key and files**

```bash
mkdir -p ~/.config/sops/age && cp ~/.config/chezmoi/key.txt ~/.config/sops/age/keys.txt && chmod 600 ~/.config/sops/age/keys.txt
PUB=$(nix run nixpkgs#age -- -y ~/.config/sops/age/keys.txt 2>/dev/null || nix shell nixpkgs#age -c age-keygen -y ~/.config/sops/age/keys.txt)
printf 'creation_rules:\n  - path_regex: secrets/.*\\.yaml$\n    age: %s\n' "$PUB" > .sops.yaml
nix shell nixpkgs#sops nixpkgs#yq-go -c sh -c '
  yq -n ".secrets = load_str(\"$HOME/.secrets\")" > /tmp/s.yaml && sops -e /tmp/s.yaml > secrets/secrets.yaml && shred -u /tmp/s.yaml
  yq -n ".onprem = load_str(\"$HOME/.kube/onprem-s2a.yaml\") | .ovh = load_str(\"$HOME/.kube/ovh-k8s.conf\") | .config = load_str(\"$HOME/.kube/config\")" > /tmp/k.yaml && sops -e /tmp/k.yaml > secrets/kube.yaml && shred -u /tmp/k.yaml'
grep -c 'ENC\[' secrets/*.yaml
```
Expected: each file shows a count ≥ 1 (values encrypted).

- [ ] **Step 2: Write `home/modules/secrets.nix`**

```nix
{ config, ... }: let h = config.home.homeDirectory; in {
  sops = {
    age.keyFile = "${config.xdg.configHome}/sops/age/keys.txt";
    secrets.secrets       = { sopsFile = ../../secrets/secrets.yaml; path = "${h}/.secrets"; mode = "0600"; };
    secrets.kube-onprem   = { sopsFile = ../../secrets/kube.yaml; key = "onprem"; path = "${h}/.kube/onprem-s2a.yaml"; mode = "0600"; };
    secrets.kube-ovh      = { sopsFile = ../../secrets/kube.yaml; key = "ovh";    path = "${h}/.kube/ovh-k8s.conf";   mode = "0600"; };
    secrets.kube-config   = { sopsFile = ../../secrets/kube.yaml; key = "config"; path = "${h}/.kube/config";         mode = "0600"; }; # signoz-tunnel uses context "ovh" from here
  };
}
```

- [ ] **Step 3: Fonts and theme**

`home/modules/fonts.nix`:
```nix
{ pkgs, ... }: {
  fonts.fontconfig.enable = true;
  home.packages = with pkgs; [ nerd-fonts.jetbrains-mono nerd-fonts.fantasque-sans-mono victor-mono material-symbols noto-fonts noto-fonts-emoji ];
}
```
`home/modules/theme.nix` (mako icon path removed in Task 4 Step 4; GTK/qt files are verbatim in home/files):
```nix
{ pkgs, ... }: {
  home.packages = [ pkgs.papirus-icon-theme pkgs.kdePackages.breeze pkgs.kdePackages.breeze-icons ];
  xdg.configFile."mako/config".text = builtins.readFile ../files/.config/mako/config + ''
    icon-path=${pkgs.papirus-icon-theme}/share/icons/Papirus-Dark
  '';
}
```
Then `git mv home/files/.config/mako/config home/mako-config.base` and point `readFile` at `../mako-config.base` (so `files.nix` does not also deploy it).

- [ ] **Step 4: Delete obsolete material (D8)**

```bash
git rm -q home.nix home/laptop.nix
git rm -rq home/modules/desktop
git rm -q docs/superpowers/plans/2026-06-30-caelestia-*.md docs/superpowers/plans/2026-07-01-caelestia-*.md \
          docs/superpowers/specs/2026-06-30-caelestia-*.md docs/superpowers/specs/2026-07-01-caelestia-*.md
nix flake lock
grep -rniE 'caelestia|quickshell|eww|adhd-salah-tasks' --include='*.nix' . && echo FAIL || echo "obsolete gone"
```
(`qtengine/caelestia.colors` stays: it is the live Qt colour scheme file, only named after caelestia.)
Add `./modules/secrets.nix ./modules/fonts.nix ./modules/theme.nix` to imports.

- [ ] **Step 5: Checks and commit**

```bash
nix flake check 2>&1 | tail -3
git add -A && git commit -m "feat(secrets,fonts,theme): sops-nix for ~/.secrets + kubeconfigs; drop caelestia-era files"
```

---

### Task 10: System bootstrap per distro family + NixOS base

**Files:**
- Create: `bootstrap/common.sh`, `bootstrap/apt.sh`, `bootstrap/pacman.sh`, `bootstrap/dnf.sh`, `bootstrap/install.sh`, `hosts/nixos-laptop/` (adjust), `docs/install.md`

**Interfaces:**
- Produces: `bootstrap/install.sh <host>` — idempotent; installs Nix, system packages, session file, PAM, keyd, then runs `home-manager switch --flake .#<host> -b pre-dots`.

- [ ] **Step 1: `bootstrap/common.sh`**

```bash
#!/usr/bin/env bash
# Root-level pieces shared by every non-NixOS distro. Sourced by install.sh.
set -euo pipefail
install_nix() {
  command -v nix >/dev/null && return
  curl -fsSL https://install.determinate.systems/nix | sh -s -- install --no-confirm
  . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
}
install_session() {   # $1 = user
  sudo install -Dm644 /dev/stdin /usr/share/wayland-sessions/hyprland-dots.desktop <<EOF
[Desktop Entry]
Name=Hyprland (dots)
Exec=/home/$1/.local/bin/start-hyprland-dots
Type=Application
EOF
}
install_keyd_conf() { sudo install -Dm644 "$DOTS/system/keyd/default.conf" /etc/keyd/default.conf; sudo systemctl enable --now keyd; }
switch_home() { nix run home-manager/master -- switch --flake "$DOTS#$1" -b pre-dots; }
```
Copy the live keyd file into the repo: `mkdir -p system/keyd && sudo cat /etc/keyd/default.conf > system/keyd/default.conf`.

- [ ] **Step 2: Per-family package scripts**

`bootstrap/pacman.sh`:
```bash
install_system() {
  sudo pacman -S --needed --noconfirm base-devel git curl greetd greetd-tuigreet pipewire pipewire-pulse wireplumber \
    polkit keyd hyprlock docker xdg-desktop-portal-gtk
  [ "${GPU:-}" = nvidia ] && sudo pacman -S --needed --noconfirm nvidia-open-dkms nvidia-utils
  printf 'auth include system-login\n' | sudo tee /etc/pam.d/hyprlock >/dev/null
}
```
`bootstrap/apt.sh`:
```bash
install_system() {
  sudo apt-get update
  sudo apt-get install -y git curl greetd pipewire pipewire-pulse wireplumber policykit-1 keyd docker.io xdg-desktop-portal-gtk
  if ! command -v hyprlock >/dev/null; then sudo add-apt-repository -y ppa:cppiber/hyprland && sudo apt-get install -y hyprlock; fi
  [ "${GPU:-}" = nvidia ] && sudo ubuntu-drivers install || true
  printf '@include common-auth\n' | sudo tee /etc/pam.d/hyprlock >/dev/null
}
```
`bootstrap/dnf.sh`:
```bash
install_system() {
  sudo dnf install -y git curl greetd tuigreet pipewire wireplumber polkit keyd docker xdg-desktop-portal-gtk || true
  sudo dnf copr enable -y solopasha/hyprland && sudo dnf install -y hyprlock
  printf 'auth include system-auth\n' | sudo tee /etc/pam.d/hyprlock >/dev/null
}
```
(hyprlock comes from the distro because PAM authentication needs the system's `unix_chkpwd`; decision D13 in the spec.)

- [ ] **Step 3: `bootstrap/install.sh`**

```bash
#!/usr/bin/env bash
# usage: bootstrap/install.sh <host>   (run as the target user, from a clone of dots)
set -euo pipefail
DOTS="$(cd "$(dirname "$0")/.." && pwd)"; export DOTS
host="${1:?host name from hosts/default.nix}"
. "$DOTS/bootstrap/common.sh"
. /etc/os-release
case " ${ID} ${ID_LIKE:-} " in
  *" arch "*)                     . "$DOTS/bootstrap/pacman.sh" ;;
  *" debian "*|*" ubuntu "*)      . "$DOTS/bootstrap/apt.sh" ;;
  *" fedora "*|*" rhel "*|*" centos "*) . "$DOTS/bootstrap/dnf.sh" ;;
  *" nixos "*) echo "NixOS: use nixos-rebuild switch --flake .#$host"; exit 0 ;;
  *) echo "unsupported distro: $ID"; exit 1 ;;
esac
GPU="$(nix eval --raw --file "$DOTS/hosts/default.nix" "$host.gpu" 2>/dev/null || echo mesa)"; export GPU
install_nix
install_system
install_session "$USER"
install_keyd_conf
switch_home "$host"
echo "done — log out and pick 'Hyprland (dots)' at the login screen"
```
`chmod +x bootstrap/*.sh`

- [ ] **Step 4: Update the NixOS host to use the shared home**

`hosts/nixos-laptop/configuration.nix`: keep it as is, but ensure `programs.hyprland.enable = true;` and that `users.users.${host.user}` uses `host.user` (replace literal `devsupreme`). `nix build .#nixosConfigurations.nixos-laptop.config.system.build.toplevel --dry-run` must evaluate.

- [ ] **Step 5: Write `docs/install.md`**

Sections: (1) prerequisites (git, sudo); (2) `git clone https://github.com/snoorullah/dots ~/dots && cd ~/dots`; (3) copy the age key to `~/.config/sops/age/keys.txt`; (4) `bootstrap/install.sh <host>`; (5) adding a new host = one line in `hosts/default.nix`; (6) update: `nix flake update && home-manager switch --flake ~/dots#<host>`; (7) rollback: `home-manager generations` then run the older generation's `activate`, and `*.pre-dots` backups.

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat(bootstrap): per-distro system layer (pacman/apt/dnf), session file, PAM, keyd; install docs"
```

---

### Task 11: Distro matrix CI

**Files:**
- Create: `tests/distro-matrix.sh`, `.github/workflows/matrix.yml`

- [ ] **Step 1: `tests/distro-matrix.sh` (runs inside a container as root, creates a user)**

```bash
#!/usr/bin/env bash
# Inside a fresh distro container: install deps, Nix, create user, pre-create clobber files,
# switch generic home, run in-home.sh (Review Focus 1-3,5).
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
  mkdir -p ~/.config/waybar && echo stale > ~/.config/waybar/config.jsonc && echo stale > ~/.zshrc
  cd ~/dots && nix run home-manager/master -- switch --impure --flake .#generic -b pre-dots
  test -f ~/.config/waybar/config.jsonc.pre-dots
  bash tests/in-home.sh'
```

- [ ] **Step 2: `.github/workflows/matrix.yml`**

```yaml
name: distro-matrix
on: [push, pull_request]
jobs:
  flake-check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: DeterminateSystems/nix-installer-action@main
      - run: nix flake check
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
CI has no age key, so the `generic` host must build without secrets (Step 3).

- [ ] **Step 3: Make secrets optional for `generic`**

In `options.nix` add `options.dots.secrets.enable = lib.mkOption { type = lib.types.bool; default = true; };`, in `home/default.nix` set `dots.secrets.enable = host.distro != "any";`, and wrap `secrets.nix`'s config in `lib.mkIf config.dots.secrets.enable`.

- [ ] **Step 4: Run one distro locally**

```bash
docker run --rm -v "$PWD:/src:ro" archlinux:latest bash /src/tests/distro-matrix.sh; echo exit=$?
```
Expected: `exit=0`. Then push and confirm all five matrix jobs are green:
```bash
git add -A && git commit -m "test: distro matrix (ubuntu, debian, arch, fedora, rocky) + flake check CI"
git push -u origin consolidate
gh run watch --repo snoorullah/dots
```

---

### Task 12: Cutover — work PC, then archdesk and archlaptop

**Files:**
- Create: `tests/live-diff.sh`, `tests/allowed-diffs.txt`

- [ ] **Step 1: Confirm each host's GPU on the box**

On each machine: `lspci | grep -iE 'vga|3d'`. NVIDIA → `gpu = "nvidia"`, otherwise `"mesa"`; fix `hosts/default.nix` and commit.

- [ ] **Step 2: `tests/live-diff.sh` — built vs live before switching**

```bash
#!/usr/bin/env bash
# Lists every managed file whose built content differs from the live one, minus allowed diffs.
set -uo pipefail
host="${1:-workpc}"
act=$(nix build --no-link --print-out-paths ".#homeConfigurations.$host.activationPackage")
repo="$(pwd)"
cd "$act/home-files"
find -L . -type f | sed 's#^\./##' | sort | while read -r p; do
  [[ $p == .local/bin/* ]] && continue            # wrappers always differ from the raw live scripts
  grep -qxF "$p" "$repo/tests/allowed-diffs.txt" && continue
  cmp -s "$p" "$HOME/$p" || echo "DIFF $p"
done
```
`tests/allowed-diffs.txt` — the files Tasks 4–9 intentionally changed:
```
.config/hypr/hyprland.lua
.config/hypr/host.lua
.config/waybar/config.jsonc
.config/otter-launcher/config.toml
.config/yazi/theme.toml
.config/mako/config
.zshrc
.zshenv
.task/hooks/on-modify.timewarrior
.config/zsh/nix-paths.zsh
.config/git/config
```
```bash
bash tests/live-diff.sh workpc
```
Expected: no output. Any `DIFF` line = an unintended change → fix in the repo, not live.

- [ ] **Step 3: Switch the work PC (owner present)**

```bash
nix profile remove Waybar                                  # nix-profile waybar duplicate (flake Alexays/Waybar)
cd ~/work/dots-consolidation/dots/.claude/worktrees/consolidate
nix run home-manager/master -- switch --flake .#workpc -b pre-dots
systemctl --user daemon-reload && systemctl --user list-timers | grep adhd
HYPRLAND_INSTANCE_SIGNATURE=$(ls -t $XDG_RUNTIME_DIR/hypr | head -1) hyprctl reload && hyprctl configerrors
bash tests/in-home.sh
```
Expected: timers listed, `hyprctl configerrors` empty, `in-home.sh` exit 0. Log out → log in to "Hyprland (dots)" (install the session file once: `. bootstrap/common.sh && install_session $USER`). Rollback if needed: `home-manager generations`, run the previous `…/activate`, restore `*.pre-dots`.

- [ ] **Step 4: Remove superseded system copies on the work PC (owner confirms each)**

```bash
sudo apt remove taskwarrior kitty                           # 2.6.2 task + apt kitty 0.32 (nix provides both)
rm -f ~/.local/bin/{clipse,aw-server,awatcher,starship,k9s} # now from nix
sudo rm -f /usr/bin/swww /usr/bin/swww-daemon               # manual install, now from nix
systemctl --user disable --now clip-prune.timer; rm -f ~/.config/systemd/user/clip-prune.*
```

- [ ] **Step 5: archdesk and archlaptop**

```bash
git clone -b consolidate https://github.com/snoorullah/dots ~/dots && cd ~/dots
cp <age key> ~/.config/sops/age/keys.txt
bootstrap/install.sh archdesk          # or archlaptop
bash tests/in-home.sh
```

- [ ] **Step 6: Merge and archive (owner actions)**

Open a PR `consolidate → main` on `snoorullah/dots` and merge after review. Then for `ubuntu-dots`, `hyprland-config`, `tmux-config` (both owners): add a README line "Moved to github.com/snoorullah/dots" and archive the repo in GitHub settings.

---

## Execution notes

- Tasks 1–9 build on each other's interfaces (`host`, `glWrap`, `home/files`, `scripts.nix`); run them in order.
- Task 9 Step 1 and Task 12 Steps 3–6 need the owner present (secrets, sudo, logout).
