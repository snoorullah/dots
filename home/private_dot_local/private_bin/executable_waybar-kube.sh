#!/usr/bin/env bash
# waybar-kube.sh — current kube context/namespace of the default KUBECONFIG
# (set globally to ~/.kube/onprem-s2a.yaml in .zshenv, environment.d, hyprland.lua).
# class kube-up / kube-down from a 3s /readyz probe so an unreachable cluster shows red.
export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/onprem-s2a.yaml}"
ctx=$(kubectl config current-context 2>/dev/null)
[ -z "$ctx" ] && { printf '{"text":"󱃾 none","class":"kube-none","tooltip":"no context in %s"}\n' "$KUBECONFIG"; exit 0; }
ns=$(kubectl config view --minify -o jsonpath='{..namespace}' 2>/dev/null); ns=${ns:-default}
short=${ctx#*@}   # admin@onprem-s2a -> onprem-s2a
if timeout 3 kubectl get --raw /readyz >/dev/null 2>&1; then cls=kube-up; st=reachable; else cls=kube-down; st=UNREACHABLE; fi
printf '{"text":"󱃾 %s%s","class":"%s","tooltip":"%s · ns %s · %s\\n%s"}\n' \
  "$short" "$([ "$ns" != default ] && printf ' (%s)' "$ns")" "$cls" "$ctx" "$ns" "$st" "$KUBECONFIG"
