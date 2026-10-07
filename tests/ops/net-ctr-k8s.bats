load helpers
bats_require_minimum_version 1.5.0
# Network, containers and cluster domain: net-watch, containers, containers-prune, k8s-health.
# Every external tool is a stub in $BATS_TEST_TMPDIR/bin (first on PATH); nothing touches the real docker/kubectl/systemctl.
UJ="$BATS_TEST_DIRNAME/../../home/private_dot_local/lib/dots-ops/jobs"

mkstub() { printf '#!/bin/sh\n%s\n' "$2" > "$BIN/$1"; chmod +x "$BIN/$1"; }

setup() {
  setup_ops
  export BIN="$BATS_TEST_TMPDIR/bin"; mkdir -p "$BIN"
  export STUB_LOG="$BATS_TEST_TMPDIR/calls.log"; : > "$STUB_LOG"
  export OPS_ASK_UI=0 KDIR="$BATS_TEST_TMPDIR/kube"; mkdir -p "$KDIR"
  mkstub getent 'exit ${STUB_DNS_RC:-0}'
  mkstub curl 'exit ${STUB_NET_RC:-0}'
  # systemctl --user <verb> ... <unit>.service ; STUB_NOUNIT / STUB_COND_NO / STUB_INACTIVE are space-separated unit names
  mkstub systemctl 'echo "systemctl $*" >> "$STUB_LOG"
verb=$2; for last; do :; done; u=${last%.service}
has() { case " $1 " in *" $u "*) return 0 ;; esac; return 1; }
case $verb in
  cat) has "$STUB_NOUNIT" && exit 1; exit 0 ;;
  show) has "$STUB_COND_NO" && echo no || echo yes; exit 0 ;;
  is-active) has "$STUB_INACTIVE" && exit 3; exit 0 ;;
esac
exit 0'
  mkstub docker 'echo "docker $*" >> "$STUB_LOG"
case "$1 $2" in
  "info "*) exit ${STUB_DOCKER_INFO_RC:-0} ;;
  "system df") printf "%b" "$STUB_DF_OUT" ;;
  "ps --filter") case "$3" in health=unhealthy) printf "%b" "$STUB_UNHEALTHY" ;; status=restarting) printf "%b" "$STUB_RESTARTING" ;; esac ;;
esac
exit 0'
  # kubectl: files in $KDIR: <ctx>.down | <ctx>.nodes | <ctx>.pods | <ctx>.certs | <ctx>.apps ; <ctx>.crd-cert / .crd-argo = CRD exists
  mkstub kubectl 'echo "kubectl $*" >> "$STUB_LOG"
[ "$3" = "--request-timeout=10s" ] || exit 9
c=$2; shift 3
[ -e "$KDIR/$c.down" ] && exit 1
case "$1 $2" in
  "get nodes")  cat "$KDIR/$c.nodes" 2>/dev/null || echo "{\"items\":[]}" ;;
  "get pods")   cat "$KDIR/$c.pods" 2>/dev/null || echo "{\"items\":[]}" ;;
  "get crd")    case $3 in certificates.cert-manager.io) [ -e "$KDIR/$c.crd-cert" ] ;; applications.argoproj.io) [ -e "$KDIR/$c.crd-argo" ] ;; esac ;;
  "get certificates.cert-manager.io") cat "$KDIR/$c.certs" ;;
  "get applications.argoproj.io") cat "$KDIR/$c.apps" ;;
esac'
  export PATH="$BIN:$PATH"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  ops_cfg() { echo "$2"; }
}
runjob() { source "$1"; job_main; }
# PATH with the usual coreutils but no docker/kubectl (the real ones live in /usr/bin): symlink farm of what the jobs need
minpath() {
  local m="$BATS_TEST_TMPDIR/min" t; mkdir -p "$m"
  for t in jq sed awk grep sort paste head date cat stat mv mkdir tr basename wc find rm dirname env bash sh uniq pkill; do
    ln -sf "$(command -v $t)" "$m/$t" 2>/dev/null || true
  done
  ln -sf "$BIN/systemctl" "$m/systemctl"
  echo "$m"
}
ustate() { jq -r ".$2" "$OPS_STATE/state/$1.json"; }

