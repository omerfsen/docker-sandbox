#!/usr/bin/env bats
# Lab 01: sbx is installed at the course version, held, signed in, and healthy.

load ../../tests/helpers

setup_file() {
  export DIAG="$BATS_FILE_TMPDIR/diagnose.json"
  sbx diagnose --json >"$DIAG" 2>/dev/null || true
}

check_status() {
  jq -r --arg n "$1" '.checks[] | select(.name == $n) | .status' "$DIAG"
}

@test "CLI is the course version" {
  run sbx version
  [ "$status" -eq 0 ]
  [[ "$output" == "sbx version v${TRAINING_VERSION} "* ]]
}

@test "the docker-sbx package is held at the course version" {
  run dpkg-query -W -f '${Version}' docker-sbx
  [[ "$output" == "${TRAINING_VERSION}-"* ]]
  run apt-mark showhold
  [[ "$output" == *docker-sbx* ]]
}

@test "the daemon is running" {
  run sbx daemon status
  [ "$status" -eq 0 ]
  [[ "$output" == *"running"* ]]
}

@test "diagnose reports no failures" {
  [ "$(jq -r '.summary.fail' "$DIAG")" = 0 ]
}

@test "the daemon runs the same version as the CLI" {
  [ "$(check_status 'Version match')" = pass ]
}

@test "the daemon can use KVM" {
  [ "$(check_status 'Virtualization')" = pass ]
}

@test "you are signed in to Docker" {
  [ "$(check_status 'Authentication')" = pass ]
}

@test "the global network policy is initialized" {
  [ "$(check_status 'Global network policy')" = pass ]
}
