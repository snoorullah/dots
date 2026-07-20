{ pkgs, ... }:

# Phase 5 — the time-tracking prosthetic: taskwarrior3 + timewarrior +
# ActivityWatch (aw-server-rust + awatcher thin client) + the `timetrack`
# Python rollup/note/sync CLI + the salah/break/focus bash layer + their
# systemd --user units.
#
# ── Path surgery (the crux) ─────────────────────────────────────────────
# The live (non-Nix) install hardcodes /home/linuxbrew/.linuxbrew/bin/task and
# /usr/bin/timew everywhere. Every file under ./timetrack/files/ has been
# patched to the bare command names `task` / `timew`, resolved via:
#   - the `timetrack` runner below (writeShellApplication + runtimeInputs =
#     guaranteed PATH regardless of ambient systemd-user environment), for
#     the Python CLI's rollup/note/sync subcommands, and
#   - plain `home.packages` (taskwarrior3, timewarrior, python3 env, rofi),
#     for the adhd-*.sh scripts, the waybar bar scripts, and the taskwarrior
#     hook, all of which run under the normal user session PATH.
#
# ── DROPPED (quickshell/eww/caelestia-bound — the laptop has no quickshell) ──
#   scripts:  adhd-block-exec.sh, adhd-task-cmd.sh, adhd-start.sh,
#             adhd-tasks-export.sh, adhd-wall-exec.sh, qs-*.sh, eww-*.sh
#   systemd:  adhd-block.path/.service, adhd-task-cmd.path/.service,
#             adhd-wall.path/.service
# adhd-salah-nudge.sh was KEPT: it already used plain notify-send (never
# caelestia IPC), so only its PATH line needed the linuxbrew removal.
#
# ── Manual post-install steps (cannot be done declaratively) ────────────
#   - clone the private DATA_REPO (shaiknoorullah/timetrack-data) to
#     ~/.local/share/timetrack/data-repo — `timetrack sync` no-ops (returns
#     False, non-fatal) until repo/.git exists there.
#   - ~/.local/share/timetrack/events/ is mkdir'd by timetrack-logind.py itself.
#   - ~/powerhouse/timetrack/daily is mkdir'd by note.write() itself.
#   - config.py's HABIT_SPRINT_START is None; set a real date to start the
#     "day X of 14" countdown in the note header (patch the copy under
#     ./timetrack/files/timetrack-lib/timetrack/config.py).
#   - install aw-watcher-web (browser extension) if per-domain web rollup is
#     wanted; the rollup auto-detects any bucket with "web" in its name and
#     stays inert (no web line in the note) until then.
let
  pythonEnv = pkgs.python3.withPackages (ps: with ps; [ sqlite-utils requests jeepney ]);

  # `timetrack` runner: PYTHONPATH points at the patched package below;
  # runtimeInputs guarantee python/task/timew/git are on PATH inside the
  # wrapper regardless of what systemd --user's ambient PATH looks like.
  timetrack = pkgs.writeShellApplication {
    name = "timetrack";
    runtimeInputs = [ pythonEnv pkgs.taskwarrior3 pkgs.timewarrior pkgs.git ];
    text = ''
      export PYTHONPATH="${./timetrack/files/timetrack-lib}:''${PYTHONPATH:-}"
      exec python -m timetrack "$@"
    '';
  };
