final: prev: {
  otter-launcher  = final.callPackage ./otter-launcher.nix { };
  aether          = final.callPackage ./aether.nix { };
  dotsAdhanPython = final.python3.withPackages (ps: [ (final.callPackage ./adhanpy.nix { python3Packages = ps; }) ]);
  # tmux plugins pinned by tools/pin-tmux-plugins.sh; ~/.config/tmux/plugins -> ~/.nix-profile/share/tmux-plugins
  dotsTmuxPluginFarm = final.linkFarm "dots-tmux-plugins" (map (p: {
    name = "share/tmux-plugins/${p.dir}";
    path = final.fetchFromGitHub { inherit (p) owner repo rev hash; };
  }) (builtins.fromJSON (builtins.readFile ./tmux-plugins.json)));
}
