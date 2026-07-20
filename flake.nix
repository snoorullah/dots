{
  description = "devsupreme — multi-host Nix config (work-PC home-manager + NixOS laptop)";

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
      # ── Work PC (Ubuntu, standalone home-manager) — UNCHANGED ──
      homeConfigurations."devsupreme" = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        extraSpecialArgs = { inherit inputs system; };
        modules = [
          inputs.caelestia.homeManagerModules.default
          ./home.nix
        ];
      };

      # ── Laptop (fresh NixOS install, NVIDIA) ──
      # Deliberately does NOT reference inputs.caelestia, so
      # `nixos-install --flake #laptop` never tries to fetch the local-path
      # caelestia fork on a machine that lacks it. To use quickshell/caelestia
      # on the laptop later, repoint the caelestia input to the GitHub fork
      # (github:shaiknoorullah/shell?ref=feat/caelestia-widgets) and wire its
      # home-manager module into ./home/laptop.nix.
      nixosConfigurations."laptop" = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit inputs; };
        modules = [
          ./hosts/laptop/configuration.nix
          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.extraSpecialArgs = { inherit inputs system; };
            home-manager.users.devsupreme = import ./home/laptop.nix;
          }
        ];
      };
    };
}
