# Install

One user setup on every Linux. chezmoi owns the files, Nix (home-manager) owns the packages, and a few
root-level pieces are installed by a chezmoi run script per distro family (Arch, Debian/Ubuntu,
Fedora/RHEL). NixOS gets the root layer from `nix/hosts/nixos-laptop`.

## 1. Install chezmoi

```sh
sh -c "$(curl -fsLS get.chezmoi.io)" -- -b ~/.local/bin
```

## 2. Secrets (copied by hand, optional)

This repo is public, so it holds no secrets, not even encrypted ones. Copy them from an existing
machine, each with mode 0600: `~/.secrets`, `~/.kube/{config,onprem-s2a.yaml,ovh-k8s.conf}` and
the SSH keys the tunnels use (`~/.ssh/ovh_key`, plus the keys listed in
`~/.config/onprem-kube-tunnel.conf`). For example:

```bash
scp -p oldhost:'.secrets' ~/ && scp -p oldhost:'.kube/{config,onprem-s2a.yaml,ovh-k8s.conf}' ~/.kube/
chmod 600 ~/.secrets ~/.kube/*
```

Without them everything else works: shells skip `~/.secrets`, and each kube tunnel unit is skipped
(`ConditionPathExists`) until its file exists. After copying, run
`systemctl --user restart onprem-kube-tunnel ovh-k8s-tunnel`.

Personal machines only: the reverse SSH tunnel (`reverse-tunnel.service`, autossh) reads its remote host from
`~/.config/reverse-tunnel.env` (mode 0600), which is never in the repo:

```bash
REMOTE=user@host               # required: the machine that exposes the tunnel
REMOTE_PORT=2222               # optional (default 2222): port opened on REMOTE
LOCAL_PORT=22                  # optional (default 22): this machine's sshd
IDENTITY=/home/you/.ssh/id_ed25519   # optional (default ~/.ssh/id_ed25519); absolute path
```

The tunnel uses `StrictHostKeyChecking=yes`, so seed `~/.ssh/known_hosts` once by hand and check the
fingerprint: `ssh -i "$IDENTITY" "$REMOTE" true`. Then `systemctl --user restart reverse-tunnel`.

Also personal-only and hand-copied: `${XDG_CONFIG_HOME:-~/.config}/pi-fleet/config.sh` for `pi-fleet-monitor`
and `pnats-agent-browser` (project names, tmux panes, worktree paths; the scripts exit with a message without
it). The variables each script reads are listed at the top of the script.

## 3. Init, review, apply

There are no automatic backups of your existing files: chezmoi overwrites every file it manages, and
home-manager manages no dotfiles (only its own fontconfig snippets, `environment.d/10-home-manager.conf` and a
`tray.target` unit; `-b pre-dots` applies to those alone). The safety net is to look first and copy what you care
about yourself:

```sh
chezmoi init snoorullah/dots      # clone + write the config, change nothing
chezmoi diff                      # every file that would change
cp -a ~/.config ~/.config.bak     # your own backup of whatever the diff shows (and ~/.zshrc etc.)
chezmoi apply
```

You are asked once for the multiplexer (tmux by default, herdr as the trial). The GPU is detected
(`nvidia`, `mesa`, or `nixos`). The run scripts do the rest, in order:

1. `00-system` (once per machine): installs Nix if missing, then per distro family pipewire, polkit,
   hyprlock (plus the PAM file), Docker Engine and wireshark; on NVIDIA hosts also
   nvidia-container-toolkit, and the driver only when none is installed. Packages a distro does not carry are
   skipped with a message instead of failing the run: keyd comes from the distro when packaged (Arch), otherwise
   the pinned upstream release is built from source (Debian/Ubuntu, Fedora/RHEL); hyprlock comes from the
   cppiber PPA on Ubuntu, COPR on Fedora, EPEL on RHEL-likes, or is skipped. greetd is installed only where
   tuigreet is packaged (Arch, Fedora; not Ubuntu 24.04 / Debian 12). Docker is left alone when it is
   already installed (e.g. docker-ce); on NVIDIA hosts the script restarts docker only if `nvidia-ctk` actually
   changed `/etc/docker/daemon.json`. It installs the "Hyprland (dots)" session file and
   `/etc/keyd/default.conf`, enables `keyd` and `docker`, and adds you to the `docker` and
   `wireshark` groups. greetd: see step 4. (Tailscale is not part of the dotfiles; install it yourself if you want it.)
2. `10-nix` (whenever any file under `nix/` changes): `home-manager switch` for your GPU flavour, with the
   home-manager CLI pinned by `nix/flake.lock`.
3. `22-userdata` (once): creates `~/.task`, `~/.kube` and the adhd directories, generates prayer times, and clones
   `~/walls`.
4. `24-systemd` (whenever the units or the data change): enables the user timers and services (after
   `22-userdata`, so the prayer-time files exist), the selected multiplexer's service, the kube tunnels (each
   skipped until its hand-copied secret exists), and the timetrack units when `timetrack` is on.
5. `90-extra-tools` (whenever the pins change): the pinned npm/cargo/pipx/uv/go tools, the Grok CLI and the Aether
   Firefox profile. It runs last and puts the Nix profile on its own PATH, so it works on the first apply.

Log out and back in so the new groups apply.

## 4. Log in

Log out and choose "Hyprland (dots)" in your login manager. Where tuigreet is installed (Arch, Fedora), the
root script writes `/etc/greetd/config.toml` (tuigreet launching `start-hyprland-dots`, left alone if you already
customised it) and enables greetd only when the machine has no display manager. On Ubuntu 24.04 / Debian 12
greetd is not installed at all (no tuigreet package; greetd's own postinst would enable it). An existing display
manager (e.g. GDM) is never disabled or replaced; it just lists the "Hyprland (dots)" session.

## 5. Update

```sh
chezmoi update
```

## 6. Review before applying

```sh
chezmoi diff
```

## 7. Rollback

- Packages: `home-manager generations`, then run the `activate` script of the generation you want.
- Files: there are no automatic backups. Restore from the copy you made before the first apply (step 3).
- chezmoi never deletes anything destructively without `--force`. `chezmoi state delete-bucket --bucket=scriptState`
  makes the run-once scripts run again.

## 8. NixOS

```sh
sudo nixos-rebuild switch --flake ~/.local/share/chezmoi/nix#nixos-laptop
chezmoi apply
```

The host enables Hyprland, hyprlock, keyd (with `system/keyd/default.conf`), Docker with the NVIDIA
container toolkit and wireshark. Regenerate `hardware-configuration.nix` on the machine at
install time (the committed one is a placeholder). The `10-nix` script does nothing on NixOS;
packages come from the rebuild. home-manager runs with `useUserPackages = false`, so the packages land in
`~/.nix-profile` exactly as on other distros; the session PATH adds `/run/wrappers/bin` and
`/run/current-system/sw/bin` instead of `/usr/...`.

## 9. Maintenance (dots-ops)

After the first apply, dots-ops keeps the machine tidy: disk cleanup, updates, backups, firewall and ssh checks,
cluster health, one Waybar icon, and approvals for anything risky. The installer adds you to the `dots-ops` group,
so log out and back in once. Backups need `RESTIC_REPOSITORY` and `RESTIC_PASSWORD` in your hand-copied `~/.secrets`.
See [dots-ops.md](dots-ops.md) for how it works and the cutover fire drill.
On a company-managed (Intune) machine answer yes to the "Org-managed machine" prompt: see [Org-managed machines](dots-ops.md#org-managed-machines).
