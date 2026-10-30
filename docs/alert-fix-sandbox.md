# Alert-fix agent: the one sudo step

The alert-fix agent runs with `sandbox.failIfUnavailable: true`.
On Ubuntu 24.04+ the sandbox cannot start until `bwrap` may create user namespaces.
Until then the agent **refuses to start** (fail closed). Nothing falls back to unsandboxed.

---

1. **Check**

   ```
   sysctl kernel.apparmor_restrict_unprivileged_userns
   ```

   `0` or "No such file": nothing to do.
   `1`: do step 2.

2. **Install the profile** (text from the official Claude Code sandboxing docs)

   ```
   sudo tee /etc/apparmor.d/bwrap > /dev/null <<'EOF2'
   abi <abi/4.0>,
   include <tunables/global>

   profile bwrap /usr/bin/bwrap flags=(unconfined) {
     userns,
     include if exists <local/bwrap>
   }
   EOF2
   sudo systemctl reload apparmor
   ```

3. **Verify**

   ```
   bwrap --ro-bind / / --unshare-user --unshare-net true && echo ok
   ```

---

**What this opens.**
Only `/usr/bin/bwrap` itself may create user namespaces, and it runs unconfined.
It does not apply to the commands bwrap runs inside the sandbox.
Every other program stays restricted.

> Do not set `kernel.apparmor_restrict_unprivileged_userns=0`.
> That lifts the restriction for every program on the machine.

Home is unreadable inside the sandbox (`denyRead ~`) except the run dir.
A test command that needs a toolchain under `~` will fail there.

---

**Before every agent start** the overview runs a probe inside the same sandbox.
It must show that the agent cannot connect to the session bus, docker, ssh-agent or herdr sockets,
cannot list `/data`, and sees none of the scrubbed credential variables.
No proof, no agent. Without the profile the probe cannot run, so nothing starts.
The probe uses one short `claude -p --model haiku` call that may run only that script.

Inside the sandbox reads are denied for `~`, `/home`, `/data`, `/tmp`, `/run`, `/media`, `/mnt` and `/srv`.
`TMPDIR` points at a private `tmp/` in the run dir.

**Config.** `rules.toml` needs `[alerts] authserv_id`, or no ticket is ever offered.
A keyring-backed `gh` credential helper may need `DBUS_SESSION_BUS_ADDRESS` for the host push (not the agent). Unverified.
