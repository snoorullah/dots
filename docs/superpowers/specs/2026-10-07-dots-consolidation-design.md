# dots consolidation — design

Date: 2026-10-07 · Branch: `consolidate` (fork `snoorullah/dots`) · Owner: Shaik Noorullah

## Goal

One repo (`dots`) produces the **identical user setup** — Hyprland desktop, waybar, kitty,
otter-launcher, tmux, zsh, taskwarrior/timewarrior, adhd/salah tooling, git, fonts, themes —
on every machine: work PC (Ubuntu 24.04, RTX 4090), home PC `archdesk` (Arch), home laptop
(Arch), and any other Linux (Debian, Fedora/RHEL/Rocky/CentOS, NixOS).

`ubuntu-dots`, `hyprland-config` and `tmux-config` are folded in and then archived.

## Source of truth (precedence)

1. **The work PC's live files (2026-10-07)** win over every repo. Survey result: every live
   config is a plain file; chezmoi's source dir (`~/src/caelestia-shell/dotfiles`) is gone;
   home-manager (HM) manages only packages + 2 files. So the live files are the baseline and
   get snapshotted verbatim first (Task 3), then normalized.
2. **Exception — home changes made 2026-10-04 on `archdesk` are kept:**
   - `tmux-config@archdesk` (3 commits: `plugins.lock`, `@resurrect-processes "~claude->claude *"`,
     prefix+c rename prompt, prefix+C-l/C-k passthrough, eza + wl-copy, PR cache in
     `$XDG_RUNTIME_DIR`, claude-notify escaping). Base tmux = `archdesk`; the live
     `~/.tmux.conf` local overrides are re-applied on top.
   - `dots@archdesk` (plain zsh for archdesk) is already merged into this branch's history.
     Its *content* loses to the live work-PC zsh (rule 1, decision D4); it stays under
     `hosts/archdesk/` as reference until Task 9 deletes it.
3. Repos only fill gaps (things not present live): `keyd` config, hyprlock/hypridle parity.

## Architecture

```
            ┌──────────────── user layer (identical everywhere) ────────────────┐
 flake.nix ─┤ home-manager standalone: homeConfigurations."<user>@<host>"        │
            │  home/modules/{desktop,hypr,shell,tmux,git,timetrack,adhd,fonts,  │
            │                theme,apps,dev,editors,secrets}                     │
            │  every script = writeShellApplication (own PATH, no host PATH use) │
            │  Hyprland + portal + hyprlock: latest release, locked by flake.lock│
            └──────────────────────────────┬─────────────────────────────────────┘
                                           │ host.gpu = nvidia | mesa | nixos
            ┌──────────────── system layer (thin, per distro family) ───────────┐
            │ bootstrap/{apt,pacman,dnf}.sh: Nix installer, GPU driver, greetd   │
            │   + tuigreet, /etc/pam.d/hyprlock, wayland-session file, pipewire, │
            │   keyd, polkit, docker.  NixOS: nixosModules.base does the same.   │
            └────────────────────────────────────────────────────────────────────┘
```

Why this split: Nix + HM runs unchanged on every distro, so everything that *can* live in
`$HOME` does, with versions pinned by `flake.lock` → same binaries everywhere. Only things that
need root (kernel driver, PAM, display manager, session file, keyd) are per-distro, and they
are small.

### Decisions (defaults chosen; ★ = owner should confirm)

