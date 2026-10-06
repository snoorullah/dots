final: prev: {
  otter-launcher  = final.callPackage ./otter-launcher.nix { };
  aether          = final.callPackage ./aether.nix { };
  dotsAdhanPython = final.python3.withPackages (ps: [ (final.callPackage ./adhanpy.nix { python3Packages = ps; }) ]);
}
