# NixOS Laptop Daily-Driver — Design

A reproducible, flake-defined NixOS system for a fresh laptop install: the full Hyprland minimal-desktop + the time-tracking prosthetic + the complete dev/infra/editor toolchain, sharing one home-manager layer with the (Ubuntu) work PC.

## 1. Goal & realistic framing
One `nixos-install --flake` bootstraps a daily-usable laptop: Hyprland desktop, browsers, editors, the full dev stack, comms/media, and the personal time-tracking system — all declarative, rollback-able, reproducible. **Today's target = bootable + daily-usable** (system + NVIDIA + desktop + core apps + dev shell). The long tail (every last CLI tool, per-app polish) iterates over the following days. Hardware specifics (GPU exact model, disks) are generated *on the laptop* at install.

## 2. Hosts & architecture
Extend the existing `shaiknoorullah/dots` flake into a **multi-host** flake (no new repo, DRY):
- `homeConfigurations."devsupreme"` → **work PC** (Ubuntu, home-manager standalone). Unchanged behaviour; may gain shared modules over time. NOT migrated in this project.
- `nixosConfigurations."laptop"` → **the laptop** (full NixOS = system modules + the SAME home-manager config imported as `home-manager.nixosModules.home-manager`).
- The **home layer is shared** between both hosts via common modules; host-specific bits (nvidia, hardware, some services) live only under the laptop.

## 3. Repo structure (`~/dotfiles`)
```
flake.nix                # inputs + both outputs (home-manager standalone + nixosConfigurations.laptop)
hosts/
  laptop/
    configuration.nix    # NixOS system: boot, nvidia, net, audio, fonts, locale, user, services
    hardware-configuration.nix   # GENERATED on the laptop at install (placeholder committed)
home/
  home.nix               # top-level home-manager (imports the modules below); shared
  desktop/               # hyprland, waybar, mako, swayosd, swww, otter, kitty, clipse, bluetuith, lock/idle
  editors.nix            # vscode, zed, neovim
  dev.nix                # node/pnpm, python/uv, go, rust + the ats-v2 toolset + infra/devops + containers
  apps.nix               # browsers, comms, media
  timetrack.nix          # taskwarrior/timew/awatcher/adhd/rollup + the systemd --user units + scripts
  shell.nix              # zsh, tmux, git, starship, the CLI env
```
The current `home.nix` (caelestia + ripgrep/fastfetch) is refactored into `home/` modules; caelestia becomes a disabled input (§8).

## 4. System layer (NixOS, laptop) — `hosts/laptop/configuration.nix`
- **Boot:** `systemd-boot`, latest stable kernel, `nixpkgs` unstable (matches the work PC flake).
- **NVIDIA (user confirmed NVIDIA/hybrid):** `hardware.nvidia` with the proprietary driver + `nvidia.modesetting.enable`; if the laptop is Intel/AMD+NVIDIA hybrid (Optimus), `hardware.nvidia.prime` offload (sync/offload decided at install once the bus IDs are known). `services.xserver.videoDrivers = ["nvidia"]`. This replaces the nixGL hack the Ubuntu box needs.
- **Networking:** NetworkManager (`nm-applet` in the bar tray).
- **Audio:** PipeWire + WirePlumber (`services.pipewire`), rtkit.
- **Login → Hyprland:** `greetd` + `tuigreet` (minimal) launching Hyprland; `programs.hyprland.enable = true`.
- **Fonts:** JetBrainsMono Nerd Font, Noto (+ CJK + emoji), fontconfig defaults matching the work PC.
- **Locale/time:** `en_US.UTF-8`, `Asia/Kolkata`.
- **User:** `devsupreme`, shell zsh, groups `wheel networkmanager video audio docker`.
- **Services:** bluetooth (bluez + `services.blueman`? no — bluetuith TUI is used), `hardware.bluetooth.enable`, `security.polkit`, `xdg.portal` (hyprland portal), `services.gnome.gnome-keyring` or a keyring for secrets, `programs.dconf`.
- **Nix:** flakes enabled, `nix.settings.experimental-features = ["nix-command" "flakes"]`, allowUnfree, a weekly GC + store optimise.
- **Hardware:** `./hardware-configuration.nix` (generated at install; a placeholder is committed so the flake evaluates).

