{ pkgs, ... }:

# Laptop home-manager layer, imported by nixosConfigurations.laptop.
# Grows phase-by-phase; each module is self-contained.
#   Phase 2 → ./modules/desktop        (hyprland, waybar, mako, swayosd, otter, …)
#   Phase 3 → ./modules/dev.nix        + ./modules/editors.nix
#   Phase 4 → ./modules/apps.nix       + ./modules/shell.nix
#   Phase 5 → ./modules/timetrack.nix
{
  imports = [
    # (filled in as phases land)
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
