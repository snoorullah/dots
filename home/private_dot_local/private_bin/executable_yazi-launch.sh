#!/usr/bin/env bash
# yazi-launch.sh — launch yazi with the nix profile on PATH so yazi itself and
# its preview helpers (ffmpegthumbnailer, unar, fd, file) resolve. Hyprland's
# exec PATH does NOT include ~/.nix-profile/bin, so a bare `yazi` would fail.
export PATH="$HOME/.nix-profile/bin:$PATH"
exec yazi "$@"
