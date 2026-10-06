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
    ln -s ${zen}/bin/zen-beta $out/bin/zen
    ln -s ${zen}/bin/zen-beta $out/bin/zen-browser
  '';
  zen = inputs.zen-browser.packages.${pkgs.system}.default;
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
    (lib.hiPrio taskwarrior3) timewarrior taskwarrior-tui aw-server-rust awatcher dotsAdhanPython
    zsh antidote starship zoxide fzf eza bat ripgrep jq gh neovim git chezmoi
    tmux inputs.herdr.packages.${pkgs.system}.default
    kubectl k9s openssh
    nerd-fonts.jetbrains-mono nerd-fonts.fantasque-sans-mono victor-mono material-symbols noto-fonts noto-fonts-color-emoji
    kdePackages.breeze kdePackages.breeze-icons

    # --- owner picks (addendum) ---
    # browsers / chat / mail
    zen compat google-chrome brotab slack teams-for-linux thunderbird
    # CLI utilities
    p7zip ast-grep buf doxygen ffmpeg glslang (lib.lowPrio go-task) imagemagick ipmitool lm_sensors pandoc
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
    bun check-jsonschema clang cmake cudaPackages.cudatoolkit deno go golangci-lint gopls go-tools llvm
    lua luarocks (lib.lowPrio luajit) meson ninja nodejs_24 pipx pnpm ruff rustup shellcheck shfmt uv yamllint
    # media
    blender loupe mpv swappy
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
    claude-code codex ollama-cuda
  ];
}
