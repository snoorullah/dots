final: prev: {
  otter-launcher  = final.callPackage ./otter-launcher.nix { };
  aether          = final.callPackage ./aether.nix { };
  timetrack       = final.callPackage ./timetrack { };
  hypr-kdeconnect-fix = final.callPackage ./hypr-kdeconnect-fix.nix { };
  # HyprCapture: upstream's own nix/package.nix (hyprlandPlugins.mkHyprlandPlugin, built against this pkgs.hyprland;
  # the plugin .so and hyprcapture-ui come from one derivation) at the pinned HEAD sha.
  hyprcapture = let
    src = final.fetchFromGitHub {
      owner = "gfhdhytghd"; repo = "HyprCapture";
      rev = "73a519e9643338e580a594f543dc738782bdbf19";
      sha256 = "1p6gr234si52yq4yrsh0qgz6sdkfj59ill3g9znkh7y87hnyniyg";
    };
  # the in-place-editor ctest fails under the nix sandbox's offscreen Qt (11 other UI/plugin tests pass); exclude just it
  in (final.callPackage "${src}/nix/package.nix" { inherit src; }).overrideAttrs (o: {
    preCheck = (o.preCheck or "") + ''
      export CTEST_ARGS="-E in-place-editor"
      checkFlagsArray+=("ARGS=-E in-place-editor")
    '';
  });
  dotsAdhanPython = final.python3.withPackages (ps: [ (final.callPackage ./adhanpy.nix { python3Packages = ps; }) ]);
  # tmux plugins pinned by tools/pin-tmux-plugins.sh; ~/.config/tmux/plugins -> ~/.nix-profile/share/tmux-plugins
  # tmux-thumbs is the exception: it needs a compiled binary, so it comes prebuilt from nixpkgs.
  dotsTmuxPluginFarm = final.linkFarm "dots-tmux-plugins" ((map (p: {
    name = "share/tmux-plugins/${p.dir}";
    path = final.fetchFromGitHub { inherit (p) owner repo rev hash; };
  }) (builtins.fromJSON (builtins.readFile ./tmux-plugins.json))) ++ [{
    name = "share/tmux-plugins/tmux-thumbs";
    path = "${final.tmuxPlugins.tmux-thumbs}/share/tmux-plugins/tmux-thumbs";
  }]);
}
