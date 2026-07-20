{ pkgs, inputs, system, ... }:
let
  nixglhost = inputs.nix-gl-host.packages.${system}.default;
  caelestiaBase = inputs.caelestia.packages.${system}.with-cli;

  # Wrap caelestia's launcher with nix-gl-host so the Nix-built quickshell can
  # use the host nvidia driver. symlinkJoin keeps the rest of the package
  # (share/, cli) intact; we only replace bin/caelestia-shell with a wrapper.
  caelestiaWrapped = pkgs.symlinkJoin {
    name = "caelestia-shell-nixgl";
    paths = [ caelestiaBase ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      rm -f $out/bin/caelestia-shell
      makeWrapper ${nixglhost}/bin/nixglhost $out/bin/caelestia-shell \
        --add-flags ${caelestiaBase}/bin/caelestia-shell
    '';
  };
in {
  home.username = "devsupreme";
  home.homeDirectory = "/home/devsupreme";
  home.stateVersion = "25.11";

  programs.home-manager.enable = true;

  home.packages = [
    pkgs.ripgrep
    pkgs.fastfetch
    pkgs.papirus-icon-theme   # app icons for mako notifications (slack/discord/etc.)
    # yazi file manager + preview helpers (image previews use kitty's graphics protocol)
    pkgs.yazi
    pkgs.ffmpegthumbnailer    # video thumbnails
    pkgs.unar                 # archive preview/extract
    pkgs.fd                   # yazi's find/filter backend
    pkgs.file                 # mime detection fallback
    pkgs.waybar
    pkgs.mako
    pkgs.swayosd
    caelestiaWrapped # puts the nixGL-wrapped `caelestia-shell` on PATH
  ];

  programs.caelestia = {
    enable = true;
    package = caelestiaWrapped;
    cli.enable = true;
    # Judge it manually first; once happy we flip this on and retire the old shell.
    systemd.enable = false;
    # NOTE: deliberately NOT setting `settings` here — caelestia owns its own
    # WRITABLE ~/.config/caelestia/shell.json (its UI writes scheme/wallpaper/etc).
    # Managing it via HM makes it a read-only symlink and breaks caelestia's pickers.
  };
}
