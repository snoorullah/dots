# dots-overview (the tracking + data CLI) lives in ./dots-overview. It is added only when that directory
# exists, so this overlay still evaluates on a tree that does not carry it yet.
final: prev:
(prev.lib.optionalAttrs (builtins.pathExists ./dots-overview) {
  dots-overview = final.callPackage ./dots-overview { };
}) // {
  otter-launcher  = final.callPackage ./otter-launcher.nix { };
  aether          = final.callPackage ./aether.nix { };
  timetrack       = final.callPackage ./timetrack { };
  hypr-kdeconnect-fix = final.callPackage ./hypr-kdeconnect-fix.nix { };
  phosphor-icon-theme = final.callPackage ./phosphor-icon-theme { };
  dots-icon-font      = final.callPackage ./dots-icon-font { };
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
  # kcat: its optional Avro support (libserdes -> avro-c++ 1.12.0) fails to build at the pinned nixpkgs; plain Kafka
  # produce/consume does not need it. Drop this once avro-c++ builds again.
  kcat = prev.kcat.overrideAttrs (o: { buildInputs = final.lib.filter (d: (d.pname or "") != "libserdes") o.buildInputs; });
  # The ONE user-facing python3 env -- and ansible lives in it. Not `ansible` plus an
  # overridePythonAttrs: that puts a library on ansible's own process only, while a module runs
  # under ansible_playbook_python, the BARE interpreter, which reported sophosfirewall-python
  # not_found. Installed from this env, ansible_playbook_python is this env's python and sees
  # every library here. A second withPackages env is not an option either: two envs collide on
  # bin/python3 in home-manager's buildEnv.
  dotsAdhanPython = final.python3.withPackages (ps: [
    (final.callPackage ./adhanpy.nix { python3Packages = ps; })
    ps.ansible-core
    (final.callPackage ./sophosfirewall-python.nix { python3Packages = ps; })   # sophos.sophos_firewall
  ]);
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
