{ pkgs, ... }:

# Phase 3 — the three editors: VS Code, Zed, Neovim.
# Kept intentionally light: VS Code + Zed manage their own settings/extensions
# in-app (mutable); Neovim is a sane starter with LSP prerequisites. The user's
# own nvim config migrates later (spec §11).
{
  programs.vscode = {
    enable = true;
    package = pkgs.vscode;           # unfree; allowUnfree on at system level
    # Extensions/settings left mutable — install in-app. Nix-managed extensions
    # can be layered in later once the working set is known.
  };

  programs.neovim = {
    enable = true;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;
    withNodeJs = true;               # for LSP servers that ship as npm packages
    withPython3 = true;
    withRuby = false;                # adopt the new HM default (no ruby provider)
  };

  home.packages = with pkgs; [
    zed-editor                       # Zed has no stable HM module — install the pkg
  ];
}
