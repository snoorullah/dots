# Install

One user setup on every Linux. chezmoi owns the files, Nix (home-manager) owns the packages, and a few
root-level pieces are installed by a chezmoi run script per distro family (Arch, Debian/Ubuntu,
Fedora/RHEL). NixOS gets the root layer from `nix/hosts/nixos-laptop`.

## 1. Install chezmoi

```sh
sh -c "$(curl -fsLS get.chezmoi.io)" -- -b ~/.local/bin
```

## 2. Age key (optional)

Copy your age identity to `~/.config/chezmoi/key.txt` (mode 0600) before the first apply.
Without it, secrets are skipped: the encrypted files, the kube configs and the two kube tunnel
units are left out, and everything else works.

## 3. Init and apply

```sh
chezmoi init --apply snoorullah/dots
```

You are asked once for the multiplexer (tmux by default, herdr as the trial). The GPU is detected
(`nvidia`, `mesa`, or `nixos`). The run scripts do the rest, in order:

1. `00-system` (once per machine): installs Nix if missing, then per distro family greetd, pipewire,
   polkit, keyd, hyprlock (plus the PAM file), Docker Engine, tailscale, and the wireshark CLI;
   on NVIDIA hosts also the driver and nvidia-container-toolkit. It installs the "Hyprland (dots)"
   session file and `/etc/keyd/default.conf`, enables `keyd`, `docker` and `tailscaled`, and adds you to the
   `docker` and `wireshark` groups. It does not run `tailscale up` (sign in yourself) and it does not
   enable greetd (see step 4).
2. `10-nix` (whenever `nix/` inputs change): `home-manager switch` for your GPU flavour. Files that
   already exist are moved aside as `*.pre-dots`.
3. `20-systemd` (whenever the units or the data change): enables the user timers and services,
   the selected multiplexer's service, the kube tunnels when an age key is present, and the timetrack
   units when `timetrack` is on.
4. `30-userdata` (once): creates `~/.task`, `~/.kube` and the adhd directories, generates prayer times, and clones
   `~/walls`.

Run `tailscale up` once, and log out and back in so the new groups apply.

## 4. Log in

Log out and choose "Hyprland (dots)" in your login manager. The root script writes
`/etc/greetd/config.toml` (tuigreet launching `start-hyprland-dots`, left alone if you already customised it)
and enables greetd only when the machine has no display manager. An existing display manager is never
disabled or replaced; it just lists the "Hyprland (dots)" session.

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
- Files replaced by the first switch are kept next to the originals as `*.pre-dots`.
- chezmoi never deletes anything destructively without `--force`. `chezmoi state delete-bucket --bucket=scriptState`
  makes the run-once scripts run again.

## 8. NixOS

```sh
sudo nixos-rebuild switch --flake ~/.local/share/chezmoi/nix#nixos-laptop
chezmoi apply
```

The host enables Hyprland, hyprlock, keyd (with `system/keyd/default.conf`), Docker with the NVIDIA
container toolkit, tailscale and wireshark. Regenerate `hardware-configuration.nix` on the machine at
install time (the committed one is a placeholder). The `10-nix` script does nothing on NixOS;
packages come from the rebuild.
