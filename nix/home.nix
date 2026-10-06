{ pkgs, lib, gpu, inputs, ... }: {
  home.stateVersion = "25.11";
  programs.home-manager.enable = true;
  targets.genericLinux.enable = gpu != "nixos";
  home.packages = [ ];
}
