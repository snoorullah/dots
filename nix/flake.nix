{
  description = "dots — packages for one user setup on every Linux (files are chezmoi's)";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = { url = "github:nix-community/home-manager"; inputs.nixpkgs.follows = "nixpkgs"; };
    nix-gl-host  = { url = "github:numtide/nix-gl-host";        inputs.nixpkgs.follows = "nixpkgs"; };
    nixgl        = { url = "github:nix-community/nixGL";        inputs.nixpkgs.follows = "nixpkgs"; };
    zen-browser  = { url = "github:0xc000022070/zen-browser-flake"; inputs.nixpkgs.follows = "nixpkgs"; };
    herdr.url    = "github:ogulcancelik/herdr/v0.9.3";
  };
  outputs = inputs@{ self, nixpkgs, home-manager, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; config.allowUnfree = true; overlays = [ (import ./pkgs/overlay.nix) ]; };
      mkHome = gpu: home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        extraSpecialArgs = { inherit inputs gpu; };
        modules = [ ./home.nix {
          home.username = builtins.getEnv "USER";
          home.homeDirectory = builtins.getEnv "HOME";
        } ];
      };
      act = gpu: (mkHome gpu).activationPackage;
      depsCheck = gpu: pkgs.runCommand "deps-${gpu}" { } ''
        fail=0
        while read -r c; do [ -z "$c" ] && continue
          [ -x "${act gpu}/home-path/bin/$c" ] || { echo "NO-CMD $c"; fail=1; }
        done < ${../tests/expected-commands.txt}
        [ $fail = 0 ] && touch $out
      '';
    in {
      homeConfigurations = { nvidia = mkHome "nvidia"; mesa = mkHome "mesa"; };
      nixosConfigurations.nixos-laptop = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit inputs; };
        modules = [
          ./hosts/nixos-laptop/configuration.nix
          home-manager.nixosModules.home-manager
          { nixpkgs.overlays = [ (import ./pkgs/overlay.nix) ];
            home-manager = { useGlobalPkgs = true; useUserPackages = true;
              extraSpecialArgs = { inherit inputs; gpu = "nixos"; };
              users.devsupreme = import ./home.nix; }; }
        ];
      };
      checks.${system} = { deps-nvidia = depsCheck "nvidia"; deps-mesa = depsCheck "mesa"; };
      packages.${system} = { inherit (pkgs) otter-launcher; };
    };
}
