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
  Only a lasting `fail` reminds you again (every 24 h). A lasting `warn` stays quiet after its first notification.
- Every dots-ops unit has an `ExecStopPost=` reporter (`dots-ops-job --report-failure`). If a unit crashes, is
  killed or hits its timeout before the job could report, the job turns `fail` "unit <result>/<code>/<status>"
  (for example `unit timeout/killed/TERM`). This covers the user and root `dots-ops@.service` and the transient
  `dots-ops-now-*` / `dots-ops-act-*` units. When the job already reported warn/fail in that run, the reporter
  stays out of the way.
- Root jobs write their status to `/var/lib/dots-ops/<job>.json`. The **relay** (`dots-ops-relay.path`) watches
  that directory and copies each status into your user state, so root jobs show up in Waybar too. Only status
  and ask files live at that level. Everything else root keeps (lynis report, audit baseline, SMART counters,
  firewall hashes, locks, the scheduled-reboot marker) is in `/var/lib/dots-ops/root/`, which the relay does not
  watch, so bookkeeping writes never fire the relay.
- A job that needs your say-so calls `ops_ask`. That creates an **approval** (a pending file) and a SwayNC
  notification with buttons. Your answer goes through `dots-ops answer`.
- A root job asks by writing `/var/lib/dots-ops/ask-<job>.json`. The relay turns it into a user approval.
  The relay only accepts root actions in such asks, and drops asks older than 24 h.
- When you approve a root action, `sudo -n /usr/local/bin/dots-ops-run <job> <action>` starts a transient unit
  `dots-ops-act-<job>-<action>`. It returns at once. The action runs on in its own unit, so logging out
  cannot kill a half-finished package transaction. A root action that reports its own result uses a state name
  that no user job has, so the relay never drops it: the volumes prune reports as `containers-prune-volumes`.
  If the action unit itself dies, it shows up as `<job>-<action>` (for example `updates-full-apply`).
- **Heavy** jobs wait for idle: `hypridle` runs `dots-ops idle-start` after 15 minutes without input
  (`timeout = 900` in `~/.config/hypr/hypridle.conf`). `idle-start` also sets the logind idle hint of your
  session, and `idle-end` clears it. Heavy jobs run only when idle AND on AC.
- The nightly fallback (`dots-ops-fallback.timer`, 03:30) is a **user** timer. It runs only while your user
  manager runs, which means while you are logged in (no linger is set up). It opens a 2 h idle window only if
  the machine is on AC, the screen is locked, and logind reports you idle (`IdleHint=yes`) for at least
  15 minutes. The timer is not `Persistent`, so a 03:30 missed while the machine slept does not fire on resume.

## What runs when

"Heavy" means: only when idle and on AC (or forced with `--now`). "Auto" means it acts without asking.

