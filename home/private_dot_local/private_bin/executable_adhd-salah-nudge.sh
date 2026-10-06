#!/usr/bin/env bash
# adhd-salah-nudge.sh PrayerName — fire the prayer reminder. Sends a PLAIN, non-blocking
# notification (no --wait/--action): the caelestia (quickshell) notifier was probed 2026-07-18
# and hangs on `notify-send --wait --action=...` for the full timeout without ever returning
# an action (exit=124 after 6s) — a blocking --wait here would wedge this transient systemd
# nudge unit forever. The reliable one-key answer is the picker keybind (Super+Shift+;), which
# does not depend on notification-action support; this notification is only a reminder.
# Streak-positive wording, never guilt.
set -uo pipefail
export PATH="/home/linuxbrew/.linuxbrew/bin:$HOME/.local/bin:$PATH"
name="${1:-Salah}"
notify-send "🕌 $name" "Iqamah time — log when you're back. (Super+Shift+; to log)" 2>/dev/null || true
