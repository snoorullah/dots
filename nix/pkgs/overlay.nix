final: prev: {
  otter-launcher  = final.callPackage ./otter-launcher.nix { };
  aether          = final.callPackage ./aether.nix { };
  timetrack       = final.callPackage ./timetrack { };
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
