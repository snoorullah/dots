# dots-ops

dots-ops keeps the machine healthy without you watching it. Small systemd jobs check disks, updates,
network, containers, clusters, backups and security. Safe work runs by itself. Anything risky asks you first.
You see the result in one Waybar icon.

It is plain bash plus systemd. There is no daemon. It works the same on Arch, Debian/Ubuntu, Fedora/RHEL and
NixOS. Spec: `docs/superpowers/specs/2026-10-07-dots-ops-design.md`. This page describes the system as built.

## Architecture

Two halves, one shared library (`lib.sh`):

| Half | Runs as | Code lives in | Units |
|---|---|---|---|
| User | you | `~/.local/lib/dots-ops/` (chezmoi), CLI in `~/.local/bin/dots-ops*` | `systemctl --user` |
| Root | root | `/usr/local/lib/dots-ops/`, `/usr/local/bin/dots-ops-run`, `/usr/local/bin/dots-ops-job` (NixOS: the nix store) | `systemctl` (system) |

- A job is one file with a `job_main` function. `dots-ops@<job>.service` runs it through `dots-ops-job`.
  The same template exists for user and root.
- `dots-ops-job` takes a lock per job (`flock`, so runs never overlap), checks the job is enabled, and for
  heavy jobs checks the machine is idle and on AC. Then it calls `job_main`.
- A job reports with `ops_state <job> ok|warn|fail "summary"`. A change of state sends one notification.
- Root jobs write their status to `/var/lib/dots-ops/<job>.json`. The **relay** (`dots-ops-relay.path`) watches
  that directory and copies each status into your user state, so root jobs show up in Waybar too.
- A job that needs your say-so calls `ops_ask`. That creates an **approval** (a pending file) and a SwayNC
  notification with buttons. Your answer goes through `dots-ops answer`.
- A root job asks by writing `/var/lib/dots-ops/ask-<job>.json`. The relay turns it into a user approval.
  The relay only accepts root actions in such asks, and drops asks older than 24 h.
- When you approve a root action, `sudo -n /usr/local/bin/dots-ops-run <job> <action>` starts a transient unit
  `dots-ops-act-<job>-<action>`. It returns at once. The action runs on in its own unit, so logging out
  cannot kill a half-finished package transaction.
- **Heavy** jobs wait for idle: `hypridle` runs `dots-ops idle-start` after 15 minutes without input
  (`timeout = 900` in `~/.config/hypr/hypridle.conf`). Heavy jobs run only when idle AND on AC. A fallback at 03:30 opens a 2 h idle
  window if the screen is locked (or nobody is logged in) and the machine is on AC.

## What runs when

"Heavy" means: only when idle and on AC (or forced with `--now`). "Auto" means it acts without asking.

