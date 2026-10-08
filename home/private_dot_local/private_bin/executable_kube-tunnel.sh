#!/usr/bin/env bash
# kube-tunnel.sh — carry kubectl to the on-prem k8s API over an SSH forward, through whichever PVE host
# is up.
#
# WHY: the API lives on the isolated node subnet (10.10.10.0/24, VLAN 100) with no route from the
# workstation. The habit that grew around that was `ssh root@B "KUBECONFIG=… kubectl …"`, which is wrong
# twice over:
#   1. it hands host B the cluster-admin certificate — a compromised B owns the cluster, not just its own
#      traffic. A forward moves only encrypted bytes; the TLS session and the client cert stay here.
#   2. it pins every cluster operation to ONE host. B down = no kubectl, on a cluster whose stated goal is
#      to survive two host failures.
# This script fixes both: it probes the declared hosts in order and forwards through the first that
# answers, so any one of the three will do.
#
# It deliberately does NOT retry in a loop — systemd's Restart=always owns that, and re-running the script
# re-probes, so a host that comes back is picked up on the next restart.
#
# It carries BOTH cluster APIs, which is what lets every operator tool run here:
#   - the Kubernetes API, for kubectl/helm
#   - the Talos API, for talosctl. One forward is enough for the WHOLE cluster: Talos proxies a
#     `-n <node>` request through whichever endpoint you reach, so `talosctl -e 127.0.0.1 -n <any node>`
#     works through a single forward to one control plane. Verified 2026-09-18 against the live cluster,
#     including a node OTHER than the forwarded one. The belief that talosctl needed one forward per node
#     is what kept a cluster-admin talosconfig sitting on host B.
#
# Usage: kube-tunnel.sh <config-file>
# Config (one directive per line; FORWARD and HOST may repeat, HOST order = preference):
#   FORWARD=<local-port> <host:port>   a loopback forward; repeat for each API
#   KNOWN_HOSTS=<path>                 pinned host keys — the repo's onprem-pve-known_hosts
#   USER=root
#   HOST=<ip> <ssh-key-path>
set -uo pipefail

CONF="${1:-}"
[ -n "$CONF" ] && [ -r "$CONF" ] || { echo "kube-tunnel: unreadable config: ${CONF:-<none>}" >&2; exit 2; }

val() { sed -n "s/^$1=//p" "$CONF" | tail -1; }
KNOWN_HOSTS="$(val KNOWN_HOSTS)"; USER_="$(val USER)"
for v in KNOWN_HOSTS USER_; do
  [ -n "${!v}" ] || { echo "kube-tunnel: config is missing ${v%_}" >&2; exit 2; }
done

# Build the -L arguments. 127.0.0.1 explicitly on every one: these forwards ask for no credential of
# their own, so binding anything routable would publish an open door to both cluster APIs on the LAN.
FWD=()
DESC=""
while read -r lport target; do
  [ -n "$lport" ] && [ -n "$target" ] || continue
  FWD+=(-L "127.0.0.1:$lport:$target")
  DESC="$DESC 127.0.0.1:$lport->$target"
done < <(sed -n 's/^FORWARD=//p' "$CONF")
[ "${#FWD[@]}" -gt 0 ] || { echo "kube-tunnel: config declares no FORWARD lines" >&2; exit 2; }

# Host keys are PINNED. An SSH MITM on the management path cannot forge kubectl output either way — the
# API's TLS is verified end to end against the cluster CA — but it could still hijack the hop, and this
# workstation holds the admin credential. StrictHostKeyChecking=no is not appropriate here.
COMMON=(-o IdentitiesOnly=yes -o StrictHostKeyChecking=yes -o "UserKnownHostsFile=$KNOWN_HOSTS"
        -o ConnectTimeout=8 -o BatchMode=yes)

tried=()
while read -r ip key; do
  [ -n "$ip" ] || continue
  tried+=("$ip")
  # Probe with a real authenticated session, not a TCP connect: a host that answers on 22 but rejects the
  # key is useless to us, and finding that out here is what makes the fall-through work.
  ssh "${COMMON[@]}" -i "$key" "$USER_@$ip" true >/dev/null 2>&1 || continue
  echo "kube-tunnel: forwarding$DESC via $ip"
  # exec: systemd supervises the ssh process itself, not a shell wrapping it.
  exec ssh -N -T "${COMMON[@]}" -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 \
       -o ServerAliveCountMax=3 -i "$key" \
       "${FWD[@]}" "$USER_@$ip"
done < <(sed -n 's/^HOST=//p' "$CONF")

echo "kube-tunnel: no PVE host reachable — tried: ${tried[*]:-<none declared>}" >&2
exit 1