in
{
  home.packages = [
    pkgs.taskwarrior3    # provides `task` 3.4.2 — go-task deliberately NOT installed globally (see dev.nix)
    pkgs.timewarrior     # provides `timew`
    pkgs.aw-server-rust  # provides `aw-server` (binary name != attribute name — see report)
    pkgs.awatcher        # provides `awatcher`; default cargo features = thin client reporting to an
                         # EXTERNAL aw-server (NOT the "bundle" feature with its own embedded server —
                         # verified from upstream Cargo.toml: default = ["gnome","kwin_window"], "bundle"
                         # is opt-in only). Safe to run alongside the separate aw-server service below.
    pkgs.rofi            # adhd-capture.sh's capture-inbox menu; rofi-wayland was merged into rofi
                         # upstream, so this one package covers Wayland/Hyprland already.
    pythonEnv            # also puts a bare `python3` on PATH, for the taskwarrior hook + adhd-prayer-times.sh
    timetrack
  ];

  # ── Keep scripts (patched, path-surgery'd) → ~/.local/bin ──────────────
  home.file = {
    ".local/bin/adhd-break.sh" = {
      source = ./timetrack/files/bin/adhd-break.sh;
      executable = true;
    };
    ".local/bin/adhd-break-end.sh" = {
      source = ./timetrack/files/bin/adhd-break-end.sh;
      executable = true;
    };
    ".local/bin/adhd-focus.sh" = {
      source = ./timetrack/files/bin/adhd-focus.sh;
      executable = true;
    };
    ".local/bin/adhd-capture.sh" = {
      source = ./timetrack/files/bin/adhd-capture.sh;
      executable = true;
    };
    ".local/bin/adhd-salah-pick.sh" = {
      source = ./timetrack/files/bin/adhd-salah-pick.sh;
      executable = true;
    };
    ".local/bin/adhd-prayer-times.sh" = {
      source = ./timetrack/files/bin/adhd-prayer-times.sh;
      executable = true;
    };
    ".local/bin/adhd-salah-schedule.sh" = {
      source = ./timetrack/files/bin/adhd-salah-schedule.sh;
      executable = true;
    };
    ".local/bin/adhd-salah-tasks.sh" = {
      source = ./timetrack/files/bin/adhd-salah-tasks.sh;
      executable = true;
    };
    ".local/bin/adhd-salah-nudge.sh" = {
      source = ./timetrack/files/bin/adhd-salah-nudge.sh;
      executable = true;
    };

    ".taskrc".source = ./timetrack/files/task/taskrc;
    ".task/hooks/on-modify.timewarrior" = {
      source = ./timetrack/files/task/on-modify.timewarrior;
      executable = true;
    };
  };

  xdg.configFile = {
    "timewarrior/timewarrior.cfg".source = ./timetrack/files/timewarrior/timewarrior.cfg;
    # live ~/.config/timewarrior/extensions/ is empty (0 files) — nothing to port.
    "timetrack/categories.toml".source = ./timetrack/files/timetrack-config/categories.toml;
    "awatcher/config.toml".source = ./timetrack/files/awatcher/config.toml;
  };

  # ── systemd --user services ─────────────────────────────────────────────
  systemd.user.services = {
    aw-server = {
      Unit = {
        Description = "ActivityWatch server (aw-server-rust)";
        After = [ "default.target" ];
      };
      Service = {
        Type = "simple";
        ExecStart = "${pkgs.aw-server-rust}/bin/aw-server";
        Restart = "on-failure";
        RestartSec = 5;
      };
      Install.WantedBy = [ "default.target" ];
    };

    awatcher = {
      Unit = {
        Description = "ActivityWatch awatcher (window + AFK, Wayland)";
        Requires = [ "aw-server.service" ];
        After = [ "aw-server.service" ];
      };
      Service = {
        Type = "simple";
        ExecStart = "${pkgs.awatcher}/bin/awatcher";
        Restart = "on-failure";
        RestartSec = 5;
      };
      Install.WantedBy = [ "default.target" ];
    };

    timetrack-logind = {
      Unit = {
        Description = "timetrack — systemd-logind session/lock/suspend capture";
        After = [ "default.target" ];
      };
      Service = {
        Type = "simple";
        # run straight from the nix store under the python env — no separate
        # ~/.local/bin install needed (unlike the writeShellApplication runner
        # above, this is a single python script, not something a user invokes
        # interactively).
        ExecStart = "${pythonEnv}/bin/python3 ${./timetrack/files/logind/timetrack-logind.py}";
        Restart = "on-failure";
        RestartSec = 5;
      };
      Install.WantedBy = [ "default.target" ];
    };

    timetrack-rollup = {
      Unit.Description = "timetrack rollup (refresh local observe DB + Obsidian note)";
      Service = {
        Type = "oneshot";
        ExecStart = "${timetrack}/bin/timetrack rollup";
        ExecStartPost = "${timetrack}/bin/timetrack note";
      };
    };

    timetrack-sync = {
      Unit.Description = "timetrack git backup (sqlite-diffable dump -> private repo)";
      Service = {
        Type = "oneshot";
        ExecStart = "${timetrack}/bin/timetrack sync";
      };
    };

    adhd-prayer-times = {
      Unit.Description = "Regenerate ADHD-OS prayer times (offline, Hyderabad/Hanafi)";
      Service = {
        Type = "oneshot";
        ExecStart = "%h/.local/bin/adhd-prayer-times.sh";
      };
    };

    adhd-salah-schedule = {
      Unit.Description = "Schedule today's salah nudges";
      Service = {
        Type = "oneshot";
        ExecStart = "%h/.local/bin/adhd-salah-schedule.sh";
      };
    };

    adhd-salah-tasks = {
      Unit.Description = "Generate today's salah tasks from prayer-times.conf";
      Service = {
        Type = "oneshot";
        ExecStart = "%h/.local/bin/adhd-salah-tasks.sh";
      };
    };
  };

  # ── systemd --user timers ───────────────────────────────────────────────
  systemd.user.timers = {
    timetrack-rollup = {
      Unit.Description = "timetrack rollup every 30 min (<=30min local freshness)";
      Timer = {
        OnCalendar = "*:0/30";
        OnStartupSec = 60;
        Persistent = true;
      };
      Install.WantedBy = [ "timers.target" ];
    };

    timetrack-sync = {
      Unit.Description = "timetrack hourly backup (<=1h backup freshness)";
      Timer = {
        OnCalendar = "*:05";
        OnStartupSec = 120;
        Persistent = true;
      };
      Install.WantedBy = [ "timers.target" ];
    };

    adhd-prayer-times = {
      Unit.Description = "Daily refresh of ADHD-OS prayer times";
      Timer = {
        OnCalendar = "*-*-* 00:05:00";
        OnBootSec = "2min";
        Persistent = true;
      };
      Install.WantedBy = [ "timers.target" ];
    };

    adhd-salah-schedule = {
      Unit.Description = "Daily salah-nudge scheduling (+ at login)";
      Timer = {
        OnCalendar = "*-*-* 00:12:00";
        OnStartupSec = 45;
        Persistent = true;
      };
      Install.WantedBy = [ "timers.target" ];
    };

    adhd-salah-tasks = {
      Unit.Description = "Daily salah-task generation (+ at login)";
      Timer = {
        OnCalendar = "*-*-* 00:10:00";
        OnStartupSec = 30;
        Persistent = true;
      };
      Install.WantedBy = [ "timers.target" ];
    };
  };
}