| Job | Context | Trigger | Heavy | Auto / approve | What it does |
|---|---|---|---|---|---|
| `updates-check` | root | daily, 10 min after boot | no | auto (read-only), asks | Counts pending updates (apt / dnf / checkupdates). Pending updates raise an `updates-full` ask. NixOS: n/a |
| `updates-security` | root | daily 04:00, idle target | yes | auto | Security-only updates: unattended-upgrade (Debian/Ubuntu), `dnf --security` (Fedora/RHEL). Arch and NixOS: n/a |
| `updates-full` (action) | root | after you approve | n/a | approve | Full native upgrade. The ask shows the count and a kernel/driver flag |
| `reboot-needed` | root | `dots-ops-reboot.path` (reboot marker) | no | approve | Asks: reboot now, or tonight 03:00 |
| `firmware` | root | weekly | no | approve | `fwupdmgr refresh`, asks before installing any firmware update |
| `audit` | root | weekly, idle target | yes | auto | `lynis` score and warnings, compared with last run (plus `arch-audit` on Arch). Needs lynis, else n/a |
| `firewall` | root | daily, 5 min after boot, on installer run | no | approve | Compares the live firewall with `firewall.json`. First apply and any drift ask, with the exact commands shown |
| `ssh-harden` | root | daily, 5 min after boot, on installer run | no | approve | Offers the sshd drop-in (no root login, keys only). Skips if you have no usable authorized key |
| `disk-watch` | user | hourly | no | auto | Warns at `disk.warn` %, fails at `disk.crit` %. At warn it starts both cleaners, forced |
| `disk-clean-user` | user | idle target, or forced by disk-watch | yes | auto | Nix GC for your profile, stale caches |
| `disk-clean-system` | root | daily 03:40, idle target, or forced | yes | auto | Journal vacuum (2 weeks), package cache clean, Nix GC |
| `smart` | root | daily | no | auto | SMART health and error counters per disk. A rising counter keeps the disk red for 7 days. No SMART disk: n/a |
| `trim` | root | weekly | no | auto | Makes sure periodic TRIM is on. Unsupported: n/a |
| `power-profile` | root | udev (AC change), event driven | no | auto | AC: performance. Battery: power-saver. Desktop: balanced |
| `net-watch` | user | 2 min after boot, then every 5 min | no | auto | DNS, internet, tailscale, kube tunnels. Restarts a down tunnel once, then fails |
| `containers` | user | hourly | no | auto | Warns on unhealthy or restarting containers. No docker: n/a |
| `containers-prune` | user | idle target | yes | auto + approve | Prunes dangling images. Asks before the root volumes prune when more than 10 GB is reclaimable |
| `k8s-health` | user | 5 min after boot, then every 15 min | no | auto | Per kube context: NotReady nodes, CrashLoop pods, expiring certs, failed Argo syncs. One notification per new issue |
| `backup` | user | idle target | yes | auto | restic snapshot of `$HOME` (plus the dots repo if outside), then forget/prune |
| `backup-check` | user | weekly | yes | auto | `restic check` of the structure and a 5 % data sample |
| `backup-watch` | user | daily | no | auto | Warns when the newest backup is older than `backup.max_age_hours` |
| `dots-update` | user | daily | yes | auto | `chezmoi update --apply --no-tty`: pulls the repo, re-runs the Nix switch |
| `pins-check` | user | Mondays 10:00 | no | auto + approve | Compares pinned tools and the nixpkgs lock with upstream. Asks to open a bump PR (`dots-ops pins-bump`) |

Notes:

- There is no topgrade. System upgrades use each distro's own tool. Nix and pinned tools move through
  `dots-update` and `pins-check`.
- Heavy root jobs are pulled by `dots-ops-system-idle.target`. Heavy user jobs by `dots-ops-idle.target`.
- On NixOS the root layer comes from `nix/hosts/nixos-laptop/dots-ops.nix`. Package updates and the firewall
  are NixOS' own, so those jobs report n/a.

## Waybar module and `dots-ops status`

The Waybar module `custom/ops` shows the worst state, refreshed every 30 s and on every state change.

| Text | Class | Meaning |
|---|---|---|
| `✓` | `ok` | all jobs ok, nothing waiting |
| `! N` | `warn` | N jobs in warn, or approvals waiting |
| `✗ N` | `fail` | N jobs failed |
| `· K ask` | | suffix: K approvals waiting for you |

The tooltip lists every non-ok job with its summary, and every waiting approval.
Left click opens `dots-ops status`. Right click toggles performance mode (`dots-ops perf-mode`).

`dots-ops status` is an fzf list, worst first. Each line is `job ⟂ status ⟂ summary ⟂ age`.
Status is `ok`, `warn`, `fail`, or `ask` (an approval waiting).

| Key | Action |
|---|---|
| enter | last 50 log lines of the job |
| ctrl-a | approve |
| ctrl-s | snooze |
| ctrl-k | skip |
| ctrl-r | run now (`dots-ops run <job> --now`) |

Other commands:

| Command | Does |
|---|---|
| `dots-ops run <job> [--now]` | start a job. Without `--now`: via systemd, async. With `--now`: user job runs in your terminal and ignores the idle gate. Root job: starts a transient unit `dots-ops-now-<job>` and returns at once |
| `dots-ops answer <job> approve\|alt\|skip\|snooze` | answer an approval (what the buttons do) |
| `dots-ops idle-start [--fallback]`, `idle-end` | open or close the idle window (hypridle calls these) |
| `dots-ops perf-mode [on\|off\|toggle]` | performance profile plus do-not-disturb |
| `dots-ops pins-bump` | open the pins bump PR (the approval action of `pins-check`) |
| `dots-ops relay` | copy root status and asks into user state (the path unit runs this) |
| `dots-ops waybar` | print the Waybar JSON |

