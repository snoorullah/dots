# Aether (github:shaiknoorullah/Aether): a thin overlay on stock Firefox. The SYSTEM step of the repo's
# install.sh (autoconfig loader into the Firefox app dir) is reproduced at build time by wrapFirefox:
#   extraPrefsFiles  -> aether-loader.cfg appended to <libdir>/mozilla.cfg (the wrapper's own autoconfig
#                       file, declared by defaults/pref/autoconfig.js; no config.js conflict)
#   zz-aether.js     -> <libdir>/defaults/pref/zz-aether.js (sandbox_enabled=false, loads last)
# The per-user profile (-P aether, chrome/ symlinks) is chezmoi / Task 10, at the same rev.
{ lib, runCommand, wrapFirefox, firefox-unwrapped, fetchFromGitHub, extraPolicies ? { } }:
let
  rev = "5e085656802eec3e26ecf0e4c55c2a771036cf36";
  src = fetchFromGitHub {
    owner = "shaiknoorullah"; repo = "Aether"; inherit rev;
    hash = "sha256-qHJ/7128CVhMm8yb7ad6inaiqsBCiz/8fJGQCQRmaXU=";
  };
  firefox = (wrapFirefox firefox-unwrapped {
    inherit extraPolicies;
    extraPrefsFiles = [ "${src}/overlay/loader/aether-loader.cfg" ];
  }).overrideAttrs (o: {
    buildCommand = o.buildCommand + ''
      cp ${src}/overlay/loader/zz-aether.js "$prefsDir/zz-aether.js"
    '';
  });
in
runCommand "aether-${rev}" { passthru = { inherit firefox src rev; }; meta.mainProgram = "aether"; } ''
  mkdir -p $out/bin $out/share/applications
  # launcher: overlay/bin/aether with the nix-built Firefox instead of `firefox` on PATH
  sed -e 's|^HERE=.*|HERE="${src}/overlay/bin"|' \
      -e 's|\$(firefox --version|$(${firefox}/bin/firefox --version|' \
      -e 's|^exec firefox |exec ${firefox}/bin/firefox |' \
      ${src}/overlay/bin/aether > $out/bin/aether
  chmod +x $out/bin/aether
  sed -e "s|^Exec=aether|Exec=$out/bin/aether|" ${src}/overlay/share/aether.desktop > $out/share/applications/aether.desktop
  for s in 16 24 32 48 64 128 256 512; do
    install -Dm644 ${src}/assets/logo/png/aether-$s.png $out/share/icons/hicolor/''${s}x''${s}/apps/aether.png
  done
  install -Dm644 ${src}/assets/logo/aether.svg $out/share/icons/hicolor/scalable/apps/aether.svg
''
