# dots-ops — automated system maintenance (design)

Date: 2026-10-07 · Repo: `dots` (branch `consolidate`, second plan after the consolidation plan)
Owner: Shaik Noorullah · Status: approved in conversation section by section; written for review.

## Goal

Keep every dots machine **up to date, secure, and healthy without babysitting**: OS and package
upgrades, security, firmware, disk, performance modes, network, containers, Kubernetes clusters
and backups — some on schedules, some on triggers, all reporting through desktop notifications,
risky actions waiting for the owner's click.

## Decisions (owner, 2026-10-07)

| # | Decision | Value |
|---|---|---|
| O1 | Autonomy | **Tiered**: safe actions run automatically; risky ones (full upgrades, kernel/driver, reboots, firmware, volume pruning, restores, retention beyond policy) wait for Approve. |
| O2 | Notifications | **Desktop only**: SwayNC notifications with action buttons + a Waybar health module + `dots-ops status` TUI. Nothing leaves the machine. |
| O3 | Heavy-job window | **When idle**: locked/idle ≥ 15 min **and** on AC; nightly fallback for days that never idle; never on battery or during active work. |
| O4 | Extra scope | Backups (restic), Kubernetes clusters, firmware, firewall + SSH hardening — all in. |
| O5 | Engine | **A**: systemd units + small shared bash library. No new daemon. **topgrade dropped** (owner, 2026-10-07): it refuses to run as root and would upgrade pinned tools; system upgrades use each family's native command, pinned tools move only through `pins-check` bump PRs. |
| O6 | Backup destination | Configurable: `RESTIC_REPOSITORY` + password from chezmoi-encrypted secrets (local disk, NAS or S3/MinIO decided by the owner later). |

Constraints inherited from the consolidation design: identical on every distro (Arch, Ubuntu,
Debian, Fedora/RHEL, NixOS); chezmoi owns files, Nix owns tools; minimal.

## Architecture

```
 triggers ──► dots-ops@<job>.service ──► job script ──► lib.sh ──► state/log ──► notify / ask
 (timer,         (user or system,          (sources        │                       │
  path, udev,     one template)             lib.sh)        ▼                       ▼
  idle target)                                    root: /var/lib/dots-ops/*.json   SwayNC (buttons)
                                                    └─► dots-ops-relay.path (user) ┘   Waybar module
                                                                                        dots-ops status (fzf TUI)
 Approve ─► dots-ops-run <job> <action>   (root actions via one narrow sudo rule)
```

### Engine units

| Unit | Responsibility | Interface |
|---|---|---|
| `lib.sh` (`~/.local/lib/dots-ops/lib.sh`, ~150 lines) | shared functions | `ops_log job level msg` → JSON line in `~/.local/state/dots-ops/log.jsonl`; `ops_state job ok|warn|fail summary` → `state/<job>.json`; `ops_notify urgency title body`; `ops_ask job question action` → `pending/<job>.json` + SwayNC Approve/Skip/Snooze 1d (24 h expiry → Skip, re-asked next run); `ops_idle_ok` (idle ≥ N min AND on AC); `ops_lock job` (flock); `ops_dry` (honours `DOTS_OPS_DRY_RUN=1`) |
| `dots-ops@.service` (user + system template) | run one job with timeout + lock | `ExecStart=dots-ops-job %i`; `TimeoutStartSec` per job (upgrades 2 h, others 10 min) |
| `dots-ops-relay.path/.service` (user) | turn root state files into user state + notifications | watches `/var/lib/dots-ops/` |
| `dots-ops-idle.target` | pulled by hypridle on idle; wants all due heavy jobs | jobs re-check `ops_idle_ok` and exit early if no longer allowed |
| `dots-ops-run` + `/etc/sudoers.d/dots-ops` | execute an approved action | sudo rule allows only `dots-ops-run <job> <action>` for the owner |
| `dots-ops status` (fzf TUI) | list jobs, last run, pending approvals, logs; approve / run now / snooze | reads state/pending/log |
| Waybar `custom/ops` | worst state at a glance (✓ / ! N / ✗ N); click → `dots-ops status` | reads `state/*.json` |
| `~/.config/dots-ops/config.toml` (chezmoi template) | thresholds, schedules, idle minutes, retention, cluster contexts, per-job enable | per-host values via chezmoi data |

### Notification semantics
State-change driven: ok→warn/fail notifies once; repeated fail re-notifies at most every 24 h;
fail→ok sends one "recovered". Pending approvals persist until handled (not lost if a toast is
missed); if no notification daemon is running, notifications queue in `pending/` and show next login.

## Domains and jobs