# ---- net-watch ----
@test "net-watch: online, tunnels active -> ok" {
  runjob "$UJ/net-watch.sh"
  [ "$(ustate net-watch status)" = ok ]
  ! grep -q 'restart' "$STUB_LOG"
}
@test "net-watch: DNS and connectivity both down -> warn offline, tunnels not touched" {
  STUB_DNS_RC=2 STUB_NET_RC=6 STUB_INACTIVE="onprem-kube-tunnel" runjob "$UJ/net-watch.sh"
  [ "$(ustate net-watch status)" = warn ]
  [ "$(ustate net-watch summary)" = offline ]
  ! grep -q 'restart' "$STUB_LOG"
}
@test "net-watch: inactive tunnel restarted once and recorded, still inactive next run -> fail naming it" {
  export STUB_INACTIVE="ovh-k8s-tunnel"
  runjob "$UJ/net-watch.sh"
  [ "$(ustate net-watch status)" = warn ]
  [ "$(grep -c 'systemctl --user restart ovh-k8s-tunnel.service' "$STUB_LOG")" = 1 ]
  [ -n "$(jq -r '.["ovh-k8s-tunnel"].restarted_at' "$OPS_STATE/net-watch-tunnels.json")" ]
  ! grep -q 'restart onprem' "$STUB_LOG"
  runjob "$UJ/net-watch.sh"
  [ "$(ustate net-watch status)" = fail ]
  [[ "$(ustate net-watch summary)" == *ovh-k8s-tunnel* ]]
  [ "$(grep -c 'restart' "$STUB_LOG")" = 1 ]   # no second restart
}
@test "net-watch: tunnel that recovers clears its restarted_at" {
  STUB_INACTIVE="ovh-k8s-tunnel" runjob "$UJ/net-watch.sh"
  runjob "$UJ/net-watch.sh"   # active again (no STUB_INACTIVE)
  [ "$(ustate net-watch status)" = ok ]
  [ "$(jq -r 'has("ovh-k8s-tunnel")' "$OPS_STATE/net-watch-tunnels.json")" = false ]
}
@test "net-watch: condition not met or unit missing -> n/a, never restarted or failed" {
  export STUB_INACTIVE="onprem-kube-tunnel ovh-k8s-tunnel" STUB_COND_NO="onprem-kube-tunnel" STUB_NOUNIT="ovh-k8s-tunnel"
  runjob "$UJ/net-watch.sh"
  runjob "$UJ/net-watch.sh"
  [ "$(ustate net-watch status)" = ok ]
  ! grep -q 'restart' "$STUB_LOG"
}
@test "net-watch: tailscale present but not Running -> warn; absent -> ignored" {
  mkstub tailscale 'echo "{\"BackendState\":\"NeedsLogin\"}"'
  runjob "$UJ/net-watch.sh"
  [ "$(ustate net-watch status)" = warn ]
  [[ "$(ustate net-watch summary)" == *tailscale* ]]
  mkstub tailscale 'echo "{\"BackendState\":\"Running\"}"'
  runjob "$UJ/net-watch.sh"
  [ "$(ustate net-watch status)" = ok ]
}

# ---- containers ----
@test "containers: docker missing or daemon down -> ok n/a" {
  PATH="$(minpath)" runjob "$UJ/containers.sh"
  [ "$(ustate containers status)" = ok ]
  [[ "$(ustate containers summary)" == "n/a: docker unavailable" ]]
  STUB_DOCKER_INFO_RC=1 runjob "$UJ/containers.sh"
  [[ "$(ustate containers summary)" == "n/a: docker unavailable" ]]
}
@test "containers: unhealthy and restarting containers -> warn listing names" {
  STUB_UNHEALTHY='web\n' STUB_RESTARTING='worker\n' runjob "$UJ/containers.sh"
  [ "$(ustate containers status)" = warn ]
  [[ "$(ustate containers summary)" == *web* && "$(ustate containers summary)" == *worker* ]]
}
@test "containers: all healthy -> ok" {
  runjob "$UJ/containers.sh"
  [ "$(ustate containers status)" = ok ]
}