| # | Decision | Default |
|---|---|---|
| D1 | Hyprland source | Nix, **latest release** (owner decision 2026-10-07; nixpkgs-unstable has 0.56.2, live is 0.55.4). `flake.lock` keeps every host on the same build; `nix flake update` bumps all of them at once. GL-wrapped on non-NixOS. Distro Hyprland packages are not used. The live 0.55 Lua config is verified/ported to 0.56 in Task 6. |
| D2 | GL on non-NixOS | `host.gpu = "nvidia"` → `nix-gl-host` wrapper (proven on work PC); `"mesa"` → nixGL mesa (`targets.genericLinux.nixGL`); `"nixos"` → none. |
| D3 | Script PATH | Every `~/.local/bin` script ships as `writeShellApplication` with explicit `runtimeInputs`: no `/usr/bin`, linuxbrew, `~/.cargo/bin` or session-PATH reliance (Hyprland's session PATH is system-only). |
| D4 ★ | zsh | Live wins: oh-my-zsh + forgit/autosuggestions/syntax-highlighting via `programs.zsh.oh-my-zsh`. Dead sources (asdf, envman, linuxbrew, bun, LM Studio) dropped; `~/.secrets` kept via sops. |
| D5 | tmux | `tmux-config@archdesk` imported with `git subtree` (history kept) into `home/modules/tmux/config/`; plugins pinned as Nix derivations from `plugins.lock`, not fetched by TPM at runtime. |
| D6 ★ | Secrets | `sops-nix` HM module; age key at `~/.config/sops/age/keys.txt` (copied by hand, never committed). Holds `~/.secrets` and kubeconfigs (`onprem-s2a.yaml`, `ovh-k8s.conf`, `config` — the last is used by `signoz-tunnel` via context `ovh`). Replaces chezmoi's `encrypted_private_dot_secrets.age`. |
| D7 ★ | Laptop-only timetrack units (logind/rollup/sync CLI) | Kept behind `dots.timetrack.enable`, **default false** (not running on the work PC). |
| D8 | Obsolete, dropped | caelestia/quickshell, eww, rofi themes/scripts, X11 fallback (i3/picom/polybar), adhd distrobox bridge, `adhd-salah-tasks`, `clip-prune`, swaync mask, hyprland-config's hyprlang config. The `rofi` binary stays only for `adhd-capture.sh`. |
| D9 | Wallpapers | `~/walls` cloned on activation from `snoorullah/walls` when absent (569 MB, never in the Nix store). |
| D10 | Identity | Repo commits and global git identity = work (`snoorullah@proficientnow.com`); the Gmail identity is removed from `shell.nix`. |
| D11 | Hosts | `workpc` (ubuntu, nvidia), `archdesk` (arch, gpu set on the box), `archlaptop` (arch, gpu set on the box), `generic` (impure `$USER`/`$HOME`, mesa), NixOS `nixos-laptop` (HM as NixOS module). |
| D13 | hyprlock | From the **distro** (pacman / Ubuntu PPA / Fedora COPR), not Nix: a Nix-built hyprlock on a non-NixOS host cannot authenticate through the system's PAM (`unix_chkpwd` is setuid in the host only). Its config is still managed by dots. On NixOS it comes from `programs.hyprlock`. |
| D12 | Old repos | After cutover: README pointer commit + GitHub "archive" (owner action). ubuntu-dots history is **not** imported (77 MB `.git`, 57 MB obsolete PNGs). |

## Out of scope

Kernel/boot config on non-NixOS distros, disk layout, browser profiles, and user *data*
(`~/.task` DB, `salah.log`, timewarrior data) — data is synced separately.

Licensed fonts installed live but not redistributable in a public repo — LigaSFMono Nerd
(Apple SF Mono) and Segoe UI — are not committed; copy them to `~/.local/share/fonts` by hand.
Everything the desktop actually renders with (JetBrainsMono Nerd Font) comes from nixpkgs.

## Testing strategy

- `tests/portability-lint.sh`: managed files may not contain `/home/linuxbrew`, `/usr/bin/<tool>`,
  `/home/devsupreme`, `/snap/`, `.cargo/bin`, `.nix-profile/bin`, `/run/user/1001`.
- `tests/placement.sh`: builds the HM activation package; every path in
  `tests/expected-targets.txt` exists (executables checked for mode).
- `tests/deps.sh`: every command in `tests/expected-commands.txt` resolves in the built
  `home-path/bin`.
- `tests/distro-matrix.sh` + `.github/workflows/matrix.yml`: containers ubuntu:24.04,
  debian:12, archlinux, fedora:41, rockylinux:9 install Nix, run `home-manager switch`, then
  placement + deps inside. `nix flake check` evaluates every host including NixOS.
- `tests/live-diff.sh`: on the work PC, diffs built files against live `$HOME` before cutover;
  only normalizations listed in `tests/allowed-diffs.txt` may differ.
