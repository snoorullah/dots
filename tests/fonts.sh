#!/usr/bin/env bash
# Fonts: every family the shell tokens name must be installed on BOTH hosts (home.nix and the NixOS
# configuration), must build to a .ttf of that family, and must resolve in fontconfig.
# No home-manager switch and no chezmoi apply: assertions a/b read the nix tree, c reads the live fontconfig.
# Set FONTS_SKIP_FC=1 to skip c (a fresh checkout before the owner has switched), FONTS_SKIP_BUILD=1 to skip b.
set -uo pipefail
root="$(git rev-parse --show-toplevel)"
home="$root/nix/home.nix"; host="$root/nix/hosts/nixos-laptop/configuration.nix"
fail=0; bad() { echo "FAIL: $*"; fail=1; }

# family ; nix attr (overlay or nixpkgs) ; regex for the attr in the host files ; ttf name regex ; needed in the NixOS fonts.packages
families=(
  "Bricolage Grotesque;bricolage-grotesque;bricolage-grotesque;Bricolage;yes"
  "JetBrains Mono;jetbrains-mono;(^|[^-a-z.])jetbrains-mono;JetBrainsMono-;yes"
  "dots Icons;dots-icon-font;dots-icon-font;dots-icons;no"
)
# dots Icons reaches the NixOS host through home.nix (imported by the host's home-manager), so only the other two need fonts.packages.

# a) each family has a package named in both host files
for f in "${families[@]}"; do
  IFS=';' read -r fam attr re _ need <<<"$f"
  grep -Eq "$re" <(grep -v '^\s*#' "$home" | sed 's/nerd-fonts\.jetbrains-mono//g') || bad "a: '$fam' ($attr) not in nix/home.nix"
 [ "$need" = yes ] || continue
  grep -Eq "$re" <(grep -v '^\s*#' "$host" | sed 's/nerd-fonts\.jetbrains-mono//g') || bad "a: '$fam' ($attr) not in nixos-laptop fonts.packages"
done

# b) each package builds and holds a .ttf of the family
if [ -z "${FONTS_SKIP_BUILD:-}" ]; then
  for f in "${families[@]}"; do
    IFS=';' read -r fam attr _ ttf _ <<<"$f"
    p="$(nix build --no-link --print-out-paths --impure --expr "
      let fl = builtins.getFlake \"path:$root/nix\";
          pkgs = import fl.inputs.nixpkgs { system = \"x86_64-linux\"; config.allowUnfree = true; overlays = [ (import $root/nix/pkgs/overlay.nix) ]; };
      in pkgs.\"$attr\"" 2>/dev/null | head -1)"
    if [ -z "$p" ]; then bad "b: '$attr' does not build/evaluate"; continue; fi
    find "$p" -iname '*.ttf' | grep -Eiq "$ttf" || bad "b: '$attr' output has no .ttf matching /$ttf/ ($p)"
  done
fi

# c) fontconfig resolves each family to itself, not a fallback
if [ -z "${FONTS_SKIP_FC:-}" ]; then
  for f in "${families[@]}"; do
    IFS=';' read -r fam _ <<<"$f"
    got="$(fc-match -f '%{family}' "$fam")"
    case ",$got," in *",$fam,"*) ;; *) bad "c: fc-match '$fam' -> '$got'" ;; esac
  done
fi

[ $fail = 0 ] && echo "fonts: ok" || exit 1