## Approving, snoozing, skipping

Each approval is one SwayNC notification with buttons:

| Button | Effect |
|---|---|
| Approve | runs the action (a root action goes through `dots-ops-run`) |
| second button (only on `reboot-needed`: "Tonight 03:00") | runs the alternative action |
| Skip | drops it. The next run asks again if it is still needed |
| Snooze 1d | hides it for 24 h. It also leaves the Waybar count for 24 h |

- An approval **expires after 24 h** and counts as skip. Approving an expired one does nothing.
- There is one live approval per job. A missed toast is not lost: see `dots-ops status` or the Waybar count.
- Approvals are bound to what you saw. The firewall ask stores the hash of the rules and commands it showed.
  If `firewall.json` changes before you approve, the apply refuses ("rules changed since approval") and a fresh
  ask is made.
- If no notification daemon runs (TTY login, SwayNC crashed), notifications queue in
  `~/.local/state/dots-ops/queue/` and appear on the next job run.

## Where logs and state live

| What | Where |
|---|---|
| User log (JSON lines, rotated at 10 MB, 30 days kept) | `~/.local/state/dots-ops/log.jsonl` |
| User job status | `~/.local/state/dots-ops/state/<job>.json` |
| Waiting approvals | `~/.local/state/dots-ops/pending/<job>.json` |
| Relay bookkeeping, locks, queue | `~/.local/state/dots-ops/{relayed,locks,queue}/` |
| Perf-mode flag | `~/.local/state/dots-ops/perf-mode` |
| Root job status and root asks | `/var/lib/dots-ops/<job>.json`, `/var/lib/dots-ops/ask-<job>.json` |
| Root log, locks | `/var/lib/dots-ops/root/` |
| Firewall bookkeeping | `/var/lib/dots-ops/firewall.applied`, `firewall.pending-hash` |
| Owner name for ssh guard | `/etc/dots-ops/owner` |
| Raw job output | `journalctl --user -u dots-ops@<job>` and `journalctl -u dots-ops@<job>` |
| Approved root actions | `journalctl -u 'dots-ops-act-*'` |
| Forced root runs | `journalctl -u 'dots-ops-now-*'` |

Quick log of one job: `jq -r 'select(.job=="backup")' ~/.local/state/dots-ops/log.jsonl`.

## Config

User config: `~/.config/dots-ops/config.toml` (chezmoi). Defaults are used for any missing key. The idle threshold is not a config key: it is `timeout = 900` in `~/.config/hypr/hypridle.conf`.

| Key | Default | Used by |
|---|---|---|
| `disk.warn` / `disk.crit` | 85 / 95 | `disk-watch` |
| `backup.keep_daily` / `keep_weekly` / `keep_monthly` | 7 / 4 / 6 | `backup` forget policy |
| `backup.max_age_hours` | 48 | `backup-watch` |
| `k8s.contexts` | `["admin@onprem-s2a", "ovh"]` | `k8s-health` |
| `pins.lock_max_days` | 30 | `pins-check`, `pins-bump` (nixpkgs lock age) |
| `jobs.<job>.enabled` | `true` | any job: set `false` to disable |

**Root ignores this file.** Root has no `yq` (it is only in your Nix profile), so root jobs run on their
built-in defaults. Root jobs also never read anything from your home. Thresholds you can tune live in user jobs.
A root job therefore cannot be switched off from config. See "How to disable a job".

## Adding a job

1. Write the job file. User: `home/private_dot_local/lib/dots-ops/jobs/<job>.sh`. Root:
   `system/dots-ops/jobs/<job>.sh`. Set `OPS_HEAVY=1` if it is heavy. Define `job_main`. Report with
   `ops_state`. Run every mutating command through `ops_run` so `DOTS_OPS_DRY_RUN=1` only prints it.
