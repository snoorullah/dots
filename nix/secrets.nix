{ config, pkgs, lib, ... }:
# One local vault: KeePassXC holds passwords, app secrets (Secret Service), SSH keys (fed to
# ssh-agent on unlock, removed on lock) and browser logins. Clipboard history skips secrets.
#
# Split of responsibilities:
#   nix (this file)  packages, browser native-messaging hosts, keepassxc.ini keys, dots-secrets
#   chezmoi          ssh-agent.service, keepassxc.service, env, Hyprland autostart, dots-clip-store
#   dots-secrets     the one-time, stateful steps: create the vault, import SSH keys, move the
#                    Secret Service off gnome-keyring (with its items), move CLI tokens.
#
# Secret Service is NOT switched declaratively: switching before the items are copied would log
# every app out (Chrome/Brave/VS Code/Slack keep their encryption keys there).
let
  kp = pkgs.keepassxc;

  # Browser bridge manifests. Firefox-family uses allowed_extensions, Chromium-family allowed_origins.
  ffHost = builtins.toJSON {
    name = "org.keepassxc.keepassxc_browser";
    description = "KeePassXC integration with native messaging support";
    path = "${kp}/bin/keepassxc-proxy";
    type = "stdio";
    allowed_extensions = [ "keepassxc-browser@keepassxc.org" ];
  };
  crHost = builtins.toJSON {
    name = "org.keepassxc.keepassxc_browser";
    description = "KeePassXC integration with native messaging support";
    path = "${kp}/bin/keepassxc-proxy";
    type = "stdio";
    allowed_origins = [
      "chrome-extension://oboonakemofpalcgghocfoadofidjkkk/" # Chrome Web Store build
      "chrome-extension://pdffhmdngciaglkoonimfcmckehcpafo/" # Edge add-ons build
    ];
  };
  hostFile = dir: json: { "${dir}/org.keepassxc.keepassxc_browser.json".text = json; };

  # keepassxc.ini is rewritten by KeePassXC at runtime (geometry, recent files), so a read-only
  # symlink would break it. Set only our keys, in place, on every activation.
  ini = "${config.xdg.configHome}/keepassxc/keepassxc.ini";
  settings = {
    General = {
      ConfigVersion = "2";
      RememberLastDatabases = "true";
      RememberLastKeyFiles = "true";
      OpenPreviousDatabasesOnStartup = "true";
      AutoSaveAfterEveryChange = "true";
      AutoReloadOnChange = "true";
      BackupBeforeSave = "true";
      UseAtomicSaves = "true";
    };
    GUI = {
      ShowTrayIcon = "true";
      MinimizeToTray = "true";
      MinimizeOnClose = "true";
      MinimizeOnStartup = "true";
      TrayIconAppearance = "monochrome-light";
      CheckForUpdates = "false";
      ApplicationTheme = "dark";
    };
    Security = {
      ClearClipboard = "true";
      ClearClipboardTimeout = "10";
      ClearSearch = "true";
      LockDatabaseIdle = "true";
      LockDatabaseIdleSeconds = "900";
      LockDatabaseScreenLock = "true";
      IconDownloadFallback = "false";
      PasswordsHidden = "true";
      HidePasswordPreviewPanel = "true";
    };
    # ssh-agent.service (chezmoi) owns this socket; KeePassXC adds keys on unlock, removes on lock.
    SSHAgent = {
      Enabled = "true"; # AuthSockOverride is written at activation (needs the runtime dir)
    };
    Browser = {
      Enabled = "true";
      UpdateBinaryPath = "false"; # the manifests below are Nix-managed; do not let it rewrite them
      SearchInAllDatabases = "true";
    };
  };
  iniCmds = lib.concatStrings (lib.mapAttrsToList (sec: kv:
    lib.concatStrings (lib.mapAttrsToList (k: v: ''
      run ${pkgs.crudini}/bin/crudini --set "${ini}" ${sec} ${k} "${v}"
    '') kv)) settings);

  py = pkgs.python3.withPackages (p: [ p.secretstorage ]);
  dots-secrets = pkgs.writeShellApplication {
    name = "dots-secrets";
    runtimeInputs = [ kp pkgs.openssh pkgs.coreutils pkgs.gnugrep pkgs.crudini pkgs.systemd pkgs.libnotify ];
    text = builtins.replaceStrings [ "@PY@" "@MIGRATE@" ] [ "${py}/bin/python3" "${./secrets/migrate-keyring.py}" ]
      (builtins.readFile ./secrets/dots-secrets.sh);
  };
in {
  home.packages = [
    dots-secrets
    pkgs.docker-credential-helpers # docker-credential-secretservice
    (pkgs.runCommand "git-credential-libsecret" { } ''
      mkdir -p $out/bin
      ln -s ${pkgs.gitFull}/bin/git-credential-libsecret $out/bin/git-credential-libsecret
    '')
  ];

  home.file = hostFile ".mozilla/native-messaging-hosts" ffHost
    // hostFile ".zen/native-messaging-hosts" ffHost
    // hostFile ".config/google-chrome/NativeMessagingHosts" crHost
    // hostFile ".config/BraveSoftware/Brave-Browser/NativeMessagingHosts" crHost
    // hostFile ".config/chromium/NativeMessagingHosts" crHost;

  home.activation.keepassxcIni = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run mkdir -p "$(dirname "${ini}")"
    [ -e "${ini}" ] || run touch "${ini}"
    ${iniCmds}
    # crudini cannot expand the runtime dir; write the real path.
    run ${pkgs.crudini}/bin/crudini --set "${ini}" SSHAgent AuthSockOverride "''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/ssh-agent.socket"
  '';
}
