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
      # udev RUN needs an absolute path: the store's systemctl instead of /usr/bin
      for r in $out/lib/udev/rules.d/*.rules; do
        substituteInPlace "$r" --replace-fail /usr/bin/systemctl ${pkgs.systemd}/bin/systemctl
      done
      install -m 644 system/dots-ops/firewall.json $L/firewall.json
      install -Dm 644 system/dots-ops/sshd/50-dots.conf $L/sshd/50-dots.conf
      substituteInPlace $out/bin/dots-ops-run \
        --replace-fail /usr/local/lib/dots-ops $L \
        --replace-fail /usr/local/bin/dots-ops-job $out/bin/dots-ops-job \
        --replace-fail /usr/local/bin/dots-ops-run $out/bin/dots-ops-run
      substituteInPlace $out/bin/dots-ops-job --replace-fail /usr/local/lib/dots-ops $L
      substituteInPlace $L/lib.sh --replace-fail /usr/local/bin/dots-ops-run $out/bin/dots-ops-run
      # jobs/actions default to the /usr/local prefix (e.g. OPS_SYS_DIR, the reboot-scheduled job runner); point them at the store copy
      for f in $L/jobs/*.sh $L/actions/*/*.sh; do
        substituteInPlace "$f" --replace-quiet /usr/local/lib/dots-ops $L \
          --replace-quiet /usr/local/bin/dots-ops-job $out/bin/dots-ops-job
      done
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
  rootPath = [ pkgs.jq pkgs.util-linux pkgs.gawk pkgs.procps pkgs.power-profiles-daemon "/run/current-system/sw" ];
  runners = "${pkg}/bin/dots-ops-run, /run/current-system/sw/bin/dots-ops-run";
  cfg = config.dots-ops;
  # Task 9 / R39: the same declarative rules the ufw/firewalld job applies elsewhere, as networking.firewall options
  fw = builtins.fromJSON (builtins.readFile (sys + "/firewall.json"));
  isRange = r: lib.hasInfix ":" (toString r.port);
  rulesFor = proto: builtins.filter (r: r.proto == proto) fw.allow;
  portsFor = proto: map (r: lib.toInt (toString r.port)) (builtins.filter (r: !isRange r) (rulesFor proto));
  rangesFor = proto: map (r: let b = lib.splitString ":" (toString r.port); in {
    from = lib.toInt (builtins.elemAt b 0); to = lib.toInt (builtins.elemAt b 1);
  }) (builtins.filter isRange (rulesFor proto));
  # ssh-harden lockout guard at eval time: only key-only sshd when the owner has declared authorized keys
  ownerKeys = config.users.users.${cfg.owner}.openssh.authorizedKeys;
  ownerHasKeys = ownerKeys.keys != [ ] || ownerKeys.keyFiles != [ ];
in
{
  options.dots-ops.owner = lib.mkOption {
    type = lib.types.str;
    description = "User whose authorized keys guard the sshd hardening; written to /etc/dots-ops/owner (R40).";
  };

  config = {
    environment.systemPackages = [ pkg pkgs.jq ];
    systemd.packages = [ pkg ];
    services.udev.packages = [ pkg ];
    services.power-profiles-daemon.enable = lib.mkDefault true;   # powerprofilesctl for the power-profile job and perf-mode
    systemd.services."dots-ops@".path = rootPath;
    # [Install] sections of packaged units are ignored on NixOS: enable every shipped timer/path unit here
    systemd.timers = lib.genAttrs (withSuffix ".timer") (_: { wantedBy = [ "timers.target" ]; });
    systemd.paths = lib.genAttrs (withSuffix ".path") (_: { wantedBy = [ "paths.target" ]; });
    systemd.tmpfiles.rules = [ "d /var/lib/dots-ops 0755 root root -" "d /run/dots-ops 0755 root root -" ];
    users.groups.dots-ops = { };
    # R19: same defense in depth as system/dots-ops/sudoers — no caller environment or PATH reaches the runner
    security.sudo.extraConfig = ''
      Cmnd_Alias DOTS_OPS_RUN = ${runners}
      Defaults!DOTS_OPS_RUN env_reset
      Defaults!DOTS_OPS_RUN secure_path="/run/wrappers/bin:/run/current-system/sw/bin"
    '';
    security.sudo.extraRules = [{
      groups = [ "dots-ops" ];
      runAs = "root";   # same as (root) in system/dots-ops/sudoers; the module default is ALL:ALL
      commands = [
        { command = "${pkg}/bin/dots-ops-run"; options = [ "NOPASSWD" ]; }
        { command = "/run/current-system/sw/bin/dots-ops-run"; options = [ "NOPASSWD" ]; }
      ];
    }];

    # Task 9: security domain (the firewall and ssh-harden root jobs report n/a on NixOS and point here)
    environment.etc."dots-ops/owner" = { text = "${cfg.owner}\n"; mode = "0644"; };
    assertions = [{ assertion = fw.default_incoming == "deny"; message = "dots-ops: firewall.json default_incoming must be deny"; }];
    networking.firewall = {
      enable = lib.mkDefault true;   # NixOS default policy already drops unlisted incoming (default_incoming deny)
      allowedTCPPorts = portsFor "tcp";
      allowedUDPPorts = portsFor "udp";
      allowedTCPPortRanges = rangesFor "tcp";
      allowedUDPPortRanges = rangesFor "udp";
    };
    services.openssh.settings = lib.mkIf ownerHasKeys {
      PermitRootLogin = lib.mkDefault "no";
      PasswordAuthentication = lib.mkDefault false;
      KbdInteractiveAuthentication = lib.mkDefault false;
    };
    warnings = lib.optional (config.services.openssh.enable && !ownerHasKeys)
      "dots-ops: sshd left as is (no users.users.${cfg.owner}.openssh.authorizedKeys) — key-only login would lock you out";
  };
}