2. For an approval, call `ops_ask <job> "question" "user:<command>"` or `"root:<job> <action>"`. A root
   action also needs `system/dots-ops/actions/<job>/<action>.sh`.
3. Add a timer. User: `home/private_dot_config/systemd/private_user/dots-ops-<job>.timer` with
   `Unit=dots-ops@<job>.service`. Root: `system/dots-ops/units/dots-ops-<job>.timer`. For an idle-driven heavy
   job add `dots-ops@<job>.service` to `Wants=` of `dots-ops-idle.target` (user) or
   `dots-ops-system-idle.target` (root).
4. User timers: add the enable line to `home/.chezmoiscripts/run_onchange_after_24-systemd.sh.tmpl`
   (`systemctl --user enable --now dots-ops-<job>.timer`). Root timers are enabled by the installer loop.
5. Add a bats test in `tests/ops/`. Use the stubs in `tests/ops/stubs/` and `DOTS_OPS_DRY_RUN`.
   Cover the n/a path on distros that lack the feature. A missing feature must report `ok` n/a, never `fail`.
6. Run `bats tests/ops`, `bash tests/lint.sh`, `bash tests/placement.sh`.
7. Root files only: the installer hash changes, so the root layer reinstalls on the next `chezmoi apply`.

## Backups (restic)

Backups need a repository and a password. They come from the environment, never from the repo.
Put them in the hand-copied `~/.secrets` (mode 0600, owned by you):

```sh
export RESTIC_REPOSITORY=/mnt/backup/restic        # or sftp:host:/path, s3:..., b2:...
export RESTIC_PASSWORD='...'                       # or: export RESTIC_PASSWORD_FILE=/path/to/file
```

Create the repository once:

```sh
. ~/.secrets && restic init
```

Until this is set, `backup` shows warn "not configured" and the other backup jobs report n/a.
Excluded paths are in `~/.config/dots-ops/backup-excludes`. Snapshots carry the tag `dots-ops`.

Restore:

```sh
. ~/.secrets
restic snapshots --tag dots-ops                       # find the id
restic restore <id> --target /tmp/restore             # everything
restic restore <id> --target /tmp/restore --include /home/<you>/.ssh   # one path
mkdir -p /tmp/mnt && restic mount /tmp/mnt            # browse snapshots like a filesystem
```

Never restore over your live home without looking first. Restore to a temp target and copy what you need.

## How to disable a job

- User job: set it in `~/.config/dots-ops/config.toml` (edit the chezmoi source, then `chezmoi apply`):

  ```toml
  [jobs.backup]
  enabled = false
  ```

  The job exits at once and logs "disabled in config".
- Stop the schedule: `systemctl --user disable --now dots-ops-<job>.timer`.
- Root job: `sudo systemctl disable --now dots-ops-<job>.timer`. For jobs pulled by the idle target, remove the
  job from `Wants=` in `system/dots-ops/units/dots-ops-system-idle.target` and re-run the installer.
- Everything at once: `systemctl --user disable --now dots-ops-relay.path` stops the relay. Removing yourself
  from group `dots-ops` removes the root path (the sudo rule).

## Security model

- The only way from your user to root is `sudo -n /usr/local/bin/dots-ops-run <job> <action>`. The sudoers rule
  (`/etc/sudoers.d/dots-ops`) allows only that binary, only for group `dots-ops`, without a password.
  It sets `env_reset` and a fixed `secure_path` for it, so your environment and PATH never reach root.
- `dots-ops-run` starts with `#!/bin/bash -p`, fixes PATH before any command, and drops every `OPS_*` and
  `DOTS_OPS_*` variable.
- It checks `<job>` and `<action>` against **existing root-owned files**: `/usr/local/lib/dots-ops/jobs/<job>.sh`
  (run) and `/usr/local/lib/dots-ops/actions/<job>/<action>.sh` (approved action). Names must match
  `[a-z0-9-]`, so `../` and unknown jobs or actions are rejected. A job named `ask-*` is reserved.
