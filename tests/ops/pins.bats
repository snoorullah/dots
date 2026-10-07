load helpers
setup() {
  setup_ops; export OPS_ASK_UI=0
  export OPS_DOTS_REPO="$BATS_TEST_TMPDIR/repo" OPS_JOBS_DIR="$BATS_TEST_DIRNAME/../../home/private_dot_local/lib/dots-ops/jobs"
  export OPS_CONFIG="$BATS_TEST_TMPDIR/none.toml" OPS_LIB="$BATS_TEST_DIRNAME/../../home/private_dot_local/lib/dots-ops/lib.sh"
  mkdir -p "$OPS_DOTS_REPO/home/.chezmoidata" "$OPS_DOTS_REPO/nix"
  cat > "$OPS_DOTS_REPO/home/.chezmoidata/extra-tools.yaml" <<'YAML'
extraTools:
  npm:   [ { name: agent-browser, version: 0.27.1 }, { name: "@mariozechner/pi-mom", version: 0.66.1 } ]
  cargo: [ { crate: tttui, version: 0.1.0 } ]
  pipx:  [ { name: ytm-player, version: 2.0.0 } ]
  uv:    [ { name: syncall, version: 1.8.8, python: "3.12.5" } ]
YAML
  printf '{"nodes":{"nixpkgs":{"locked":{"lastModified":%s}}}}' "$(date +%s)" > "$OPS_DOTS_REPO/nix/flake.lock"
  export PATH="$BATS_TEST_DIRNAME/stubs:$PATH" PINS_FIXTURES="$BATS_TEST_DIRNAME/fixtures/pins"
  BIN="$BATS_TEST_DIRNAME/../../home/private_dot_local/private_bin"
}
# a real repo (branch main) with a local bare origin, all under BATS_TEST_TMPDIR
git_repo() {
  export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
  git init -q --bare "$BATS_TEST_TMPDIR/origin.git"
  git -C "$OPS_DOTS_REPO" init -q -b main
  git -C "$OPS_DOTS_REPO" add -A && git -C "$OPS_DOTS_REPO" commit -qm init
  git -C "$OPS_DOTS_REPO" remote add origin "$BATS_TEST_TMPDIR/origin.git"
  git -C "$OPS_DOTS_REPO" push -q origin main
}
cands() {
  printf '[{"kind":"npm","name":"agent-browser","from":"0.27.1","to":"0.28.0","auto":true},{"kind":"uv","name":"syncall","from":"1.8.8","to":"1.9.0","auto":false}]' > "$OPS_STATE/pins-candidates.json"
}
@test "all current -> ok, no ask" {
  export PINS_FIXTURE_SET=current
  bash "$BIN/executable_dots-ops-job" pins-check
  [ "$(jq -r .status "$OPS_STATE/state/pins-check.json")" = ok ]
  [ ! -e "$OPS_STATE/pending/pins-check.json" ]
}
@test "newer npm + cargo -> warn, candidates, ask with pins-bump" {
  export PINS_FIXTURE_SET=newer
  bash "$BIN/executable_dots-ops-job" pins-check
  [ "$(jq -r .status "$OPS_STATE/state/pins-check.json")" = warn ]
  [ "$(jq -r '[.[]|select(.auto)]|length' "$OPS_STATE/pins-candidates.json")" = 2 ]
  [ "$(jq -r .action "$OPS_STATE/pending/pins-check.json")" = "user:dots-ops pins-bump" ]
}
@test "newer uv is reported but never auto-bumped" {
  export PINS_FIXTURE_SET=newer
  bash "$BIN/executable_dots-ops-job" pins-check
  [ "$(jq -r '.[]|select(.name=="syncall").auto' "$OPS_STATE/pins-candidates.json")" = false ]
}
@test "scoped npm name is fetched (%2F) and compared" {
  mkdir -p "$BATS_TEST_TMPDIR/fx/newer"
  cp "$PINS_FIXTURES"/newer/* "$BATS_TEST_TMPDIR/fx/newer/"
  printf '{"version":"0.70.0"}' > "$BATS_TEST_TMPDIR/fx/newer/registry.npmjs.org__mariozechner_2Fpi-mom_latest.json"
  export PINS_FIXTURE_SET=newer PINS_FIXTURES="$BATS_TEST_TMPDIR/fx"
  bash "$BIN/executable_dots-ops-job" pins-check
  [ "$(jq -r '.[]|select(.name=="@mariozechner/pi-mom").to' "$OPS_STATE/pins-candidates.json")" = 0.70.0 ]
}
@test "stale nixpkgs lock -> warn even with current pins" {
  export PINS_FIXTURE_SET=current
  printf '{"nodes":{"nixpkgs":{"locked":{"lastModified":%s}}}}' $(( $(date +%s) - 40*86400 )) > "$OPS_DOTS_REPO/nix/flake.lock"
  bash "$BIN/executable_dots-ops-job" pins-check
  jq -r .summary "$OPS_STATE/state/pins-check.json" | grep -q 'nixpkgs lock 40 days old'
}
@test "registry unreachable -> warn 'check failed', no candidates" {
  export PINS_FIXTURE_SET=offline
  bash "$BIN/executable_dots-ops-job" pins-check
  [ "$(jq -r .status "$OPS_STATE/state/pins-check.json")" = warn ]
  jq -r .summary "$OPS_STATE/state/pins-check.json" | grep -q 'check failed'
  [ "$(jq length "$OPS_STATE/pins-candidates.json")" = 0 ]
}
@test "pins-bump dry-run edits only auto candidates and prints branch, test, push, PR" {
  git_repo; cands
  DOTS_OPS_DRY_RUN=1 run bash "$BIN/executable_dots-ops" pins-bump
  [ "$status" = 0 ]
  [[ $output == *"git -C"*"worktree add -b pins/"* ]]
  [[ $output == *"tests/extra-tools-dryrun.sh"* ]] && [[ $output == *"gh pr create"* ]]
  [[ $output == *"git -C"*"push"*"pins/"* ]]
  [[ $output == *"agent-browser 0.27.1 -> 0.28.0"* ]]
  [[ $output != *'select(.name == "syncall")'* ]] && [[ $output != *"pins_set_version uv"* ]]
}
@test "pins-bump never pushes to main/master" {
  git_repo; cands
  DOTS_OPS_DRY_RUN=1 run bash "$BIN/executable_dots-ops" pins-bump
  [[ $output != *"push"*" main"* ]] && [[ $output != *"push"*" master"* ]]
  [[ $output == *"push -q -u origin pins/"* ]]
}
@test "pins-bump refuses with uncommitted changes in the edited files" {
  git_repo; cands
  echo "# local" >> "$OPS_DOTS_REPO/home/.chezmoidata/extra-tools.yaml"
  DOTS_OPS_DRY_RUN=1 run bash "$BIN/executable_dots-ops" pins-bump
  [ "$status" = 1 ]
  [ "$(jq -r .status "$OPS_STATE/state/pins-check.json")" = fail ]
  [[ $output != *"worktree add"* ]]
}
@test "pins-bump branch gets -2 when pins/<date> already exists on origin" {
  git_repo; cands
  git -C "$OPS_DOTS_REPO" push -q origin "main:refs/heads/pins/$(date +%Y%m%d)"
  DOTS_OPS_DRY_RUN=1 run bash "$BIN/executable_dots-ops" pins-bump
  [[ $output == *"worktree add -b pins/$(date +%Y%m%d)-2 "* ]]
}
@test "pins-bump real run: format-preserving edit, only auto candidates (stubbed nix/gh)" {
  mkdir -p "$BATS_TEST_TMPDIR/bin" "$OPS_DOTS_REPO/tests"
  printf '#!/bin/sh\nexit 0\n' > "$BATS_TEST_TMPDIR/bin/nix"
  printf '#!/bin/sh\necho https://example.invalid/pr/1\n' > "$BATS_TEST_TMPDIR/bin/gh"
  printf '#!/bin/sh\nexit 0\n' > "$OPS_DOTS_REPO/tests/extra-tools-dryrun.sh"
  chmod +x "$BATS_TEST_TMPDIR"/bin/* "$OPS_DOTS_REPO/tests/extra-tools-dryrun.sh"
  git_repo; cands
  PATH="$BATS_TEST_TMPDIR/bin:$PATH" run bash "$BIN/executable_dots-ops" pins-bump
  [ "$status" = 0 ]
  br="pins/$(date +%Y%m%d)"
  [[ $(git -C "$BATS_TEST_TMPDIR/origin.git" diff --shortstat main "$br") == *"1 file changed, 1 insertion(+), 1 deletion(-)"* ]]
  git -C "$BATS_TEST_TMPDIR/origin.git" show "$br:home/.chezmoidata/extra-tools.yaml" | grep -q 'name: agent-browser, version: 0.28.0'
  git -C "$BATS_TEST_TMPDIR/origin.git" show "$br:home/.chezmoidata/extra-tools.yaml" | grep -q 'name: syncall, version: 1.8.8'
  [[ $output == *"https://example.invalid/pr/1"* ]]
  [ ! -e "$OPS_STATE/pins-wt" ]
}
@test "R51 pin-only bump does not run nix flake update (fresh lock)" {
  git_repo; cands
  DOTS_OPS_DRY_RUN=1 run bash "$BIN/executable_dots-ops" pins-bump
  [ "$status" = 0 ]
  [[ $output != *"nix flake update"* ]]
}
@test "R51 stale lock runs nix flake update, even with no auto candidates" {
  printf '{"nodes":{"nixpkgs":{"locked":{"lastModified":%s}}}}' $(( $(date +%s) - 40*86400 )) > "$OPS_DOTS_REPO/nix/flake.lock"
  git_repo
  printf '[]' > "$OPS_STATE/pins-candidates.json"
  DOTS_OPS_DRY_RUN=1 run bash "$BIN/executable_dots-ops" pins-bump
  [ "$status" = 0 ]
  [[ $output == *"nix flake update --flake"* ]]
  [[ $output != *"pins_set_version"* ]]
}
@test "R51 OPS_LOCK_MAX_DAYS raises the threshold" {
  printf '{"nodes":{"nixpkgs":{"locked":{"lastModified":%s}}}}' $(( $(date +%s) - 40*86400 )) > "$OPS_DOTS_REPO/nix/flake.lock"
  git_repo; cands
  OPS_LOCK_MAX_DAYS=60 DOTS_OPS_DRY_RUN=1 run bash "$BIN/executable_dots-ops" pins-bump
  [[ $output != *"nix flake update"* ]]
}
@test "odd pin: worktree and local branch are removed, next run is not blocked" {
  git_repo
  printf '[{"kind":"npm","name":"bad name","from":"1.0.0","to":"1.1.0","auto":true}]' > "$OPS_STATE/pins-candidates.json"
  run bash "$BIN/executable_dots-ops" pins-bump
  [ "$status" = 1 ]
  [[ $output == *"refusing odd pin"* ]]
  [ ! -e "$OPS_STATE/pins-wt" ]
  [ -z "$(git -C "$OPS_DOTS_REPO" branch --list 'pins/*')" ]
  run bash "$BIN/executable_dots-ops" pins-bump
  [[ $output == *"refusing odd pin"* ]] && [[ $output != *"stale worktree"* ]]
}
@test "malformed registry version is skipped and counted as check failed" {
  mkdir -p "$BATS_TEST_TMPDIR/fx/newer"
  cp "$PINS_FIXTURES"/newer/* "$BATS_TEST_TMPDIR/fx/newer/"
  printf '{"version":"1.0 $(evil)"}' > "$BATS_TEST_TMPDIR/fx/newer/registry.npmjs.org_agent-browser_latest.json"
  export PINS_FIXTURE_SET=newer PINS_FIXTURES="$BATS_TEST_TMPDIR/fx"
  bash "$BIN/executable_dots-ops-job" pins-check
  [ "$(jq '[.[]|select(.name=="agent-browser")]|length' "$OPS_STATE/pins-candidates.json")" = 0 ]
  jq -r .summary "$OPS_STATE/state/pins-check.json" | grep -q 'check failed'
}