| Job | Context | Trigger | Heavy | Auto / approve | What it does |
|---|---|---|---|---|---|
| `updates-check` | root | daily, 10 min after boot | no | auto (read-only), asks | Counts pending updates (apt / dnf / checkupdates). Pending updates raise an `updates-full` ask. NixOS: n/a |
| `updates-security` | root | daily 04:00, idle target | yes | auto | Security-only updates: unattended-upgrade (Debian/Ubuntu), `dnf --security` (Fedora/RHEL). Holds the package lock. Arch and NixOS: n/a |
| `updates-full` (action) | root | after you approve | n/a | approve | Full native upgrade. The ask shows the count and a kernel/driver flag. Holds the package lock |
| `reboot-needed` | root | `dots-ops-reboot.path` (`/run/reboot-required`), after updates | no | approve | Asks: reboot now, or tonight 03:00. Neither reboots during a package transaction |
| `reboot-scheduled` | root | 03:00 timer armed by "Tonight 03:00" | no | (approved) | Reboots if no package transaction runs. Otherwise retries every 15 min, at most 8 times, then warns |
| `firmware` | root | weekly | no | approve | `fwupdmgr refresh`, asks before installing any firmware update |
| `audit` | root | weekly, idle target | yes | auto | `lynis` score and warnings, compared with last run (plus `arch-audit` on Arch). Needs lynis, else n/a |
| `firewall` | root | daily, 5 min after boot, on installer run | no | approve | Compares the live firewall with `firewall.json`. First apply and any drift ask, with the exact commands shown. ssh is allowed on the port(s) `sshd -T` reports (22 from `firewall.json` when sshd is missing) |
| `ssh-harden` | root | daily, 5 min after boot, on installer run | no | approve | Offers the sshd drop-in (no root login, keys only). Skips if you have no usable authorized key |
| `disk-watch` | user | hourly | no | auto | Warns at `disk.warn` %, fails at `disk.crit` %. At warn it starts both cleaners, forced, at most every 6 h |
| `disk-clean-user` | user | idle target, or forced by disk-watch | yes | auto | Nix GC for your profile, stale caches |
| `disk-clean-system` | root | daily 03:40, idle target, or forced | yes | auto | Journal vacuum (2 weeks), package cache clean, Nix GC |
| `smart` | root | daily | no | auto | SMART health and error counters per disk. A rising counter keeps the disk red for 7 days. No SMART disk: n/a |
| `trim` | root | weekly | no | auto | Makes sure periodic TRIM is on. Unsupported: n/a |
| `power-profile` | root | udev (AC change), event driven | no | auto | AC: performance. Battery: power-saver. Desktop: balanced |
| `net-watch` | user | 2 min after boot, then every 5 min | no | auto | DNS, internet, kube tunnels, and tailscale only if you installed it yourself. Restarts a down tunnel once, then fails |
| `containers` | user | hourly | no | auto | Warns on unhealthy or restarting containers. No docker: n/a |
| `containers-prune` | user | idle target | yes | auto + approve | Prunes dangling images. Asks before the root volumes prune when more than 10 GB is reclaimable. The approved prune reports as `containers-prune-volumes` |
| `k8s-health` | user | 5 min after boot, then every 15 min | no | auto | Per kube context: NotReady nodes, CrashLoop pods, expiring certs, failed Argo syncs. One notification per new issue. A context with any failed query counts as unreachable for that run (its known issues are kept). A configured context missing from this host's kubeconfig is n/a |
| `backup` | user | idle target | yes | auto | restic snapshot of `$HOME` (plus the dots repo if outside), then forget/prune |
| `backup-check` | user | weekly, idle target | yes | auto | `restic check` of the structure and a 5 % data sample. Skips itself if it ran in the last 7 days |
| `backup-watch` | user | daily | no | auto | Warns when the newest backup is older than `backup.max_age_hours` |
| `dots-update` | user | daily, idle target | yes | auto | `chezmoi update --apply --no-tty`: pulls the repo, re-runs the Nix switch. Skips itself if it ran in the last day |
| `pins-check` | user | Mondays 10:00 | no | auto + approve | Compares pinned tools and the nixpkgs lock with upstream. Asks to open a bump PR (`dots-ops pins-bump`) |

Notes:

- There is no topgrade. System upgrades use each distro's own tool. Nix and pinned tools move through
  `dots-update` and `pins-check`.
- Heavy root jobs are pulled by `dots-ops-system-idle.target`. Heavy user jobs by `dots-ops-idle.target`.
- On NixOS the root layer comes from `nix/hosts/nixos-laptop/dots-ops.nix`. Package updates and the firewall
  are NixOS' own, so those jobs report n/a.
