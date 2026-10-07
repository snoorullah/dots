{ config, lib, pkgs, ... }:

# dots-ops root side on NixOS — the equivalent of home/.chezmoiscripts/run_onchange_after_26-dots-ops-system.sh.tmpl.
# Everything root runs comes from the Nix store (root-owned, read-only); /usr/local paths are rewritten to the store.
# The user calls the runner as /run/current-system/sw/bin/dots-ops-run (lib.sh picks that path, ruling R1).
# Group membership: add "dots-ops" to the user's extraGroups (configuration.nix).
let
  repo = ../../..;
  sys = repo + "/system/dots-ops";
  pkg = pkgs.stdenvNoCC.mkDerivation {
    pname = "dots-ops-system";
    version = "1";
    src = lib.fileset.toSource {
      root = repo;
      fileset = lib.fileset.unions [
        sys
        (repo + "/home/private_dot_local/lib/dots-ops/lib.sh")
        (repo + "/home/private_dot_local/private_bin/executable_dots-ops-job")
      ];
    };
    dontConfigure = true;
    dontBuild = true;
    installPhase = ''
      runHook preInstall
      L=$out/lib/dots-ops
      install -d $out/bin $L/jobs $L/actions $out/lib/systemd/system
      install -m 755 system/dots-ops/bin/dots-ops-run $out/bin/dots-ops-run
      install -m 755 home/private_dot_local/private_bin/executable_dots-ops-job $out/bin/dots-ops-job
      install -m 644 home/private_dot_local/lib/dots-ops/lib.sh $L/lib.sh
      if [ -d system/dots-ops/jobs ]; then cp -r system/dots-ops/jobs/. $L/jobs/; fi
      if [ -d system/dots-ops/actions ]; then cp -r system/dots-ops/actions/. $L/actions/; fi
      install -m 644 system/dots-ops/units/* $out/lib/systemd/system/
      if [ -d system/dots-ops/udev ]; then install -Dm 644 -t $out/lib/udev/rules.d system/dots-ops/udev/*; fi
      substituteInPlace $out/bin/dots-ops-run \
        --replace-fail /usr/local/lib/dots-ops $L \
        --replace-fail /usr/local/bin/dots-ops-job $out/bin/dots-ops-job
      substituteInPlace $out/bin/dots-ops-job --replace-fail /usr/local/lib/dots-ops $L
      for u in $out/lib/systemd/system/*; do
        substituteInPlace "$u" --replace-quiet /usr/local/bin/dots-ops-job $out/bin/dots-ops-job
      done
      patchShebangs --host $out/bin
      runHook postInstall
    '';
  };
  units = builtins.attrNames (builtins.readDir (sys + "/units"));
  withSuffix = sfx: map (lib.removeSuffix sfx) (builtins.filter (lib.hasSuffix sfx) units);
  # tools root jobs need on PATH (the user's Nix profile is never on root's PATH)
  rootPath = [ pkgs.jq pkgs.yq-go pkgs.util-linux pkgs.gawk pkgs.procps "/run/current-system/sw" ];
in
{
  environment.systemPackages = [ pkg pkgs.jq pkgs.yq-go ];
  systemd.packages = [ pkg ];
  services.udev.packages = [ pkg ];
  systemd.services."dots-ops@".path = rootPath;
  # [Install] sections of packaged units are ignored on NixOS: enable every shipped timer/path unit here
  systemd.timers = lib.genAttrs (withSuffix ".timer") (_: { wantedBy = [ "timers.target" ]; });
  systemd.paths = lib.genAttrs (withSuffix ".path") (_: { wantedBy = [ "paths.target" ]; });
  systemd.tmpfiles.rules = [ "d /var/lib/dots-ops 0755 root root -" "d /run/dots-ops 0755 root root -" ];
  users.groups.dots-ops = { };
  security.sudo.extraRules = [{
    groups = [ "dots-ops" ];
    commands = [
      { command = "${pkg}/bin/dots-ops-run"; options = [ "NOPASSWD" ]; }
      { command = "/run/current-system/sw/bin/dots-ops-run"; options = [ "NOPASSWD" ]; }
    ];
  }];
}
