#!/usr/bin/env bats
# Lab 08 (bonus): sbx 0.51 changes. Needs sbx 0.51.0 or later.

load ../../tests/helpers
bats_require_minimum_version 1.5.0

NAME=lab-08-check

version_ok() {
  local v
  v="$(sbx version | awk '{print $3}')"
  v="${v#v}"
  [ "$(printf '%s\n' 0.51.0 "$v" | sort -V | head -1)" = 0.51.0 ]
}

setup_file() {
  version_ok || return 0
  export WS="$BATS_FILE_TMPDIR/ws" HOSTDIR="$BATS_FILE_TMPDIR/host"
  mkdir -p "$WS/src" "$HOSTDIR/victim" "$HOSTDIR/docs"
  echo host-canary >"$HOSTDIR/canary.txt"
  echo "docs from host" >"$HOSTDIR/docs/guide.txt"
  delete_sandbox "$NAME"
  sbx create --name "$NAME" shell "$WS" "$HOSTDIR/docs:/opt/docs:ro" </dev/null >/dev/null 2>&1
  sbx run -d --name "$NAME" </dev/null >/dev/null 2>&1
}

teardown_file() {
  delete_sandbox "$NAME"
}

setup() {
  version_ok || skip "needs sbx 0.51.0 or later (found $(sbx version | awk '{print $3}'))"
}

req() {
  sx "$NAME" curl -s -o /dev/null -w '%{http_code}' --max-time 10 "https://httpbin.org$1" || true
}

@test "the CLI and the daemon both run 0.51 or later" {
  run --separate-stderr sbx diagnose --json
  [ "$(jq -r '.checks[] | select(.name == "Version match") | .status' <<<"$output")" = pass ]
}

@test "the shell agent is a published kit and records the version that created it" {
  run sbx inspect "$NAME"
  [[ "$output" == *"docker.io/sbx/shell@sha256:"* ]]
  [[ "$output" =~ Created\ with:\ +v0\.5[1-9] ]]
}

@test "a planted symlink cannot make sbx cp read a host file" {
  sx "$NAME" ln -sfn "$HOSTDIR/canary.txt" "$WS/notes.txt"
  run sbx cp "$NAME:$WS/notes.txt" "$BATS_TEST_TMPDIR/a.txt"
  [ "$status" -ne 0 ]
  run sbx cp -L "$NAME:$WS/notes.txt" "$BATS_TEST_TMPDIR/b.txt"
  [ "$status" -ne 0 ]
  [ ! -e "$BATS_TEST_TMPDIR/a.txt" ] && [ ! -e "$BATS_TEST_TMPDIR/b.txt" ]
}

@test "a planted symlink cannot make sbx cp write onto the host" {
  sx "$NAME" ln -sfn "$HOSTDIR/victim" "$WS/drop"
  sx "$NAME" ln -sfn .. "$WS/up"
  echo payload >"$BATS_TEST_TMPDIR/payload.txt"
  run sbx cp "$BATS_TEST_TMPDIR/payload.txt" "$NAME:$WS/drop/payload.txt"
  [ "$status" -ne 0 ]
  sbx cp "$BATS_TEST_TMPDIR/payload.txt" "$NAME:$WS/up/escaped.txt" || true
  [ -z "$(ls -A "$HOSTDIR/victim")" ]
  [ ! -e "$(dirname "$WS")/escaped.txt" ]
  [ "$(cat "$HOSTDIR/canary.txt")" = host-canary ]
}

@test "a query rule requires the parameter, not only it" {
  sbx policy allow network --sandbox "$NAME" httpbin.org --method GET --path /anything/report --query format=csv
  EVENTUALLY_TRIES=5 eventually bash -c "[ \"\$(sbx exec $NAME curl -s -o /dev/null -w '%{http_code}' 'https://httpbin.org/anything/report?format=csv')\" = 200 ]"
  [ "$(req '/anything/report?format=json')" = 403 ]
  [ "$(req /anything/report)" = 403 ]
  [ "$(req '/anything/report?format=CSV')" = 403 ]
  [ "$(req '/anything/report?format=csv&extra=1')" = 200 ]
  [ "$(req '/anything/report?format=cs%76')" = 200 ]
}

@test "an extra workspace can be mounted read-only at a custom target" {
  run sx "$NAME" cat /opt/docs/guide.txt
  [ "$output" = "docs from host" ]
  run sx "$NAME" touch /opt/docs/x
  [ "$status" -ne 0 ]
  run sbx inspect "$NAME"
  [[ "$output" == *"$HOSTDIR/docs:/opt/docs:ro"* ]]
}

@test "run --workdir starts the agent in a workspace subdirectory" {
  run script -qec "sbx run --rm --name lab-08-wd --workdir $WS/src shell $WS -- -c pwd" /dev/null </dev/null
  [[ "$output" == *"$WS/src"* ]]
  [ -z "$(sandbox_status lab-08-wd)" ]
}

@test "an empty --sandbox is refused instead of applying globally" {
  run sbx policy allow network --sandbox "" example.org
  [ "$status" -ne 0 ]
  [[ "$output" == *"non-empty"* ]]
}

@test "exec returns 125 when the sandbox does not exist" {
  run sbx exec lab-08-does-not-exist true
  [ "$status" -eq 125 ]
}

@test "a custom secret needs a destination host" {
  run sbx secret set-custom --sandbox "$NAME" --env NOHOST_TOKEN --value fake-nohost-123
  [ "$status" -ne 0 ]
  [[ "$output" == *"--host is required"* ]]
}

@test "copying text to the host clipboard is off by default" {
  run sbx settings ls
  [[ "$output" =~ clipboard\.textCopy\ +false ]]
}
