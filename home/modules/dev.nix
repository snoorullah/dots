{ pkgs, ... }:

# Phase 3 — dev toolchains + infra/devops tooling.
# Captures the pnow-ats-v2 devenv stack (Node22/pnpm, Python313/uv, Go1.24, Rust
# stable + kubectl/helm/azure-cli/gh/postgres/redis/mc/jq/yq/just/gitleaks) plus
# the broader infra set the user asked for. Per-project `devenv.nix` shells still
# layer their own pinned tools on top via direnv.
{
  # direnv + nix-direnv so per-repo `.envrc`/`devenv.nix` (like ats-v2) auto-load.
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

  home.packages = with pkgs; [
    # ── Node / JS ──
    nodejs_22            # includes corepack; `corepack enable` gives pnpm/yarn
    pnpm                 # explicit pnpm too (matches ats-v2)

    # ── Python ──
    python313
    uv
    pipx
    ruff

    # ── Rust (stable toolchain) ──
    rustc
    cargo
    clippy
    rustfmt
    rust-analyzer

    # ── Go ── (default = latest; per-project devenv pins the exact minor)
    go
    gopls
    delve
    go-tools             # staticcheck et al.

    # ── Kubernetes / cloud ──
    kubectl
    kubernetes-helm
    k9s
    kubectx
    kustomize
    azure-cli
    gh

    # ── IaC / config mgmt ──
    terraform            # unfree (BSL); allowUnfree is on at system level
    ansible

    # ── Containers (daemon is enabled at SYSTEM level; these are client-side) ──
    docker-compose
    lazydocker
    dive

    # ── DB clients ──
    postgresql_16        # psql
    redis                # redis-cli
    minio-client         # mc

    # ── Dev CLIs ──
    devenv               # the cachix devenv runner (ats-v2 uses it)
    just
    yq-go
    gitleaks
    lazygit
    git-lfs
    jq

    # NOTE — deliberately NOT installed globally (they collide or belong to
    # per-project devenv shells, which provide them via direnv):
    #   • go-task  — its binary is ALSO `task`, which would collide with
    #                taskwarrior's `task` (the time-tracking prosthetic owns it).
    #   • secretspec, aicommits, commitlint — newer/npm tools not in nixpkgs;
    #                come from each repo's devenv.nix / pnpm devDeps.
  ];
}
