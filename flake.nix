{
  description = "devsupreme — portable home-manager config (Nix on Ubuntu)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # caelestia keeps its OWN pinned nixpkgs/quickshell (do NOT follows) so we
    # reuse the build already compiled, instead of rebuilding quickshell.
    caelestia.url = "git+file:///home/devsupreme/src/caelestia-shell?ref=feat/caelestia-widgets&shallow=1";

    # nix-gl-host: lets Nix-built GPU apps use the host nvidia driver on Ubuntu.
    nix-gl-host.url = "github:numtide/nix-gl-host";
  };

  outputs = inputs@{ nixpkgs, home-manager, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
    in {
      homeConfigurations."devsupreme" = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        extraSpecialArgs = { inherit inputs system; };
        modules = [
          inputs.caelestia.homeManagerModules.default
          ./home.nix
        ];
      };
    };
}
