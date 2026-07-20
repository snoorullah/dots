{ pkgs, ... }:

# Laptop home-manager layer, imported by nixosConfigurations.laptop.
# Grows phase-by-phase; each module is self-contained.
#   Phase 2 → ./modules/desktop        (hyprland, waybar, mako, swayosd, otter, …)
#   Phase 3 → ./modules/dev.nix        + ./modules/editors.nix
#   Phase 4 → ./modules/apps.nix       + ./modules/shell.nix
#   Phase 5 → ./modules/timetrack.nix
{
  imports = [
    ./modules/desktop        # Phase 2 — hyprland, waybar, mako, swayosd, otter, kitty, lock/idle
    ./modules/dev.nix        # Phase 3 — node/python/rust/go + k8s/cloud/iac + devenv
    ./modules/editors.nix    # Phase 3 — vscode, zed, neovim
    ./modules/apps.nix       # Phase 4 — browsers, comms, media, utilities
    ./modules/shell.nix      # Phase 4 — zsh, starship, fzf, git, tmux
    ./modules/timetrack.nix  # Phase 5 — taskwarrior/timewarrior/ActivityWatch + salah/break engine
  ];

  home.username = "devsupreme";
  home.homeDirectory = "/home/devsupreme";
  home.stateVersion = "25.11";

  programs.home-manager.enable = true;

  home.packages = with pkgs; [
    ripgrep
    fastfetch
    git
  ];
}
