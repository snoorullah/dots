{ pkgs, ... }:

# Native Hyprland config (home-manager's wayland.windowManager.hyprland module),
# re-expressing the INTENT of the live chezmoi/caelestia-era ~/.config/hypr/hyprland.lua
# — not a port of its `hl.*` Lua-DSL syntax. That DSL is this SAME home-manager
# module's own Lua-mode output (see `configType` below); we deliberately render
# classic hyprlang instead, so this config has zero runtime dependency on
# caelestia/quickshell.
#
# Judgment calls (see the PROGRESS/report notes for the full list):
#   - Dropped every caelestia-shell IPC bind/rule (Super+A leftbar toggle, the
#     `focus-panel` window rules, the quickshell/caelestia-clipboard layer
#     rules) — left a TODO where the leftbar toggle bind used to be.
#   - swayosd volume/brightness/caps binds use `bindl`/`bindle` (locked +
#     repeat) per the build spec, even though the live lua didn't mark them
#     locked — this is a deliberate fix so media keys work from the lock screen.
#   - The lua's `hl.curve({type="spring", ...})` "springy" easing has no
#     equivalent literal in classic hyprlang bezier curves; approximated with
#     the "snappy" cubic bezier for the windows/windowsOut animations.
#   - hypridle/hyprlock are configured via their own native home-manager
#     modules (translated from the live hypridle.conf/hyprlock.conf) rather
#     than raw file copies, so `services.hypridle.package = null` avoids a
#     double-start against the `hypridle` exec-once line below.
{
  wayland.windowManager.hyprland = {
    enable = true;

    # The NixOS module (`programs.hyprland.enable` in hosts/laptop/configuration.nix)
    # already installs the Hyprland binary + xdg-desktop-portal-hyprland at the
    # system level — null these out here per the module's own doc note, so
    # home-manager doesn't try to manage/duplicate them.
    package = null;
    portalPackage = null;

    # stateVersion 25.11 already defaults this to "hyprlang" (the module's
    # `configType` deprecation shim only flips to "lua" at stateVersion
    # >= 26.05) — pinned explicitly so a future stateVersion bump can't
    # silently switch the generated file format on us.
    configType = "hyprlang";

    settings = {
      "$mod" = "SUPER";

      monitor = ",preferred,auto,1";

      # NVIDIA env (RTX 4090, proprietary driver) — ported verbatim from
      # hyprland.lua's hl.env(...) calls / hypr/nvidia.conf.
      env = [
        "LIBVA_DRIVER_NAME,nvidia"
        "__GLX_VENDOR_LIBRARY_NAME,nvidia"
        "NVD_BACKEND,direct"
        "ELECTRON_OZONE_PLATFORM_HINT,auto"
      ];

      general = {
        gaps_in = 6;
        gaps_out = 3;
        border_size = 2;
        "col.active_border" = "rgb(bd93f9) rgb(ff79c6) 45deg";
        "col.inactive_border" = "rgb(232336)";
        layout = "dwindle";
        resize_on_border = true;
        allow_tearing = false;
      };

      decoration = {
        rounding = 12;
        dim_strength = 0.6;
        blur = {
          enabled = true;
          size = 5;
          passes = 2;
          new_optimizations = true;
          ignore_opacity = true;
        };
        shadow = {
          enabled = true;
          range = 14;
          color = "rgba(00000073)";
        };
        active_opacity = 0.82;
        inactive_opacity = 0.70;
      };

      animations = {
        enabled = true;
        bezier = [
          "smooth, 0.16, 1.0, 0.3, 1.0"
          "snappy, 0.05, 0.9, 0.1, 1.05"
        ];
        animation = [
          # "springy" (spring-type curve) has no classic-hyprlang equivalent —
          # approximated with "snappy" (judgment call, see header comment).
          "windows, 1, 6, snappy, popin 80%"
          "windowsOut, 1, 6, snappy, popin 80%"
          "fade, 1, 7, smooth"
          "workspaces, 1, 7, snappy, slide"
          "border, 1, 8, smooth"
          "layers, 1, 6, snappy, slide"
        ];
      };

      input = {
        kb_layout = "us";
        follow_mouse = 1;
        accel_profile = "flat";
      };

      misc = {
        disable_hyprland_logo = true;
        disable_splash_rendering = true;
        focus_on_activate = false;
      };

      dwindle = {
        preserve_split = true;
        force_split = 2;
      };

      cursor = {
        no_hardware_cursors = true; # avoids garbled/invisible cursor on nvidia
      };

      # ── Layer rules — real glass on the bar (compositor blur) ────────────
      layerrule = [
        "blur,waybar"
      ];

      # ── Window rules — workspace pinning + floats, ported 1:1 ────────────
      windowrulev2 = [
        "opaque,class:^([Kk]itty)$"

        "workspace 2 silent,class:^(zen-alpha|zen-browser|firefox|Firefox)$"
        "workspace 3 silent,class:^([Cc]ode|code-oss|Cursor)$"
        "workspace 4 silent,class:^([Ss]lack)$"
        "workspace 7 silent,class:^([Oo]bsidian)$"
        "workspace 8 silent,class:^([Ss]potify|YoutubeMusic|youtube-music)$"
        "float,class:^([Pp]avucontrol|[Nn]m-connection-editor|file-roller)$"
        "float,class:^(zen-tab-switcher)$"
        "center,class:^(zen-tab-switcher)$"

        # otter-launcher floating panel (stayfocused deliberately dropped —
        # the live config removed it too: it blocked Print-screenshot)
        "float,class:^(otter)$"
        "center,class:^(otter)$"
        "size 400 300,class:^(otter)$"
        "dimaround,class:^(otter)$"
        "rounding 5,class:^(otter)$"
        "opaque,class:^(otter)$"

        "float,class:^(wallpaper)$"
        "center,class:^(wallpaper)$"
        "size 1100 620,class:^(wallpaper)$"
        "rounding 5,class:^(wallpaper)$"

        "float,class:^(bluetuith)$"
        "center,class:^(bluetuith)$"
        "size 720 520,class:^(bluetuith)$"
        "rounding 5,class:^(bluetuith)$"

        "float,class:^(clipse)$"
        "center,class:^(clipse)$"
        "size 720 520,class:^(clipse)$"
        "rounding 5,class:^(clipse)$"

        "float,class:^(tasktui)$"
        "center,class:^(tasktui)$"
        "size 1100 720,class:^(tasktui)$"
        "rounding 5,class:^(tasktui)$"

        "float,class:^(salahpick)$"
        "center,class:^(salahpick)$"
        "size 560 320,class:^(salahpick)$"
        "rounding 5,class:^(salahpick)$"
      ];

      # ── Autostart — the minimal stack only (no caelestia/quickshell,
      # no pinned-app autostarts — those land with their own phases) ───────
      "exec-once" = [
        "waybar"
        "mako"
        "swayosd-server"
        "awww-daemon"
        # nixpkgs renamed the `swww` package to `awww` upstream (binaries
        # are now `awww`/`awww-daemon`, not `swww`/`swww-daemon`) — see
        # default.nix's package comment. TODO: point this at a real wallpaper.
        "awww img ~/Pictures/wallpaper.jpg"
        "hypridle"
        "nm-applet --indicator"
        # clipboard-history daemon — matches the live desktop's exec-once
        # (clipse -listen); cliphist is installed too as a fallback consumer
        # for `wl-paste --watch cliphist store` if clipse gets swapped out.
        "clipse -listen"
      ];

      bind = [
        "$mod, Return, exec, kitty"
        "$mod SHIFT, Q, killactive"
        "ALT, F4, killactive"

        # otter-launcher menus (kept identical to the live keybinds so muscle
        # memory carries over — otter-launcher itself is cargo-installed,
        # not packaged by Nix, see default.nix)
        "$mod, SPACE, exec, kitty --config ~/.config/kitty/otter.conf --class otter -e ~/.cargo/bin/otter-launcher app"
        "$mod, Tab, exec, kitty --config ~/.config/kitty/otter.conf --class otter -e ~/.cargo/bin/otter-launcher win"
        "$mod SHIFT, S, exec, kitty --config ~/.config/kitty/otter.conf --class otter -e ~/.cargo/bin/otter-launcher run"
        "$mod SHIFT, F, exec, kitty --config ~/.config/kitty/otter.conf --class otter -e ~/.cargo/bin/otter-launcher fb"
        "$mod, C, exec, kitty --class clipse --config ~/.config/kitty/otter.conf -e ~/.local/bin/clipse"
        "$mod SHIFT, B, exec, kitty --class bluetuith --config ~/.config/kitty/bluetuith.conf -e bluetuith"
        "$mod SHIFT, W, exec, kitty --class wallpaper --config ~/.config/kitty/otter.conf -e ~/.local/bin/wallpaper"
        ", Print, exec, ~/.local/bin/screenshot.sh region"
        "$mod, Print, exec, ~/.local/bin/screenshot.sh full"
        "$mod CTRL, S, exec, kitty --config ~/.config/kitty/otter.conf --class otter -e ~/.cargo/bin/otter-launcher sys"
        "$mod, slash, exec, kitty --config ~/.config/kitty/otter.conf --class otter -e ~/.cargo/bin/otter-launcher ws"
        "$mod, P, exec, kitty --config ~/.config/kitty/otter.conf --class otter -e ~/.cargo/bin/otter-launcher pj"
        "$mod, G, exec, kitty --config ~/.config/kitty/otter.conf --class otter -e ~/.cargo/bin/otter-launcher git"
        "$mod, T, exec, kitty --config ~/.config/kitty/otter.conf --class otter -e ~/.cargo/bin/otter-launcher tm"
        "$mod SHIFT, O, exec, kitty --config ~/.config/kitty/otter.conf --class otter -e ~/.cargo/bin/otter-launcher bm"
        "$mod, N, exec, kitty --config ~/.config/kitty/otter.conf --class otter -e ~/.cargo/bin/otter-launcher ob"
        "$mod, comma, exec, kitty --config ~/.config/kitty/otter.conf --class otter -e ~/.cargo/bin/otter-launcher zt"
        "$mod, M, exec, kitty --config ~/.config/kitty/otter.conf --class otter -e ~/.cargo/bin/otter-launcher md"
        "$mod SHIFT, M, exec, kitty --config ~/.config/kitty/otter.conf --class otter -e ~/.cargo/bin/otter-launcher ym"
        "$mod SHIFT, E, exec, kitty --config ~/.config/kitty/otter.conf --class otter -e ~/.cargo/bin/otter-launcher pw"

        # ADHD engine (kept 1:1 — same graceful-failure contract as the
        # scripts that ship in Phase 5: the bind exists, the script arrives
        # later, and every script here already no-ops cleanly when missing)
        "$mod SHIFT, A, exec, ~/.local/bin/adhd-capture.sh"
        "$mod SHIFT, X, exec, ~/.local/bin/adhd-focus.sh status"
        "$mod SHIFT, Return, exec, kitty --class tasktui --config ~/.config/kitty/tasktui.conf -e ~/.local/bin/tw-tui"
        "$mod SHIFT, P, exec, ~/.local/bin/adhd-break.sh"
        "$mod SHIFT, semicolon, exec, kitty --class salahpick --config ~/.config/kitty/otter.conf -e ~/.local/bin/adhd-salah-pick.sh"

        # TODO(phase5): non-caelestia clock-in / "chasing" panel equivalent.
        # DROPPED: $mod+A -> hl.dsp.exec_cmd(cs .. " ipc call leftbar toggle")
        # (caelestia-shell IPC — not available without caelestia/quickshell).

        "$mod, Escape, exec, hyprlock"

        # Focus (vim + arrows)
        "$mod, H, movefocus, l"
        "$mod, J, movefocus, d"
        "$mod, K, movefocus, u"
        "$mod, L, movefocus, r"
        "$mod, left, movefocus, l"
        "$mod, down, movefocus, d"
        "$mod, up, movefocus, u"
        "$mod, right, movefocus, r"

        # Move window
        "$mod SHIFT, H, movewindow, l"
        "$mod SHIFT, J, movewindow, d"
        "$mod SHIFT, K, movewindow, u"
        "$mod SHIFT, L, movewindow, r"

        # Layout
        "$mod, B, layoutmsg, preselect r"
        "$mod, V, layoutmsg, preselect d"
        "$mod, F, fullscreen, 0"
        "$mod, E, layoutmsg, togglesplit"
        "$mod SHIFT, space, togglefloating"
        "$mod, S, togglegroup"
        "$mod CTRL, H, changegroupactive, b"
        "$mod CTRL, L, changegroupactive, f"

        # Workspaces 1-10 (focus) — "0" = ws 10
        "$mod, 1, workspace, 1"
        "$mod, 2, workspace, 2"
        "$mod, 3, workspace, 3"
        "$mod, 4, workspace, 4"
        "$mod, 5, workspace, 5"
        "$mod, 6, workspace, 6"
        "$mod, 7, workspace, 7"
        "$mod, 8, workspace, 8"
        "$mod, 9, workspace, 9"
        "$mod, 0, workspace, 10"

        # Workspaces 1-10 (move window to)
        "$mod SHIFT, 1, movetoworkspace, 1"
        "$mod SHIFT, 2, movetoworkspace, 2"
        "$mod SHIFT, 3, movetoworkspace, 3"
        "$mod SHIFT, 4, movetoworkspace, 4"
        "$mod SHIFT, 5, movetoworkspace, 5"
        "$mod SHIFT, 6, movetoworkspace, 6"
        "$mod SHIFT, 7, movetoworkspace, 7"
        "$mod SHIFT, 8, movetoworkspace, 8"
        "$mod SHIFT, 9, movetoworkspace, 9"
        "$mod SHIFT, 0, movetoworkspace, 10"

        "$mod, mouse_down, workspace, e+1"
        "$mod, mouse_up, workspace, e-1"

        # System
        "$mod SHIFT, C, exec, hyprctl reload"
        "$mod SHIFT, R, exec, hyprctl reload"
        "$mod, Delete, exit"
        "$mod, I, exec, killall -SIGUSR1 waybar" # toggle bar (zen)

        # Resize submap
        "$mod, R, submap, resize"
      ];

      bindm = [
        "$mod, mouse:272, movewindow"
        "$mod, mouse:273, resizewindow"
      ];

      # Media / lock-screen keys — bindl (locked, works on the lockscreen)
      # and bindle (locked + repeats on hold). The live lua did NOT mark
      # volume/brightness/caps locked; this build deliberately does, so they
      # work while hyprlock is up (judgment call, see header comment).
      bindl = [
        ", XF86AudioMicMute, exec, pactl set-source-mute @DEFAULT_SOURCE@ toggle"
        ", XF86AudioPlay, exec, playerctl play-pause"
        ", XF86AudioNext, exec, playerctl next"
        ", XF86AudioPrev, exec, playerctl previous"
        ", Caps_Lock, exec, swayosd-client --caps-lock"
      ];

      bindle = [
        ", XF86AudioRaiseVolume, exec, swayosd-client --output-volume raise"
        ", XF86AudioLowerVolume, exec, swayosd-client --output-volume lower"
        ", XF86AudioMute, exec, swayosd-client --output-volume mute-toggle"
        ", XF86MonBrightnessUp, exec, swayosd-client --brightness raise"
        ", XF86MonBrightnessDown, exec, swayosd-client --brightness lower"
      ];
    };

    submaps.resize.settings = {
      binde = [
        ", H, resizeactive, -20 0"
        ", J, resizeactive, 0 20"
        ", K, resizeactive, 0 -20"
        ", L, resizeactive, 20 0"
      ];
      bind = [
        ", Return, submap, reset"
        ", escape, submap, reset"
      ];
    };
  };

  # ── hypridle — idle -> lock / screen-off ──────────────────────────────
  # Translated from the live ~/.config/hypr/hypridle.conf.
  # package = null: hyprland's own exec-once starts the binary above, so we
  # don't also want home-manager's systemd --user unit double-starting it.
  # `hypridle` itself is still installed via home.packages in default.nix.
  services.hypridle = {
    enable = true;
    package = null;
    settings = {
      general = {
        lock_cmd = "pidof hyprlock || hyprlock";
        before_sleep_cmd = "loginctl lock-session";
        after_sleep_cmd = "hyprctl dispatch dpms on";
        # TODO(phase5): ~/.local/bin/adhd-break-end.sh doesn't exist yet —
        # unlock will just no-op until that script lands.
        unlock_cmd = "~/.local/bin/adhd-break-end.sh";
      };
      listener = [
        {
          timeout = 600;
          on-timeout = "loginctl lock-session";
        }
        {
          timeout = 720;
          on-timeout = "hyprctl dispatch dpms off";
          on-resume = "hyprctl dispatch dpms on";
        }
      ];
    };
  };

  # ── hyprlock — Dracula lock screen ─────────────────────────────────────
  # Translated from the live ~/.config/hypr/hyprlock.conf.
  programs.hyprlock = {
    enable = true;
    settings = {
      general = {
        hide_cursor = true;
        grace = 0;
        ignore_empty_input = true;
      };

      background = [
        {
          monitor = "";
          path = "screenshot";
          blur_passes = 3;
          blur_size = 8;
          noise = 0.012;
          contrast = 0.9;
          brightness = 0.7;
          vibrancy = 0.18;
          color = "rgb(1a1a2e)";
        }
      ];

      label = [
        {
          monitor = "";
          text = ''cmd[update:1000] echo "$(date '+%H:%M')"'';
          color = "rgb(f8f8f2)";
          font_size = 96;
          font_family = "JetBrainsMono Nerd Font";
          position = "0, 170";
          halign = "center";
          valign = "center";
        }
        {
          monitor = "";
          text = ''cmd[update:60000] echo "$(date '+%A, %d %B')"'';
          color = "rgb(8be9fd)";
          font_size = 18;
          font_family = "JetBrainsMono Nerd Font";
          position = "0, 95";
          halign = "center";
          valign = "center";
        }
        {
          monitor = "";
          text = "what are you chasing?";
          color = "rgb(585880)";
          font_size = 13;
          font_family = "JetBrainsMono Nerd Font";
          position = "0, -10";
          halign = "center";
          valign = "center";
        }
      ];

      input-field = [
        {
          monitor = "";
          size = "300, 52";
          outline_thickness = 2;
          dots_size = 0.28;
          dots_spacing = 0.3;
          dots_center = true;
          rounding = 16;
          outer_color = "rgb(bd93f9)";
          inner_color = "rgb(232336)";
          font_color = "rgb(f8f8f2)";
          font_family = "JetBrainsMono Nerd Font";
          placeholder_text = ''<span foreground="##585880">password</span>'';
          check_color = "rgb(50fa7b)";
          fail_color = "rgb(ff4d4d)";
          fail_text = ''<span foreground="##ff4d4d">$FAIL ($ATTEMPTS)</span>'';
          fade_on_empty = false;
          position = "0, -65";
          halign = "center";
          valign = "center";
        }
      ];
    };
  };
}