| Domain | Job | Trigger | Auto | Approve |
|---|---|---|---|---|
| Updates | `updates-check` | daily + network-online | refresh indexes, count pending (native: apt-get -s / dnf check-update / checkupdates) | — |
| | `updates-security` | daily, idle | distro security-only updates (unattended-upgrades on Ubuntu/Debian; `dnf upgrade --security` on Fedora/RHEL); Arch has no security channel → Approve | — |
| | `updates-full` | idle, after updates-check finds updates | — | native full upgrade (apt dist-upgrade / dnf upgrade / pacman -Syu); Nix and pinned tools move via `dots-update` and `pins-check`; prompt shows counts and whether kernel/GPU driver changes |
| | `reboot-needed` | path unit on reboot-required markers | notify | reboot now / at 03:00 |
| Firmware | `firmware` | weekly | `fwupdmgr refresh` + list | every firmware update |
| Security | `audit` | weekly, idle | `lynis audit system`, arch-audit / OS CVE check; report score diff | — |
| | `firewall` | on chezmoi change + boot | apply declarative ruleset (ufw: Ubuntu/Debian/Arch; firewalld: Fedora/RHEL; NixOS: networking.firewall); includes KDE Connect 1714–1764 | first apply on each machine (dry-run diff shown) |
| | `ssh-harden` | on change | sshd drop-in: no root login, keys only; `sshd -t` before reload | — |
| Disk | `disk-watch` | hourly | alert at 85 % / 95 % per mount | — |
| | `disk-clean` | idle, or disk-watch ≥ 85 % | journal vacuum 2 weeks, nix GC > 14 d, package caches, `~/.cache` sweep | `docker system prune --volumes` |
| | `smart` | daily | SMART health; alert on change | — |
| | `trim` | weekly | `fstrim -av` | — |
| Performance | `power-profile` | udev AC/battery + boot | AC → performance, battery → power-saver (power-profiles-daemon or tuned per distro) | — |
| | `perf-mode` | keybind / Waybar click | toggle focus mode (performance + SwayNC do-not-disturb) | — |
| Network | `net-watch` | 5 min + NetworkManager dispatcher | connectivity, DNS, tailscale, kube tunnels; restart a tunnel unit once, then alert | — |
| Containers | `containers` | hourly | alert on unhealthy/restart-looping containers; prune dangling images when idle | — |
| Clusters | `k8s-health` | 15 min | per context (onprem-s2a, ovh): NotReady nodes, CrashLoop pods, certs < 14 d, failed Argo syncs; dedupe per issue | — |
| Backups | `backup` | daily, idle | restic backup of `$HOME` (excludes) + dots repo; weekly `restic check` | restore; `forget --prune` beyond policy |
| | `backup-watch` | daily | alert if last good backup > 48 h | — |

## Failure handling
- `flock` per job (no overlap); per-job timeouts → `fail`.
- Partial upgrade failure: mark `fail` with the failing step, no auto-retry; Retry button.
- Before any distro/nix upgrade: record previous home-manager generation and, where present, a
  snapper/timeshift snapshot hint; failure notifications include the rollback command.
- Self-healing is bounded: one automatic restart (e.g. a tunnel), then alert. Never loops.
- Log rotation at 10 MB, 30-day history; raw output in `journalctl [--user] -u dots-ops@*`.

## Where it lives (dots repo)
- chezmoi: `home/private_dot_local/lib/dots-ops/`, `home/private_dot_local/private_bin/executable_dots-ops*`,
  user units under `home/private_dot_config/systemd/private_user/`, `home/private_dot_config/dots-ops/config.toml.tmpl`,
  Waybar module entry, hypridle `on-timeout` hook.
- root layer (chezmoi `run_once_before_00-system` / NixOS module): system units, `/etc/sudoers.d/dots-ops`,
  firewall/sshd/tuned/power-profiles/fwupd/smartd per distro family.
- Nix packages: smartmontools, restic, lynis, bats (tests).

## Testing
- **bats unit tests** for lib.sh: state transitions + notify-once, ask approve/skip/snooze/expiry,
  lock contention, `ops_idle_ok` with fake idle/AC inputs, relay root→user. `notify-send` replaced by
  a recording fake.
- **Per-job dry-run tests** (`DOTS_OPS_DRY_RUN=1` prints commands): security-only vs full selection per
  distro family, auto vs approve prune commands, disk thresholds with a fake `df`, k8s alert dedupe.
- **`systemd-analyze verify`** for every unit; `Persistent=true` on timers where missed runs matter.
- **CI distro matrix** (from the consolidation plan): each job in dry-run picks the right package
  manager and firewall tool per container.
- **Fire drill** on the work PC at cutover: `dots-ops run <job> --now` for each job, show results.

## Rollout order (each step usable on its own)
1. Engine (lib, units, relay, Waybar, status TUI, sudo rule)
2. Disk + SMART + TRIM
3. Updates (check → security auto → full with approval) + reboot-needed + firmware
4. Network + containers + clusters
5. Security (audit, firewall, SSH) — last; firewall first-apply needs approval with a dry-run diff
6. Performance modes + backups

## Out of scope
Off-machine alerting (O2), central monitoring stacks (SigNoz already covers cluster telemetry),
automatic kernel/driver/firmware updates (always Approve), multi-machine orchestration.
