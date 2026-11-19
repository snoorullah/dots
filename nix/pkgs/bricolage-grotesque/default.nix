# Bricolage Grotesque (SIL OFL 1.1): the shell's heading and number face. Not in nixpkgs, so the static
# Regular / Medium / SemiBold TTFs (weights 400 / 500 / 600) are installed from the upstream repo at a pinned rev.
{ lib, stdenvNoCC, fetchFromGitHub }:

stdenvNoCC.mkDerivation {
  pname = "bricolage-grotesque";
  version = "unstable-2023-07-19";

  src = fetchFromGitHub {
    owner = "ateliertriay";
    repo = "bricolage";
    rev = "84745e5b96261ae5f8c6c856e262fe78d1d6efdd";
    hash = "sha256-K79ojosZqVg3S9cfBzI3d7ny+90cLCJq7W4XNotsP14=";
  };

  dontBuild = true;
  installPhase = ''
    runHook preInstall
    for w in Regular Medium SemiBold; do
      install -Dm444 "fonts/ttf/BricolageGrotesque-$w.ttf" "$out/share/fonts/truetype/BricolageGrotesque-$w.ttf"
    done
    install -Dm444 OFL.txt "$out/share/doc/bricolage-grotesque/OFL.txt"
    runHook postInstall
  '';

  meta = {
    description = "Bricolage Grotesque static fonts (Regular, Medium, SemiBold)";
    homepage = "https://github.com/ateliertriay/bricolage";
    license = lib.licenses.ofl;
    platforms = lib.platforms.all;
  };
}
