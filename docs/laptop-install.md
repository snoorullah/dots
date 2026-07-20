# Laptop install — NixOS daily-driver (`nixosConfigurations.laptop`)

Fresh-install runbook for the laptop. Target: bootable + daily-usable in one pass.
Design: `docs/superpowers/specs/2026-07-20-nixos-laptop-daily-driver-design.md`.

## What this installs
- **System:** systemd-boot, latest kernel, NVIDIA (proprietary), NetworkManager,
  PipeWire, bluetooth, greetd→Hyprland, docker daemon, fonts.
- **Desktop:** native Hyprland (hyprlang) + waybar + mako + swayosd + kitty +
  clipse/cliphist + hyprlock/hypridle + swww(awww). *(otter-launcher: see below.)*
- **Dev:** Node22/pnpm, Python313/uv/ruff, Rust stable, Go, kubectl/helm/k9s/
  azure-cli/gh, terraform/ansible, postgres/redis/mc, devenv+direnv; VS Code, Zed, Neovim.
- **Apps:** brave/firefox, slack/discord/teams/thunderbird, obsidian, mpv.
- **Shell:** zsh+starship+fzf+zoxide+git(personal)+tmux.
- **Time-tracking:** taskwarrior3 + timewarrior + ActivityWatch + the rollup +
  salah/break engine + systemd `--user` units *(Phase 5)*.

## 0. Make the installer USB
Download the NixOS **minimal** ISO (x86_64) and write it to a USB
(`dd if=nixos-minimal-*.iso of=/dev/sdX bs=4M status=progress oflag=sync`). Boot it.

## 1. Partition (manual — simple, documented)
Identify the disk (`lsblk`; assume `/dev/nvme0n1`). UEFI layout:

```
parted /dev/nvme0n1 -- mklabel gpt
parted /dev/nvme0n1 -- mkpart ESP fat32 1MiB 1025MiB
parted /dev/nvme0n1 -- set 1 esp on
parted /dev/nvme0n1 -- mkpart primary 1025MiB -16GiB    # root
parted /dev/nvme0n1 -- mkpart primary linux-swap -16GiB 100%   # 16G swap

mkfs.fat -F32 -n BOOT /dev/nvme0n1p1
mkfs.ext4 -L nixos     /dev/nvme0n1p2
mkswap -L swap /dev/nvme0n1p3 && swapon /dev/nvme0n1p3

mount /dev/disk/by-label/nixos /mnt
mkdir -p /mnt/boot && mount -o umask=077 /dev/disk/by-label/BOOT /mnt/boot
```
The labels (`nixos`, `BOOT`) match the flake's placeholder — step 3 overwrites it anyway.

## 2. Get the flake onto the machine
Recommended: install from a **local clone** (simplest, avoids input-fetch edge cases).
```
nix-shell -p git
git clone https://github.com/shaiknoorullah/dots /mnt/root/dots   # or copy via USB
```

## 3. Generate the real hardware config
```
nixos-generate-config --root /mnt
cp /mnt/etc/nixos/hardware-configuration.nix /mnt/root/dots/hosts/laptop/
```
This overwrites the committed **placeholder** with the machine's real disks/modules.
(Commit it later: `git add hosts/laptop/hardware-configuration.nix`.)

## 4. NVIDIA — only if this is a hybrid (Optimus) laptop
`lspci | grep -E 'VGA|3D'` → note the Intel/AMD and NVIDIA bus IDs. In
`hosts/laptop/configuration.nix` uncomment the `hardware.nvidia.prime` block and set
`intelBusId`/`nvidiaBusId` (format `PCI:X:Y:Z`). Pure-NVIDIA machines: skip this.

## 5. Install
```
nixos-install --flake /mnt/root/dots#laptop
# set root password when prompted, then:
reboot
```
Login at greetd → Hyprland.

> **Note on the `caelestia` flake input:** it points at a local path that won't exist
> on the laptop, but `#laptop` never references it, so Nix skips fetching it (lazy
> inputs). If an install ever complains about the caelestia input, either install
> from the local clone (above) or run
> `nix flake lock --override-input caelestia github:shaiknoorullah/shell/feat/caelestia-widgets`
> first. (Repointing it permanently is an open decision — see below.)

## 6. Post-install (manual, one-time)
- **otter-launcher** (the menu hub) is not in nixpkgs — install it with the Rust
  toolchain that's already in your dev layer:
  `cargo install otter-launcher` (lands in `~/.cargo/bin`, which the keybinds call).
- **Time-tracking data repo** (private): `git clone git@github.com:shaiknoorullah/timetrack-data ~/.local/share/timetrack/data-repo`.
- **aw-watcher-web** (browser activity): install the extension, then set
  `WEB_BUCKET` in `~/.config/timetrack` / `config.py` once you know the bucket id.
- **Habit sprint** (optional): set `HABIT_SPRINT_START` in config to start the 14-day countdown.
- Sign into brave/slack/etc.; import your nvim config if you want more than the starter.

## 7. Iterate + roll back
- Apply changes: `sudo nixos-rebuild switch --flake ~/dots#laptop`
- Roll back: pick an older generation at the systemd-boot menu, or
  `sudo nixos-rebuild switch --rollback`.

## Open decisions (not blocking a first boot)
- **caelestia/quickshell input**: kept in the flake but disabled. To run quickshell
  on the laptop later, repoint the input local-path → GitHub fork and wire its HM
  module into `home/laptop.nix`. (Affects the work-PC output too — decide deliberately.)
- **zen-browser**: needs a community flake input (TODO in `apps.nix`).
- **Disk layout**: ext4 + 16G swap chosen here; btrfs-subvols / zram are later upgrades.