- It refuses files that are not root-owned, or are group/world writable. `dots-ops-job` does the same as root.
- Root never executes or sources anything from your home. The installer refuses to run if `/usr/local`,
  `/usr/local/bin` or `/usr/local/lib` is not root-owned, and refuses symlinks under `system/dots-ops`.
- Approved actions and forced runs start as transient units (`dots-ops-act-*`, `dots-ops-now-*`). The 3-argument
  `inline` form of the runner only works when systemd set `INVOCATION_ID`, so `sudo` cannot use it directly.
- Root jobs resolve the owner's home with `getent` from `/etc/dots-ops/owner`, never from the environment.
- The firewall and sshd are guarded against lockout. A first apply is always an approval with the commands shown.
  `ssh-harden` skips (warn) when you have no usable authorized key, checks `sshd -t`, and removes its file if
  invalid.
- Joining group `dots-ops` is a trust grant: members can run any allow-listed root action. Only the owner is in it.

## Known limitations and owner decisions

| Item | Behaviour | What you do |
|---|---|---|
| Firewall is additive only (R41) | Apply never deletes rules. Rules you added by hand stay. Drift is never re-applied silently: it warns and asks | Close a port you removed from `firewall.json` by hand (`sudo ufw delete allow <port>`) |
| ufw default-deny blocks tailnet services (R42) | Only ssh and the `firewall.json` ports pass, also over `tailscale0` | Add a rule to `system/dots-ops/firewall.json` for each tailnet service you want |
| Fedora zone left as is (R43) | FedoraWorkstation zone keeps 1025-65535 open. dots-ops does not tighten it | Tighten by hand if you want the same strictness as other distros |
| Docker-published ports bypass ufw | Docker writes its own iptables rules. `-p 8080:80` is open regardless of ufw | Bind to `127.0.0.1` (`-p 127.0.0.1:8080:80`) or use the `DOCKER-USER` chain |
| `dots-update` and sudo without a tty | `chezmoi update` runs `run_onchange` scripts that call `sudo`. Without a tty (a timer) sudo cannot ask for a password, so the job fails when such a script has changes | Run `chezmoi update` by hand once. A passwordless sudo rule for those scripts is not provided |
| Root thresholds not configurable (R18) | Root jobs use built-in defaults | Edit the root job, or install `yq` system-wide (not done by the installer) |
| lynis on RHEL | Needs EPEL. Without it `audit` reports n/a | Enable EPEL |
| Secrets are hand-copied | `~/.secrets` is never in the repo | Copy it, mode 0600 (see `docs/install.md`) |
| Rollback hint | Failure notices name snapper/timeshift only. Root cannot know your home-manager generation | `home-manager generations` |
| Arch security updates | Arch has no security channel. `updates-security` is n/a and the full update is by approval | |

## Fire drill (cutover checklist)

Run this once on the real machine after the first `chezmoi apply`. Order follows the rollout.
Inspect any job with:

```sh
journalctl --user -u dots-ops@<job> -n 50     # user job
journalctl -u dots-ops@<job> -n 50            # root job (scheduled run)
journalctl -u 'dots-ops-now-*' -n 50          # root job started with --now
journalctl -u 'dots-ops-act-*' -n 50          # approved root actions
dots-ops status                               # state, summaries, waiting approvals
```

### One-time steps first

- [ ] The installer adds you to group `dots-ops`. **Log out and back in** (or reboot). Check `id -nG | grep dots-ops`.
- [ ] `systemctl --user list-timers 'dots-ops-*'` shows the user timers. `systemctl list-timers 'dots-ops-*'` shows the root ones.
- [ ] `systemctl --user is-active dots-ops-relay.path` is `active`. Waybar shows the `✓` icon (restart Waybar if not).
- [ ] The installer starts `firewall` and `ssh-harden` once. Expect two approvals (see steps 5a and 5b). Do not approve before reading them.

### Per job

`--now` skips the idle and AC gate. A root `--now` returns at once, so check the journal after a few seconds.