## 5. Home layer (shared) — `home/`
### 5a. Desktop (`home/desktop/`)
The whole minimal stack already built (Phases 0–2 on the work PC), expressed for NixOS:
- **Hyprland:** the current `hyprland.lua` is TRANSLATED to native hyprlang via `wayland.windowManager.hyprland.settings` + `extraConfig` (the lua `hl.*` API doesn't exist on stock NixOS Hyprland — see §6). Dracula values inlined (no chezmoi templating on NixOS).
- **waybar** (config.jsonc + style.css + the 4 ADHD custom-module scripts), **mako**, **swayosd**, **swww**, **clipse**, **otter-launcher** (+ all module scripts), **hyprlock**, **hypridle**, **kitty** (all its confs), **bluetuith**, **grim/slurp** screenshot script. Reused verbatim from the chezmoi tree, placed via `xdg.configFile."…".source` or the relevant HM program modules where they exist (kitty, waybar, mako have HM modules; hypr/otter/scripts via file symlinks).

### 5b. Editors (`home/editors.nix`)
- **VS Code** (`programs.vscode`), **Zed** (`programs.zed-editor` or the package), **Neovim** (`programs.neovim` — a sane starter config; the user's nvim config migrates later if they have one).

### 5c. Dev toolchains + tools (`home/dev.nix`) — from the ats-v2 devenv + infra
- **Languages:** Node 22 + corepack + pnpm; Python 3.13 + uv + pipx; Go 1.24; Rust stable (rustup or the toolchain).
- **From ats-v2 devenv:** kubectl, kubernetes-helm, azure-cli, gh, postgresql_16 (client), redis, minio-client, jq, yq-go, fzf, go-task, just, secretspec, aicommits, gitleaks, commitlint.
- **Infra/DevOps (user asked for "all"):** terraform, ansible, k9s, kustomize, kubectx, docker + docker-compose (or podman), lazygit, lazydocker.
- **Containers:** `virtualisation.docker.enable` (system) + the user in `docker` group; podman as alternative.
- **devenv:** the `cachix/devenv` + `direnv`/`nix-direnv` so per-project `devenv.nix`/`.envrc` (like ats-v2's) work out of the box.

### 5d. Apps (`home/apps.nix`)
- Browsers: **zen-browser** (via its flake/overlay — not in nixpkgs stable; use the community flake), **brave**, **firefox**.
- Comms: **Slack, Discord, teams-for-linux, Thunderbird**.
- Media: **mpv**, **ytm** (ytm-player — pipx/python package), (Spotify optional).
- Utilities: obsidian, pavucontrol, nautilus/thunar (a file manager), imv/loupe (image viewer).

### 5e. Time-tracking (`home/timetrack.nix`)
The full personal prosthetic: taskwarrior (3.x) + timewarrior + ActivityWatch (aw-server + awatcher) + the adhd/salah scripts + the Stage-3 rollup package + the systemd `--user` units + `~/powerhouse` note path. Packaged declaratively (the python rollup venv → a nix python env; the scripts → `home.file`/`writeShellApplication`; the units → `systemd.user.services/timers`).

### 5f. Shell (`home/shell.nix`)
zsh + the user's config, tmux (+ the title config), git identity/aliases, starship or the current prompt, `direnv`, the env vars.

## 6. The Hyprland translation (biggest single piece)
The work PC's `hyprland.lua` (Hyprland 0.55 lua API `hl.*`, chezmoi-templated Dracula) is NOT portable to stock NixOS Hyprland. Translate it to native hyprlang under `wayland.windowManager.hyprland.settings` (structured: `general`/`decoration`/`animations`/`input`/`bind`/`windowrulev2`/`exec-once`), inlining the Dracula hex. The just-built Phase-2 autostart (waybar/mako/swayosd-server + the minimal stack) is the exec-once set; the keybinds (otter menus, salah picker, break hotkey, ym, screenshot, swayosd, the Super+I bar toggle) all carry over. **Open:** confirm whether the work PC's lua is a real Hyprland-0.55 feature or a wrapper — either way the NixOS target is native hyprlang.

## 7. quickshell / caelestia — kept, disabled
Per the user: keep the `caelestia` flake input in `flake.nix` but do NOT wire it into the laptop's home (no `programs.caelestia`, not in `home.packages`). It stays available to re-enable in future. quickshell itself remains reachable via that input.

## 8. Install flow (today)
1. Boot the NixOS minimal ISO (write to USB).
2. Partition (a simple documented **manual** layout — safer than declarative `disko` for a first install): EFI (~512M) + root (ext4 or btrfs) + swap (or zram).
3. `nixos-generate-config --root /mnt` → copy the generated `hardware-configuration.nix` into `hosts/laptop/`.
4. `nixos-install --flake github:shaiknoorullah/dots#laptop` (or a local clone).
5. Reboot → greetd → Hyprland. `home-manager` activates as part of the NixOS switch.
Post-install: adjust NVIDIA PRIME bus IDs if hybrid; `nixos-rebuild switch --flake` for iterations.

## 9. Phasing (each phase = a flake that evaluates + a working increment)
- **Phase 1 — flake skeleton + bootable system:** multi-host flake, `hosts/laptop/configuration.nix` (boot/nvidia/net/audio/fonts/user/greetd+Hyprland), placeholder hardware-config; `nix flake check` green. Deliverable: a flake that would boot to Hyprland.
- **Phase 2 — desktop:** the translated Hyprland + waybar/mako/swayosd/otter/kitty/clipse/lock/idle/scripts in `home/desktop/`. Deliverable: full desktop on login.
- **Phase 3 — dev + editors:** `home/dev.nix` + `home/editors.nix` + docker + devenv/direnv. Deliverable: the ats-v2 dev shell + editors work.
- **Phase 4 — apps + shell:** `home/apps.nix` (browsers/comms/media) + `home/shell.nix`. Deliverable: daily-driver app set.
- **Phase 5 — time-tracking:** `home/timetrack.nix`. Deliverable: the personal prosthetic runs.
- Each phase `nix flake check`s + (where possible) builds under the current Ubuntu box's nix (evaluation/build check) before the laptop ever sees it.

## 10. Non-goals / out of scope
- Migrating or altering the **work PC** (stays Ubuntu + chezmoi; only shares home modules opportunistically).
- Declarative disk partitioning (`disko`) — a later reproducibility upgrade; first install is manual.
- Perfect 1:1 parity of every work-PC dotfile day one — MVP-bootable-today, iterate.
- Secrets: the work-PC secretspec/age flow is referenced but the laptop's secret store is set up minimally (open item §11).

## 11. Open items to resolve during planning
- **Data/secrets boundary:** the work-monitored constraint is about the WORK machine; the laptop is personal. Still — decide the laptop's secret handling (secretspec + a personal age key vs sops-nix vs plain). No work secrets on the laptop.
- **hyprland.lua nature** (native 0.55 lua vs a wrapper) → confirm; target is native hyprlang regardless.
- **zen-browser** packaging (community flake input vs an overlay) — pick one.
- **NVIDIA hybrid vs dedicated** — PRIME offload config finalized at install once bus IDs known.
- **Disk layout specifics** (btrfs-subvols vs ext4; swap size) — pick a simple default; the user confirms at partition time.
- **nvim config** — starter vs the user's existing config (if any) migrated.
- Whether the work PC also adopts `nixosConfigurations`-shared modules later (forward-compatible; not now).
