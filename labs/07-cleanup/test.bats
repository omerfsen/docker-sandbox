#!/usr/bin/env bats
# Lab 07: cleanup removes what the course created and nothing else.

load ../../tests/helpers

setup_file() {
  create_sandbox lab-07-check-a
  sbx create --name lab-07-check-b shell </dev/null >/dev/null 2>&1
  sbx stop lab-07-check-b >/dev/null 2>&1
}

teardown_file() {
  delete_sandbox lab-07-check-a
  delete_sandbox lab-07-check-b
}

others() {
  sbx ls -q | grep -v '^lab-' | sort
}

@test "prune --dry-run lists stopped sandboxes and removes nothing" {
  run sbx prune --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *lab-07-check-b* ]]
  [[ "$output" != *lab-07-check-a* ]]
  [ "$(sandbox_status lab-07-check-b)" = stopped ]
}

@test "the cleanup script removes lab sandboxes and workspaces only" {
  before="$(others)"
  mkdir -p "$HOME/sbx-labs/07-check"
  run "$REPO_ROOT/scripts/cleanup.sh"
  [ "$status" -eq 0 ]
  [ -z "$(sandbox_status lab-07-check-a)" ]
  [ -z "$(sandbox_status lab-07-check-b)" ]
  [ ! -d "$HOME/sbx-labs" ]
  [ "$(others)" = "$before" ]
}

@test "sbx is still healthy after cleanup" {
  run sbx diagnose --json
  [ "$(jq -r .summary.fail <<<"$output")" = 0 ]
}