| # | Job | Command | Expected result |
|---|---|---|---|
| 1 | engine | `dots-ops status` | The list opens. Press esc to leave |
| 2a | `disk-watch` | `dots-ops run disk-watch --now` | `ok` "worst N%". If a disk is above `disk.warn` it also starts both cleaners |
| 2b | `disk-clean-user` | `dots-ops run disk-clean-user --now` | `ok` with MB freed |
| 2c | `disk-clean-system` | `dots-ops run disk-clean-system --now` | `ok` after the journal, cache and Nix steps (journal: `-u dots-ops-now-disk-clean-system`) |
| 2d | `smart` | `dots-ops run smart --now` | `ok` per disk, or `ok` n/a with no SMART-capable disk |
| 2e | `trim` | `dots-ops run trim --now` | `ok` "fstrim.timer enabled", or n/a |
| 3a | `updates-check` | `dots-ops run updates-check --now` | `ok` "up to date", or `warn` "N pending" and an `updates-full` approval |
| 3b | `updates-security` | `dots-ops run updates-security --now` | `ok`. Arch and NixOS: n/a |
| 3c | `updates-full` | approve the ask only if you are ready | The action runs in `dots-ops-act-updates-full-apply`. The button returns at once. Watch `journalctl -fu dots-ops-act-updates-full-apply` |
| 3d | `reboot-needed` | `dots-ops run reboot-needed --now` | `ok` when nothing is pending. Otherwise an ask: reboot now / Tonight 03:00. Skip it during the drill |
| 3e | `firmware` | `dots-ops run firmware --now` | `ok` and n/a without fwupd. With updates: an ask. Skip it |
| 4a | `net-watch` | `dots-ops run net-watch --now` | `ok` "online". Tunnels with no hand-copied secret are n/a |
| 4b | `containers` | `dots-ops run containers --now` | `ok`. No docker: n/a |
| 4c | `containers-prune` | `dots-ops run containers-prune --now` | `ok`. An ask appears only above 10 GB reclaimable. Skip it |
| 4d | `k8s-health` | `dots-ops run k8s-health --now` | `ok`, or `warn` naming issues. A tunnel that is down shows "<ctx> unreachable" |
| 5a | `firewall` | `dots-ops run firewall --now` | A `warn` and an ask showing the commands. Read the list. Check ssh (22) is in it. Approve. Then `journalctl -u 'dots-ops-act-*'` and `sudo ufw status` (or `firewall-cmd --list-all`). Run the job again: expect `ok` |
| 5b | `ssh-harden` | `dots-ops run ssh-harden --now` | Without authorized keys: `warn` "skipped: no authorized_keys". With keys: an ask. Keep a second SSH session open, approve, then test a new login |
| 5c | `audit` | `dots-ops run audit --now` | `ok` with the lynis index, or n/a without lynis. The first run only records a baseline |
| 6a | `power-profile` | `dots-ops run power-profile --now`, then unplug and replug AC | `ok`. `powerprofilesctl get` follows AC |
| 6b | perf-mode | `dots-ops perf-mode on`, then `off` | A toast each way. `on`: performance profile and do-not-disturb |
| 6c | `backup` | `dots-ops run backup --now` (after `restic init`) | `ok` with a snapshot id. Without credentials: `warn` "not configured" |
| 6d | `backup-watch` | `dots-ops run backup-watch --now` | `ok` after 6c |
| 6e | `backup-check` | `dots-ops run backup-check --now` | `ok` "repository check passed" |
| 6f | restore test | `restic snapshots`, then `restic restore <id> --target /tmp/restore --include <one file>` | The file appears |
| 7a | `dots-update` | `dots-ops run dots-update --now` | `ok` "dots up to date". It can fail if a `run_onchange` script needs sudo (see limitations) |
| 7b | `pins-check` | `dots-ops run pins-check --now` | `ok` "all pins current", or `warn` and an ask to open a bump PR. Skip the ask |

### Final checks

- [ ] `dots-ops status` shows no `fail`. Every `warn` has a summary you understand.
- [ ] Click the Waybar icon: the status window opens. Snooze one approval (ctrl-s): the `ask` count drops.
- [ ] Kill SwayNC for a minute, trigger a warn, restart it: the notification shows up (queue).
- [ ] `journalctl -u 'dots-ops-act-*'` shows only the actions you approved.
