{ pkgs, ... }:

# Phase 4 — shell environment: zsh + prompt + CLI ergonomics + git identity.
# Personal machine → personal git identity only.
{
  programs.zsh = {
    enable = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
    enableCompletion = true;
    history = {
      size = 100000;
      save = 100000;
      ignoreDups = true;
      share = true;
    };
    shellAliases = {
      ll = "eza -la --git --icons";
      ls = "eza --icons";
      cat = "bat";
      lg = "lazygit";
    };
  };

  programs.starship.enable = true;
  programs.fzf.enable = true;
  programs.zoxide.enable = true;
  programs.bat.enable = true;

  programs.tmux = {
    enable = true;
    keyMode = "vi";
    mouse = true;
    baseIndex = 1;
    historyLimit = 100000;
    terminal = "tmux-256color";
  };

  programs.git = {
    enable = true;
    settings = {
      user.name = "Shaik Noorullah";
      user.email = "shaiknooru247@gmail.com";   # personal identity
      init.defaultBranch = "main";
      pull.rebase = true;
      push.autoSetupRemote = true;
    };
  };

  programs.delta = {
    enable = true;
    enableGitIntegration = true;
  };

  home.packages = with pkgs; [
    eza
    fd
    ripgrep
    dust
    bottom
    curl
    wget
    unzip
  ];
}
