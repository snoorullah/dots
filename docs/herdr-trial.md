# Herdr trial (7 days) — keep exactly one multiplexer afterwards

Switch:  `sed -i 's/multiplexer = "tmux"/multiplexer = "herdr"/' ~/.config/chezmoi/chezmoi.toml && chezmoi apply`
Back:    `sed -i 's/multiplexer = "herdr"/multiplexer = "tmux"/' ~/.config/chezmoi/chezmoi.toml && chezmoi apply`
(`promptChoiceOnce` keeps the stored value, so `chezmoi init` will not reset it.)

| # | Criterion | Pass if | Result |
|---|---|---|---|
| 1 | vi copy mode + yank | search, select, yank to wl-clipboard work from keyboard | |
| 2 | Claude agents state | sidebar shows working/blocked/idle correctly for 3+ concurrent Claude Code panes | |
| 3 | Restore | after reboot, agents resume with their original flags (incl. `--dangerously-skip-permissions`, `-c`) | |
| 4 | Notifications | a blocked agent produces a SwayNC toast within 10 s | |
| 5 | Popups | pass-menu and ssh-menu work from prefix keys | |
| 6 | nvim | working without tmux-config's "hide status when nvim focused" is acceptable | |
| 7 | Memory | `ps -o rss= -C herdr` with 6 agents ≤ 200 MB | |
| 8 | Stability | no crash in `journalctl --user -u herdr` over 7 days | |

Decision: Herdr wins only if 1–5 and 8 pass. Record the decision and date here, then run Task 12.

## Notes for the trial

- Server unit: `systemctl --user enable --now herdr.service` (runs `herdr server`, the headless server; the
  client attaches with plain `herdr`). The tmux unit is not deployed while `multiplexer = "herdr"`.
- Config: `~/.config/herdr/config.toml` (chezmoi-rendered). Validate with `herdr config check`; reload the
  running server with `herdr server reload-config`.
- Prefix is `ctrl+space` (same as tmux-config). `prefix+p` is bound to the pass popup and `prefix+S` to the SSH
  key popup; check with `prefix+?` that `prefix+p` (Herdr's default previous-tab) now opens the popup. If not,
  rebind `previous_tab` in `[keys]`.
- Toasts: `[ui.toast] delivery = "system"` sends background notifications through the OS service (SwayNC).
- The shared scripts (pass-menu, ssh-menu, task-status, git-status, ssh-askpass) live in `~/.config/dots-mux`
  under both multiplexers. `claude-notify.sh` stays under `~/.config/tmux/scripts` (tmux only); Herdr does its own
  agent notifications.
