{ config, lib, pkgs, inputs, ... }:

# NixOS system layer for the laptop daily-driver.
# Hardware specifics come from ./hardware-configuration.nix, which is a
# committed PLACEHOLDER — regenerate it on the real machine at install time:
#   nixos-generate-config --root /mnt
#   cp /mnt/etc/nixos/hardware-configuration.nix hosts/laptop/
{
  imports = [ ./hardware-configuration.nix ];

  # ── Boot ──
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # ── Nix / nixpkgs ──
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nix.settings.auto-optimise-store = true;
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };
  nixpkgs.config.allowUnfree = true;

  # ── Networking ──
  networking.hostName = "laptop";
  networking.networkmanager.enable = true;

  # ── Locale / time ──
  time.timeZone = "Asia/Kolkata";
  i18n.defaultLocale = "en_US.UTF-8";
  console.keyMap = "us";

  # ── NVIDIA (proprietary; user confirmed NVIDIA / hybrid) ──
  # For a hybrid (Optimus) laptop, uncomment hardware.nvidia.prime below and
  # fill the real bus IDs from `lspci` at install. Pure-NVIDIA needs nothing more.
  hardware.graphics.enable = true;
  hardware.graphics.enable32Bit = true;
  services.xserver.videoDrivers = [ "nvidia" ];
  hardware.nvidia = {
    modesetting.enable = true;
    powerManagement.enable = true;
    open = false;              # proprietary kernel module (flip true only on Turing+ if desired)
    nvidiaSettings = true;
    package = config.boot.kernelPackages.nvidiaPackages.stable;
    # prime = {
    #   offload.enable = true;
    #   offload.enableOffloadCmd = true;      # provides `nvidia-offload`
    #   intelBusId = "PCI:0:2:0";             # <- from `lspci | grep VGA` at install
    #   nvidiaBusId = "PCI:1:0:0";            # <- from `lspci | grep 3D`  at install
    # };
  };

  # ── Audio (PipeWire) ──
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  # ── Bluetooth ──
  hardware.bluetooth.enable = true;
  hardware.bluetooth.powerOnBoot = true;

  # ── Login → Hyprland (greetd + tuigreet) ──
  programs.hyprland.enable = true;
  programs.hyprlock.enable = true;
  services.greetd = {
    enable = true;
    settings.default_session = {
      command = "${pkgs.tuigreet}/bin/tuigreet --time --remember --cmd /home/devsupreme/.local/bin/start-hyprland-dots";
      user = "greeter";
    };
  };

  # ── Desktop plumbing ──
  security.polkit.enable = true;
  programs.dconf.enable = true;
  services.gnome.gnome-keyring.enable = true;
  xdg.portal = {
    enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
  };
  services.libinput.enable = true;

  # ── keyd (homerow mods); same keymap the chezmoi root layer installs on other distros ──
  services.keyd.enable = true;
  environment.etc."keyd/default.conf".source = ../../../system/keyd/default.conf;

  # ── Fonts ──
  fonts.packages = with pkgs; [
    nerd-fonts.jetbrains-mono
    noto-fonts
    noto-fonts-cjk-sans
    noto-fonts-color-emoji
  ];

  # ── User ──
  programs.zsh.enable = true;
  users.users.devsupreme = {
    isNormalUser = true;
    description = "devsupreme";
    extraGroups = [ "wheel" "networkmanager" "video" "audio" "docker" "wireshark" ];
    shell = pkgs.zsh;
  };

  # ── Containers ── (client tools live in the home dev layer; daemon here)
  virtualisation.docker.enable = true;
  hardware.nvidia-container-toolkit.enable = true;   # NVIDIA host: CDI for `docker run --gpus`

  # ── Network / capture ── (`tailscale up` is the owner's step)
  services.tailscale.enable = true;
  programs.wireshark.enable = true;                  # dumpcap wrapper; user is in the wireshark group above

  # Minimal system-wide tooling; everything else is in the home layer.
  environment.systemPackages = with pkgs; [ git vim wget chezmoi ];

  # First release this host was built from — do NOT bump on upgrades.
  system.stateVersion = "25.11";
}