# ---- containers-prune ----
dfout() { printf '%s\n' "{\"Type\":\"Images\",\"Reclaimable\":\"$1 (50%)\"}" "{\"Type\":\"Local Volumes\",\"Reclaimable\":\"$2 (90%)\"}" "{\"Type\":\"Build Cache\",\"Reclaimable\":\"$3\"}"; }
@test "containers-prune: heavy job; prunes dangling images, no ask under 10 GB" {
  grep -q '^OPS_HEAVY=1' "$UJ/containers-prune.sh"
  STUB_DF_OUT="$(dfout 2GB 3.5GB 500MB)\n" runjob "$UJ/containers-prune.sh"
  grep -q 'docker image prune -f' "$STUB_LOG"
  [ ! -e "$OPS_STATE/pending/containers-prune.json" ]
  [ "$(ustate containers-prune status)" = ok ]
}
@test "containers-prune: > 10 GB reclaimable (mixed units) -> asks with the root volumes action" {
  STUB_DF_OUT="$(dfout 4GB 8000MB 1.5GB)\n" runjob "$UJ/containers-prune.sh"
  [ "$(jq -r .action "$OPS_STATE/pending/containers-prune.json")" = "root:containers-prune volumes" ]
  [[ "$(jq -r .question "$OPS_STATE/pending/containers-prune.json")" == "Reclaim 14 GB (anonymous volumes and unused data; named volumes are kept on Docker"* ]]
}
@test "containers-prune: kB/TB units parse; dry-run prints the prune instead of running it" {
  source "$UJ/containers-prune.sh"
  [ "$(printf '1500kB\n2TB (1%%)\n' | _cp_bytes)" = 2000001500000 ]
  DOTS_OPS_DRY_RUN=1 STUB_DF_OUT="$(dfout 1GB 1GB 1GB)\n" run job_main
  [[ "$output" == *"+ docker image prune -f"* ]]
  ! grep -q 'docker image prune' "$STUB_LOG"
}
@test "containers-prune: docker unavailable -> ok n/a" {
  STUB_DOCKER_INFO_RC=1 runjob "$UJ/containers-prune.sh"
  [ "$(ustate containers-prune status)" = ok ]
  ! grep -q 'prune' "$STUB_LOG"
}

