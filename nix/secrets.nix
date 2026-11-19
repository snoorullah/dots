{ config, pkgs, lib, ... }:
# Secret Service provider: gnome-keyring (KeePassXC removed 2026-11-20).
#
# gnome-keyring-daemon owns org.freedesktop.secrets; apps using libsecret
# (Chrome/Brave/VS Code/Slack encryption keys, docker-credential-secretservice,
# git-credential-libsecret) store there. It runs as the chezmoi user service
# gnome-keyring.service, started by Hyprland and enabled by the 24-systemd script.
#
# SSH keys are plain files in ~/.ssh, fed to ssh-agent.service (ssh-add / AddKeysToAgent);
# they are no longer injected from a vault on unlock. Browser logins live in Zen's own
# store (signon.rememberSignons = true in zen.nix).
{
  home.packages = [
    pkgs.docker-credential-helpers # docker-credential-secretservice
    (pkgs.runCommand "git-credential-libsecret" { } ''
      mkdir -p $out/bin
      ln -s ${pkgs.gitFull}/bin/git-credential-libsecret $out/bin/git-credential-libsecret
    '')
  ];
}