- Debian/Ubuntu: `apt-daily-upgrade.timer` (the distro's own unattended-upgrades run) is left to apt. dots-ops
  does not disable it, so security updates may also run outside the idle gate and outside the package lock.
- **Package lock.** `updates-full` apply and `updates-security` hold one shared lock
  (`/var/lib/dots-ops/root/locks/pkg.lock`) for the whole package transaction. If the lock is busy they wait
  up to 30 min. Then apply fails ("approve again later") and the security run skips with a warn.
  "Reboot now" refuses with warn "package transaction running — try again" while the lock is held. The reboot
  ask comes back by itself after the transaction, because both update paths re-run `reboot-needed`.
- **Tonight 03:00** is not `shutdown -r 03:00`. It arms a transient timer `dots-ops-reboot-scheduled.timer`.
  At 03:00 it runs the root job `reboot-scheduled`, which reboots only if the package lock is free. If not, it
  re-arms itself for 15 min later, at most 8 times, then gives up with a warn. Cancel with
  `sudo systemctl stop dots-ops-reboot-scheduled.timer`.

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
Status is `ok`, `warn`, `fail`, or `ask` (an approval waiting). An `ask` row also carries the approval's token
in a hidden field, and the approve, snooze and skip keys pass it on (see below).

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
| `dots-ops answer <job> approve\|alt\|skip\|snooze [token]` | answer an approval (what the buttons do). With a token, only if the approval still shows that content |
| `dots-ops idle-start [--fallback]`, `idle-end [--fallback]` | open or close the idle window (hypridle calls these; the fallback timer uses `--fallback`) |
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
- Approvals are bound to what you saw. Each toast carries a **token**: the sha256 of the question, action,
  alternative action and ask time it showed. Your click sends `dots-ops answer <job> <choice> <token>`. If the
  approval changed in the meantime (the relay replaced a root ask with a new question), the token no longer
  matches: nothing runs, the log says "stale approval ignored", and the newer approval is shown again. When the
  relay replaces or withdraws a root ask, it also closes the old toast (it keeps the toast id from
  `notify-send -p`). `dots-ops answer` by hand, without a token, still works.
- The firewall ask also stores the hash of the rules and commands it showed. If `firewall.json` changes before
  you approve, the apply refuses ("rules changed since approval") and a fresh ask is made.
- If sudo refuses a root action you approved (group not active yet, sudoers missing), the approval is put back,
  so it is not lost.
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
| Root job status and root asks (the only files the relay watches) | `/var/lib/dots-ops/<job>.json`, `/var/lib/dots-ops/ask-<job>.json` |
| Root log, locks (including the package lock `locks/pkg.lock`) | `/var/lib/dots-ops/root/` |
| Root bookkeeping | `/var/lib/dots-ops/root/`: `firewall.applied`, `firewall.pending-hash`, `audit-last.json`, `lynis-report.dat`, `smart-<serial>.json`, `ssh-harden.*.conf`, `reboot-scheduled.json`. An older install's copies at the top level are moved here on the next root run |
| Ran-within guards, disk-watch backoff | `~/.local/state/dots-ops/{backup-check,dots-update}.last`, `disk-watch.forced` |
| Toast id of a shown approval | `~/.local/state/dots-ops/pending/<job>.nid` |
| Owner name for ssh guard | `/etc/dots-ops/owner` |
| Raw job output | `journalctl --user -u dots-ops@<job>` and `journalctl -u dots-ops@<job>` |
| Approved root actions | `journalctl -u 'dots-ops-act-*'` |
| Scheduled reboot | `journalctl -u 'dots-ops-reboot-scheduled*'` |
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

## Org-managed machines

A work PC enrolled in Intune (or any company-managed device) has its security, patching and backups owned by
company IT, and a compliance policy that may flag extra firewall, ssh, sudo or update tooling. On such a machine
set `orgManaged` and dots-ops manages nothing IT owns.

Set it with the `chezmoi init` prompt ("Org-managed machine ...?"), or put `orgManaged = true` under `[data]` in
`~/.config/chezmoi/chezmoi.toml` and run `chezmoi apply`.

What is off when `orgManaged = true`:

- **The whole root side.** The installer installs nothing: no `/usr/local/lib/dots-ops`, no `dots-ops-run`, no
  sudoers rule, no `dots-ops` group, no system units or timers, no udev rule, no `/etc/dots-ops`. So there is no
  firewall management, ssh hardening, lynis audit, update check/security/full upgrade, firmware, reboot ask,
  SMART/TRIM/system clean or power-profile job. The user side never calls `sudo` (`[root] enabled = false` in
  `~/.config/dots-ops/config.toml`): idle-start/idle-end skip the root runner silently, `disk-watch` only warns,
  `containers-prune` prunes dangling images but never offers the root volumes prune, and
  `dots-ops run <rootjob>` prints "root jobs are disabled on this machine (orgManaged)" and exits 2.
- **Root-layer packages added for dots-ops** (unattended-upgrades, fwupd, lynis, ufw, firewalld, dnf-plugins-core,
  pacman-contrib, arch-audit, power-profiles-daemon, tuned-ppd) are not installed. The desktop's own packages are.
  `perf-mode` still works but reports "power profiles unavailable" unless `powerprofilesctl` is already there.
- **Backups and self-updates.** `backup`, `backup-watch`, `backup-check`, `dots-update` and `pins-check`, their
  timers and `backup-excludes` are not deployed. The idle target does not pull them.
- **Personal infrastructure.** The Nix packages in `personalOnly` (nix/home.nix: chat and media apps, age,
  cloudflared, sshpass, CUDA, ...) are left out through `DOTS_ORG_MANAGED=1`, and extra tools marked
  `personal: true` are not installed. (Tailscale is not in the dotfiles on any profile; `net-watch` only checks
  it if the binary exists.) The personal OVH tunnel (`ovh-k8s-tunnel.service`) is not deployed or enabled, and the `ovh` kube
  context is not in `k8s.contexts`. The company cluster tunnel stays.

Kept (user level only, no root, no open ports): `disk-watch` (warn only), `disk-clean-user`, `net-watch`,
`containers`, `containers-prune`, `k8s-health`, `perf-mode`, the relay, the Waybar module and `dots-ops status`.

Switching an existing machine to `orgManaged` removes the root side on the next `chezmoi apply`: the installer
disables and deletes the dots-ops system units, the sudoers rule, the udev rule, `/usr/local/lib/dots-ops`,
`/usr/local/bin/dots-ops-{run,job}`, `/etc/dots-ops` and the `dots-ops` group. `/var/lib/dots-ops` (old status
data) is left alone. The OVH tunnel is stopped and disabled. User files already deployed (backup jobs, timers) are
not removed by chezmoi; disable them with `systemctl --user disable --now` and delete them by hand. Nothing
already installed (packages) is uninstalled.

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
  These units get the runner's fixed root PATH (`--setenv=PATH=...`), never the caller's.
- The `ExecStopPost=` failure reporter is the root-owned `/usr/local/bin/dots-ops-job --report-failure` in
  system units (the store copy on NixOS).
- Root jobs resolve the owner's home with `getent` from `/etc/dots-ops/owner`, never from the environment.
- The firewall and sshd are guarded against lockout. A first apply is always an approval with the commands shown.
  `ssh-harden` skips (warn) when you have no usable authorized key, checks `sshd -t`, and removes its file if
  invalid.
- Independently of dots-ops, the chezmoi root script puts the same three settings in
  `/etc/ssh/sshd_config.d/40-dots-baseline.conf` on every machine, org-managed ones included, and enables sshd only
  when `~/.ssh/authorized_keys` holds a key (docs/install.md). sshd keeps the first value it reads; `40-` sorts
  before `50-dots.conf` and sets the same values, so the two never disagree. On NixOS the host config sets them
  (`services.openssh.settings`, `mkDefault`), and port 22 is opened only by `firewall.json`
  (`services.openssh.openFirewall = false`).
- Joining group `dots-ops` is a trust grant: members can run any allow-listed root action. Only the owner is in it.

## Known limitations and owner decisions

| Item | Behaviour | What you do |
|---|---|---|
| Firewall is additive only (R41) | Apply never deletes rules. Rules you added by hand stay. Drift is never re-applied silently: it warns and asks | Close a port you removed from `firewall.json` by hand (`sudo ufw delete allow <port>`) |
| ufw default-deny applies to every interface (R42) | Only ssh and the `firewall.json` ports pass, on every interface, VPN or overlay interfaces included (a Tailscale or WireGuard you install yourself gets no exception) | Add a rule to `system/dots-ops/firewall.json` for each service you want reachable |
| Fedora zone left as is (R43) | FedoraWorkstation zone keeps 1025-65535 open. dots-ops does not tighten it | Tighten by hand if you want the same strictness as other distros |
| Docker-published ports bypass ufw | Docker writes its own iptables rules. `-p 8080:80` is open regardless of ufw | Bind to `127.0.0.1` (`-p 127.0.0.1:8080:80`) or use the `DOCKER-USER` chain |
| `dots-update` and sudo without a tty | `chezmoi update` runs `run_onchange` scripts that call `sudo`. Without a tty (a timer) sudo cannot ask for a password, so the job fails when such a script has changes | Run `chezmoi update` by hand once. A passwordless sudo rule for those scripts is not provided |
| Root thresholds not configurable (R18) | Root jobs use built-in defaults | Edit the root job, or install `yq` system-wide (not done by the installer) |
| lynis on RHEL | Needs EPEL. Without it `audit` reports n/a | Enable EPEL |
| Secrets are hand-copied | `~/.secrets` is never in the repo | Copy it, mode 0600 (see `docs/install.md`) |
| Rollback hint | Failure notices name snapper/timeshift only. Root cannot know your home-manager generation | `home-manager generations` |
| Arch security updates | Arch has no security channel. `updates-security` is n/a and the full update is by approval | |
| `apt-daily-upgrade.timer` (Debian/Ubuntu) | Left to apt. It can install security updates outside the idle gate and outside the dots-ops package lock | Disable it yourself if you want only dots-ops to update |
| `perf-mode off` | Returns to the same profile the `power-profile` job would pick: laptop on AC performance, on battery power-saver, desktop balanced. On a laptop on AC, on and off differ only in do-not-disturb | |
| power-profiles-daemon and tlp | They conflict. The root layer installs power-profiles-daemon only when tlp is absent. With tlp, `power-profile` and `perf-mode` report profiles unavailable | |
| Fallback needs a session and logind idle | The fallback is a user timer, so it only fires while you are logged in. It trusts logind's idle hint, which `idle-start` sets. If logind `IdleAction=` is configured in `logind.conf`, that action follows the hint | Leave `IdleAction=ignore` (the default) unless you want it |
| Removed units | The installer disables and deletes any `/etc/systemd/system/dots-ops*` unit that is no longer in the repo | |

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
| 3d | `reboot-needed` | `dots-ops run reboot-needed --now` | `ok` when nothing is pending. Otherwise an ask: reboot now / Tonight 03:00. Skip it during the drill. If you pick Tonight: `systemctl list-timers dots-ops-reboot-scheduled.timer` shows 03:00 |
| 3e | `firmware` | `dots-ops run firmware --now` | `ok` and n/a without fwupd. With updates: an ask. Skip it |
| 4a | `net-watch` | `dots-ops run net-watch --now` | `ok` "online". Tunnels with no hand-copied secret are n/a |
| 4b | `containers` | `dots-ops run containers --now` | `ok`. No docker: n/a |
| 4c | `containers-prune` | `dots-ops run containers-prune --now` | `ok`. An ask appears only above 10 GB reclaimable. Skip it |
| 4d | `k8s-health` | `dots-ops run k8s-health --now` | `ok`, or `warn` naming issues. A tunnel that is down shows "<ctx> unreachable". A context not in this host's kubeconfig shows "n/a here" |
| 5a | `firewall` | `dots-ops run firewall --now` | A `warn` and an ask showing the commands. Read the list. Check your ssh port is in it (`sudo sshd -T \| grep ^port`; 22 by default). Approve. Then `journalctl -u 'dots-ops-act-*'` and `sudo ufw status` (or `firewall-cmd --list-all`). Run the job again: expect `ok` |
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
- [ ] Idle hint: leave the machine 16 minutes, then from another device or a TTY run
      `loginctl show-user $USER -p IdleHint -p IdleSinceHint`. Expect `IdleHint=yes`. If it says `no`, the 03:30
      fallback will never fire; check that `busctl` exists and that hypridle runs inside your session.
