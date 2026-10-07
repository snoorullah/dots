{ config, pkgs, lib, gpu, inputs, ... }:
let
  glhost = inputs.nix-gl-host.packages.${pkgs.system}.default;
  wrapNvidia = drv: pkgs.symlinkJoin {
    name = "${drv.name}-nixglhost"; paths = [ drv ]; nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''for b in $out/bin/*; do t=$(readlink -f "$b"); rm "$b"; makeWrapper ${glhost}/bin/nixglhost "$b" --add-flags "$t"; done'';
  };
  # GPU-dependent GL wrapper (spec D2): nvidia → nix-gl-host, mesa → nixGL, nixos → none.
  gl = drv:
    if gpu == "nvidia" then wrapNvidia drv
    else if gpu == "mesa" then config.lib.nixGL.wrap drv
    else drv;
  # Compat names: nixpkgs renamed swww → awww (live scripts/hypr config still call swww*), and the
  # zen flake ships `zen-beta` (live config launches `zen-browser`). Remove once the configs migrate.
  compat = pkgs.runCommand "dots-compat-links" { } ''
    mkdir -p $out/bin
    ln -s ${pkgs.awww}/bin/awww $out/bin/swww
    ln -s ${pkgs.awww}/bin/awww-daemon $out/bin/swww-daemon
    ln -s ${pkgs.go-task}/bin/task $out/bin/go-task
    ln -s ${zen}/bin/zen-beta $out/bin/zen
    ln -s ${zen}/bin/zen-beta $out/bin/zen-browser
  '';
  # Browser policies (spec D3, R11/R17): aw-watcher-web force-install for both browsers. The private-browsing
  # keys come from /etc/firefox/policies/policies.json, which applies to stock Firefox only (live Zen has
  # no policies), so they go to aether only.
  awWatcher.ExtensionSettings."{ef87d84c-2127-493f-b952-5b4e744245bc}" = {
    installation_mode = "force_installed";
    install_url = "https://addons.mozilla.org/firefox/downloads/latest/aw-watcher-web/latest.xpi";
  };
  zen = gl (inputs.zen-browser.packages.${pkgs.system}.default.override { extraPolicies = awWatcher; });
  aether = gl (pkgs.aether.override {
    extraPolicies = awWatcher // { DisablePrivateBrowsing = true; PrivateBrowsingModeAvailability = 1; };
  });
in {
  home.stateVersion = "25.11";
  programs.home-manager.enable = true;
  targets.genericLinux.enable = gpu != "nixos";
  targets.genericLinux.nixGL = lib.mkIf (gpu == "mesa") { packages = inputs.nixgl.packages; defaultWrapper = "mesa"; };
  fonts.fontconfig.enable = true;
  home.packages = with pkgs; [
    # --- desktop / session / scripts ---
    (gl hyprland)
    hypridle hyprpolkitagent xdg-desktop-portal-hyprland hyprpicker
    waybar swaynotificationcenter swayosd awww (gl ghostty) chafa otter-launcher clipse yazi ffmpegthumbnailer unar file fd
    grim slurp wl-clipboard playerctl brightnessctl networkmanagerapplet bluetuith libnotify papirus-icon-theme
    (lib.hiPrio taskwarrior3) timewarrior taskwarrior-tui aw-server-rust awatcher dotsAdhanPython timetrack
    zsh antidote starship zoxide fzf eza bat ripgrep jq gh neovim git chezmoi
    tmux dotsTmuxPluginFarm inputs.herdr.packages.${pkgs.system}.default
    kubectl k9s openssh
    nerd-fonts.jetbrains-mono nerd-fonts.fantasque-sans-mono victor-mono material-symbols noto-fonts noto-fonts-color-emoji
    kdePackages.breeze kdePackages.breeze-icons

    # --- owner picks (addendum) ---
    # browsers / chat / mail
    zen aether compat (gl google-chrome) brotab slack teams-for-linux thunderbird
    (gl legcord) (gl beeper) (gl telegram-desktop) zapzap nchat tg
    (weechat.override { configure = { availablePlugins, ... }: { scripts = [ weechatScripts.wee-slack ]; }; })
    # calendar / tasks / sync
    gcalcli gnome-calendar khal tasksh python3Packages.bugwarrior taskchampion-sync-server
    kdePackages.kdeconnect-kde hypr-kdeconnect-fix hyprcapture argonaut
    # containers
    buildah skopeo dive
    # CLI utilities
    p7zip ast-grep buf doxygen ffmpeg glslang imagemagick ipmitool lm_sensors pandoc
    qalculate-gtk restic yt-dlp zip unzip
    # desktop
    kdePackages.qtstyleplugin-kvantum pavucontrol kdePackages.qt6ct yad
    # editors
    drawio obsidian vscode
    # git
    delta lazygit lefthook
    # kubernetes / cloud / IaC
    actionlint ansible ansible-lint awscli2 cilium-cli crane crossplane-cli dbmate devpod distrobox
    docker-client docker-compose kubernetes-helm kapp kbld kcl kind kubeconform kubectx kustomize
    lens minio-client molecule packer postgresql powershell qemu redis sqlite stern talhelper talosctl terraform
    # languages & toolchains
    bun check-jsonschema clang cmake deno go golangci-lint gopls go-tools llvm
    lua luarocks (lib.lowPrio luajit) meson ninja nodejs_24 pipx pnpm ruff rustup shellcheck shfmt uv yamllint
    # media
    (gl blender) loupe (gl mpv)
    (gl obs-studio) (gl kdePackages.kdenlive) (gl krita) (gl gimp3) (gl inkscape) (gl handbrake)
    font-manager
    # office
    hoppscotch libreoffice-fresh
    # secrets
    age cosign gnupg vault keepassxc kubeseal seahorse gnome-keyring sops step-cli
    # security
    binwalk conftest hadolint syft testdisk tflint trivy
    # ssh & network
    cloudflared iperf3 mosh nmap nettools sshpass tailscale traceroute whois wireguard-tools wireshark
    # TUIs
    btop cava duf dust fastfetch lazydocker
    # AI
    claude-code codex
  ] ++ (if gpu == "nvidia" then [ pkgs.cudaPackages.cudatoolkit pkgs.ollama-cuda ] else [ pkgs.ollama ]);
}
