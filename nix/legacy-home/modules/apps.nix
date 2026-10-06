{ pkgs, ... }:

# Phase 4 — daily-driver GUI apps: browsers, comms, media, utilities.
{
  home.packages = with pkgs; [
    # ── Browsers ──
    brave                # unfree
    firefox
    # TODO: zen-browser is NOT in nixpkgs — add via the community flake input
    #       (github:0xc000022070/zen-browser-flake) and wire its package here.

    # ── Comms ──
    slack                # unfree
    discord              # unfree
    teams-for-linux
    thunderbird

    # ── Media ──
    mpv
    # TODO: ytm (ytm-player) is a pipx/npm tool, not in nixpkgs — install on the
    #       laptop with `pipx install ytmusicapi`-style tooling in Phase 5 wiring.

    # ── Notes / productivity ──
    obsidian             # unfree

    # ── Utilities ──
    nautilus             # file manager
    imv                  # image viewer
    pavucontrol          # audio mixer GUI
    libreoffice-fresh    # docs
  ];
}
