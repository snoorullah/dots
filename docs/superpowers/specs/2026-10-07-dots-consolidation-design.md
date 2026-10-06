# dots consolidation — design (rev 2)

Date: 2026-10-07 · Branch: `consolidate` (fork `snoorullah/dots`) · Owner: Shaik Noorullah
Rev 2 replaces rev 1 (HM-owns-everything). Changes are owner decisions made 2026-10-07.

## Goal

One repo (`dots`) produces the **identical, minimal user setup** on every machine — work PC
(Ubuntu 24.04, RTX 4090), home PC `archdesk` (Arch), home laptop (Arch), and any other Linux
(Debian, Fedora/RHEL/Rocky/CentOS, NixOS). `ubuntu-dots`, `hyprland-config` and
`tmux-config` are folded in, then archived.

**Minimalism rule:** one tool per job. Terminal = text surface only; multiplexing lives in
exactly one multiplexer; no second launcher; no shell framework.

## Source of truth (precedence)

1. **Work PC live files (2026-10-07)** win over every repo. Every live config is a plain
   file (chezmoi's old sourceDir `~/src/caelestia-shell/dotfiles` is gone), so live files are
   imported first and then normalized.
2. **Exception — `tmux-config@archdesk` (2026-10-04)** is the tmux baseline (Claude panes
   restore with original flags, prefix+c rename, plugins.lock, eza/wl-copy, notify escaping);
   live `~/.tmux.conf` local overrides re-applied on top.
3. Repos fill gaps only (`keyd` config).
4. **Rev-2 owner decisions override live** where they replace a tool: kitty → foot,
   oh-my-zsh → antidote + zimfw modules, rofi → fzf, Hyprland 0.55 → latest.

## Architecture

```
dots/
├─ .chezmoiroot            → "home"
├─ home/                   chezmoi source state = every file under $HOME
│   ├─ .chezmoi.toml.tmpl  data: user, gpu (auto from lspci), multiplexer, encryption=age
│   ├─ .chezmoidata/       palette (Dracula), app lists
│   ├─ .chezmoiscripts/    run_once/run_onchange: system layer, nix switch, systemd, walls
│   ├─ dot_config/…        configs (templates where host-specific)
│   └─ dot_local/bin/…     scripts
├─ nix/                    flake: home-manager **packages only** (+ fonts, GL wrappers)
│   └─ pkgs/               otter-launcher, adhanpy, foot-ligatures, tmux plugin farm
└─ tests/, docs/
```

| Layer | Owns | Tool |
|---|---|---|
| Files | every file under `$HOME`: configs, `~/.local/bin` scripts, systemd **user** unit files, encrypted secrets | **chezmoi** (templates for host differences; `chezmoi diff` before every apply) |
| Packages | every binary the setup runs, pinned by `flake.lock`; fonts; GL wrappers | **Nix + home-manager**, `home.packages` only — HM writes no config files except its own `environment.d/10-home-manager.conf` and fontconfig |
| System (root) | Nix install, GPU driver, PAM for hyprlock, session file, greetd, keyd, docker | chezmoi `run_once_before_` scripts branching on `.chezmoi.osRelease.id`; NixOS: `nix/hosts/nixos-laptop` |

One command sets up or updates any machine: `chezmoi apply` (its `run_onchange_` script
runs `home-manager switch` whenever `nix/flake.lock` or `nix/**/*.nix` changes).
**No Ansible**: the root layer is ~15 package lines per distro family.

### PATH contract (why scripts can stay plain files)

Scripts are plain chezmoi files that call tools by name. Pinned tools win because every entry
point puts the Nix profile first:
`$HOME/.local/bin:$HOME/.nix-profile/bin` precedes `/usr/bin` in
`~/.config/environment.d/10-dots-path.conf` (systemd user services), `hyprland.lua`
(`hl.env("PATH", …)`, session children), and `~/.zshenv` (shells). Ubuntu's `/usr/bin/task`
(2.6.2) can still exist; it is never first.

## Decisions

| # | Decision | Value |
|---|---|---|
| D1 | Hyprland | Nix, latest release (nixpkgs-unstable: 0.56.2 today; live 0.55.4), locked by `flake.lock`, GL-wrapped on non-NixOS. Live 0.55 Lua config ported to 0.56. |
| D2 | GL on non-NixOS | `gpu=nvidia` → nix-gl-host; `gpu=mesa` → nixGL mesa; `gpu=nixos` → none. `gpu` auto-detected from `lspci` in `.chezmoi.toml.tmpl`, overridable. |
| D3 | Files vs packages | chezmoi owns files; Nix owns packages. A test asserts no path is managed by both. |
| D4 | Terminal | **foot**, built from the `barsmonster/foot` fork (adds `tweak.ligatures`) pinned to a commit; flag `footLigatures=false` falls back to upstream foot. No background images: popups use `alpha` + Hyprland blur. Popups: `foot -a <app-id> -c ~/.config/foot/popup.ini <cmd>`; main windows: `footclient` against `foot --server`. |
| D5 | Shell | zsh with **antidote + zimfw modules** (owner decision 2026-10-07). antidote (from Nix) loads `~/.zsh_plugins.txt` (chezmoi) as a static bundle; every line carries `pin:<commit>`. Modules: `zimfw/environment`, `zimfw/input`, `zimfw/utility`, `zimfw/git` (alias prefix `g`, oh-my-zsh-style names), `zimfw/completion`, `zsh-users/zsh-autosuggestions`, `MichaelAquilina/zsh-you-should-use` (replaces alias-finder), `zdharma-continuum/fast-syntax-highlighting` (last). Vi mode: built-in `bindkey -v`. Own `aliases.zsh` for non-git aliases. Dropped: oh-my-zsh and its 15 plugins (incl. Ubuntu-only `debian`, `command-not-found`), forgit, asdf/envman/linuxbrew/bun sources. History stays disabled (live choice, 2026-09-22). Rationale: zsh-bench first-command lag oh-my-zsh 84 ms vs zim 57 ms / static loaders ~66 ms; reproducible via `pin:`. |
| D6 | Multiplexer | Swappable via chezmoi data `multiplexer = "tmux" | "herdr"`. Default **tmux** (`tmux-config@archdesk`). **Herdr trial**: both installed; `docs/herdr-trial.md` defines pass/fail criteria; the loser is removed after the trial. Never both active. |
| D7 | Launcher | otter-launcher only. rofi removed: `adhd-capture.sh` uses an fzf prompt in a foot popup. |
| D8 | Secrets | chezmoi native age encryption (`encrypted_private_*`), identity `~/.config/chezmoi/key.txt` (existing key). Holds `~/.secrets`, `~/.kube/{config,onprem-s2a.yaml,ovh-k8s.conf}`. |
| D9 | Laptop timetrack units | behind data flag `timetrack = false` (not running on work PC). |
| D10 | Obsolete | caelestia/quickshell, eww, rofi, kitty (+`kitty.app`), X11 fallback (i3/picom/polybar), adhd distrobox bridge, `adhd-salah-tasks`, `clip-prune`, swaync mask, hyprland-config hyprlang, `signoz-tunnel.service` (owner: not needed). |
| D11 | Wallpapers | `~/walls` cloned by `run_once_after_` from `snoorullah/walls` (569 MB, never in the Nix store). |
| D12 | Identity | global git identity = `snoorullah@proficientnow.com`; no Gmail anywhere. |
| D13 | hyprlock | from the distro (PAM needs host `unix_chkpwd`); config from chezmoi. NixOS: `programs.hyprlock`. |
| D14 | Hosts | data-driven, not a host table: any machine = `chezmoi init --apply snoorullah/dots`; gpu auto-detected. Known hosts: workpc, archdesk, archlaptop; NixOS `nixos-laptop` keeps a system config. |
| D15 | Old repos | archive after cutover (owner action). ubuntu-dots history not imported (77 MB `.git`, 57 MB obsolete PNGs); tmux-config imported with history (`git subtree`). |

## Out of scope

Kernel/boot on non-NixOS, disk layout, browser profiles, user **data** (`~/.task` DB,
`salah.log`, timewarrior data). Licensed fonts not redistributable in a public repo
(LigaSFMono/SF Mono, Segoe UI) — copied by hand; the desktop renders with JetBrainsMono Nerd
Font from nixpkgs.

## Testing strategy

- `tests/render.sh <gpu> <multiplexer>`: `chezmoi apply --destination <tmp>` with fixed data
  (no secrets, no scripts) → rendered tree for the other tests.
- `tests/placement.sh`: every path in `tests/expected-targets.txt` exists in the render.
- `tests/lint.sh`: rendered files contain none of `/home/devsupreme`, `/home/linuxbrew`,
  `/snap/`, `.cargo/bin`, `/run/user/1001`, `/usr/bin/<tool>`, `kitty`, `rofi`, `oh-my-zsh`.
- `tests/overlap.sh`: rendered chezmoi paths ∩ home-manager `home-files` paths = ∅.
- `tests/in-home.sh`: behavioural — scripts run with the PATH contract on an empty home.
- `nix flake check`: every command in `tests/expected-commands.txt` is in each `home-path/bin`.
- CI matrix (ubuntu:24.04, debian:12, archlinux, fedora:41, rockylinux:9): fresh container →
  `chezmoi init --apply` → `in-home.sh`.
- Cutover gate on the work PC: `chezmoi diff` shows only intended changes.