# ---- k8s-health ----
k8s_ctx() { ops_cfg() { if [ "$1" = k8s.contexts ]; then printf -- '- %s\n' "$K8S_CTX"; else echo "$2"; fi; }; }
bad_pod() { printf '{"items":[{"metadata":{"namespace":"app","name":"%s"},"status":{"containerStatuses":[{"state":{"waiting":{"reason":"CrashLoopBackOff"}}}]}}]}' "$1" > "$KDIR/c1.pods"; }
@test "k8s-health: no kubectl -> ok n/a" {
  k8s_ctx; K8S_CTX=c1
  PATH="$(minpath)" runjob "$UJ/k8s-health.sh"
  [ "$(ustate k8s-health status)" = ok ]
  [[ "$(ustate k8s-health summary)" == n/a* ]]
}
@test "k8s-health: no contexts -> ok n/a; list from yq is parsed" {
  runjob "$UJ/k8s-health.sh"
  [[ "$(ustate k8s-health summary)" == n/a* ]]
  ops_cfg() { if [ "$1" = k8s.contexts ]; then printf -- '- admin@onprem-s2a\n- ovh\n'; else echo "$2"; fi; }
  runjob "$UJ/k8s-health.sh"
  grep -q 'kubectl --context admin@onprem-s2a --request-timeout=10s get nodes' "$STUB_LOG"
  grep -q 'kubectl --context ovh --request-timeout=10s get nodes' "$STUB_LOG"
}
@test "k8s-health: same issue twice -> one notification; new issue -> second; cleared -> recovered" {
  k8s_ctx; export K8S_CTX=c1
  bad_pod p1
  runjob "$UJ/k8s-health.sh"
  [ "$(ustate k8s-health status)" = warn ]
  [[ "$(ustate k8s-health summary)" == *"c1/pod/app/p1/CrashLoopBackOff"* ]]
  [ "$(notified)" = 1 ]
  runjob "$UJ/k8s-health.sh"
  [ "$(notified)" = 1 ]
  printf '{"items":[{"metadata":{"namespace":"app","name":"p1"},"status":{"containerStatuses":[{"state":{"waiting":{"reason":"CrashLoopBackOff"}}}]}},{"metadata":{"namespace":"app","name":"p2"},"status":{"initContainerStatuses":[{"state":{"waiting":{"reason":"ImagePullBackOff"}}}]}}]}' > "$KDIR/c1.pods"
  runjob "$UJ/k8s-health.sh"
  [ "$(notified)" = 2 ]
  tail -n 1 "$NOTIFY_LOG" | grep -q 'c1/pod/app/p2/ImagePullBackOff'
  runjob "$UJ/k8s-health.sh"
  [ "$(notified)" = 2 ]
  echo '{"items":[]}' > "$KDIR/c1.pods"
  runjob "$UJ/k8s-health.sh"
  [ "$(ustate k8s-health status)" = ok ]
  [ "$(notified)" = 3 ]
  tail -n 1 "$NOTIFY_LOG" | grep -q 'recovered'
}
@test "k8s-health: unreachable context -> warn '<ctx> unreachable', not fail" {
  k8s_ctx; export K8S_CTX=c1; touch "$KDIR/c1.down"
  runjob "$UJ/k8s-health.sh"
  [ "$(ustate k8s-health status)" = warn ]
  [[ "$(ustate k8s-health summary)" == *"c1 unreachable"* ]]
}
@test "k8s-health: NotReady node, expiring certificate and out-of-sync app (CRDs present)" {
  k8s_ctx; export K8S_CTX=c1
  echo '{"items":[{"metadata":{"name":"n1"},"status":{"conditions":[{"type":"Ready","status":"False"}]}}]}' > "$KDIR/c1.nodes"
  soon=$(date -u -d '+3 days' +%Y-%m-%dT%H:%M:%SZ); later=$(date -u -d '+60 days' +%Y-%m-%dT%H:%M:%SZ)
  touch "$KDIR/c1.crd-cert" "$KDIR/c1.crd-argo"
  printf '{"items":[{"metadata":{"namespace":"d","name":"soon"},"status":{"notAfter":"%s"}},{"metadata":{"namespace":"d","name":"later"},"status":{"notAfter":"%s"}}]}' "$soon" "$later" > "$KDIR/c1.certs"
  echo '{"items":[{"metadata":{"namespace":"argocd","name":"app1"},"status":{"sync":{"status":"OutOfSync"},"health":{"status":"Healthy"}}},{"metadata":{"namespace":"argocd","name":"app2"},"status":{"sync":{"status":"Synced"},"health":{"status":"Healthy"}}}]}' > "$KDIR/c1.apps"
  runjob "$UJ/k8s-health.sh"
  keys=$(jq -r '.keys[]' "$OPS_STATE/k8s-issues.json")
  [[ "$keys" == *"c1/node/-/n1/NotReady"* ]]
  [[ "$keys" == *"c1/certificate/d/soon/expiring"* ]]
  [[ "$keys" != *"later"* ]]
  [[ "$keys" == *"c1/application/argocd/app1/OutOfSync"* ]]
  [[ "$keys" != *"app2"* ]]
  [[ "$(ustate k8s-health summary)" == "3 issue(s):"* ]]
}
@test "k8s-health: cert-manager/argocd checks skipped when the CRD is absent" {
  k8s_ctx; export K8S_CTX=c1
  runjob "$UJ/k8s-health.sh"
  ! grep -q 'get certificates' "$STUB_LOG"
  ! grep -q 'get applications' "$STUB_LOG"
}

# ---- timers ----
@test "timers: net-watch/k8s-health use boot+active, containers is hourly Persistent" {
  T="$BATS_TEST_DIRNAME/../../home/private_dot_config/systemd/private_user"
  grep -q '^OnBootSec=2min' "$T/dots-ops-net-watch.timer"; grep -q '^OnUnitActiveSec=5min' "$T/dots-ops-net-watch.timer"
  grep -q '^OnBootSec=5min' "$T/dots-ops-k8s-health.timer"; grep -q '^OnUnitActiveSec=15min' "$T/dots-ops-k8s-health.timer"
  grep -q '^OnCalendar=hourly' "$T/dots-ops-containers.timer"; grep -q '^Persistent=true' "$T/dots-ops-containers.timer"
  for j in net-watch k8s-health containers; do grep -q "^Unit=dots-ops@$j.service" "$T/dots-ops-$j.timer"; done
}
