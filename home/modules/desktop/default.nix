{ pkgs, ... }:

# Phase 2 — the desktop layer: a daily-usable minimal Hyprland desktop.
# NOT caelestia/quickshell — native Hyprland + waybar + mako + swayosd +
# otter-launcher + kitty, all wired declaratively from ./files (verbatim
# copies of the live ~/.config material) and ./hyprland.nix (native hyprlang,
# see that file's header for the translation judgment calls).
{
  imports = [
    ./hyprland.nix
  ];

  home.packages = with pkgs; [
    waybar
    mako
    swayosd
    # nixpkgs renamed the `swww` wallpaper daemon package to `awww` upstream
    # (codeberg.org/LGFae/awww) — `pkgs.swww` still evaluates but only as a
    # deprecated alias emitting an eval warning, and its binaries are already
    # named `awww`/`awww-daemon` either way. Using the canonical attribute
    # directly; hyprland.nix's exec-once calls `awww-daemon`/`awww img`
    # accordingly (NOT `swww`/`swww-daemon`, which don't exist in this repo's
    # nixpkgs revision — a real unstable package-rename gotcha).
    awww
    cliphist
    clipse
    wl-clipboard
    grim
    slurp
    hyprlock
    hypridle
    kitty
    brightnessctl
    playerctl
    pavucontrol
    networkmanagerapplet
    libnotify
    jq

    # TODO: otter-launcher is NOT in nixpkgs (confirmed via
    # `nix search nixpkgs otter-launcher` — no results, and
    # `nix eval nixpkgs#otter-launcher` fails). Config + scripts are still
    # wired below (./files/otter-launcher); the live desktop's own binds
    # invoke it from ~/.cargo/bin/otter-launcher (cargo-installed, outside
    # Nix). Package it later via a flake input or overlay if it should be
    # reproducible too.
  ];

  # ── Verbatim config copies ────────────────────────────────────────────
  # Each of these becomes a single symlink from ~/.config/<name> into the
  # Nix store (fully declarative — hand-edits under these dirs won't stick).
  xdg.configFile = {
    "waybar".source = ./files/waybar;
    "mako".source = ./files/mako;
    "swayosd".source = ./files/swayosd;
    "otter-launcher".source = ./files/otter-launcher;
    "kitty".source = ./files/kitty;
  };

  # ── Bar scripts + screenshot -> ~/.local/bin ──────────────────────────
  # All fail gracefully today (timew/task/adhd-* aren't installed until
  # later phases) — they already guard with 2>/dev/null + fallback text.
  home.file = {
    ".local/bin/waybar-salah.sh" = {
      source = ./files/bin/waybar-salah.sh;
      executable = true;
    };
    ".local/bin/waybar-ctx.sh" = {
      source = ./files/bin/waybar-ctx.sh;
      executable = true;
    };
    ".local/bin/waybar-project.sh" = {
      source = ./files/bin/waybar-project.sh;
      executable = true;
    };
    ".local/bin/waybar-tracking.sh" = {
      source = ./files/bin/waybar-tracking.sh;
      executable = true;
    };
    ".local/bin/screenshot.sh" = {
      source = ./files/bin/screenshot.sh;
      executable = true;
    };
  };
}
