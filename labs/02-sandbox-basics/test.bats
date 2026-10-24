#!/usr/bin/env bats
# Lab 02: sandbox lifecycle, exec, workspace, and cp with the shell agent.

load ../../tests/helpers
bats_require_minimum_version 1.5.0

NAME=lab-02-basics

setup_file() {
  export WS="$BATS_FILE_TMPDIR/ws"
  mkdir -p "$WS"
  echo "hello from the host" >"$WS/README.txt"
  create_sandbox "$NAME" "$WS"
}

teardown_file() {
  delete_sandbox "$NAME"
  delete_sandbox lab-02-idle
  delete_sandbox lab-02-nows
  delete_sandbox lab-02-once
}

@test "the sandbox is listed with its workspace" {
  run sbx ls --json
  [ "$(jq -r --arg n "$NAME" '.[] | select(.name == $n) | .workspaces[0]' <<<"$output")" = "$WS" ]
  [ "$(sandbox_status "$NAME")" = running ]
}

@test "the sandbox runs its own kernel, not the host's" {
  run sx "$NAME" uname -r
  [ "$status" -eq 0 ]
  [ "$output" != "$(uname -r)" ]
}

@test "the workspace is shared both ways at the same path" {
  run sx "$NAME" sh -c 'pwd; cat README.txt'
  [ "${lines[0]}" = "$WS" ]
  [ "${lines[1]}" = "hello from the host" ]
  sx "$NAME" sh -c 'echo from-sandbox > from-sandbox.txt'
  [ "$(cat "$WS/from-sandbox.txt")" = from-sandbox ]
}

@test "the agent user is not root and cannot write /etc" {
  run sx "$NAME" id -u
  [ "$output" -ne 0 ]
  run sx "$NAME" sh -c 'touch /etc/probe'
  [ "$status" -ne 0 ]
}

@test "root inside the VM is available through sudo and -u root" {
  run sx "$NAME" sudo -n id -u
  [ "$output" = 0 ]
  run sbx exec -u root "$NAME" id -u
  [ "$output" = 0 ]
}

@test "exec propagates the exit code" {
  run sx "$NAME" sh -c 'exit 3'
  [ "$status" -eq 3 ]
}

@test "exec passes stdin and per-command env" {
  run bash -c "echo piped | sbx exec -i $NAME cat"
  [ "$output" = piped ]
  run sbx exec -e GREETING=merhaba "$NAME" sh -c 'echo $GREETING'
  [ "$output" = merhaba ]
}

@test "a created sandbox stops when idle and exec starts it again" {
  sbx create --name lab-02-idle shell "$WS" </dev/null >/dev/null 2>&1
  EVENTUALLY_TRIES=20 EVENTUALLY_DELAY=3 eventually bash -c '[ "$(sbx ls --json | jq -r ".[] | select(.name == \"lab-02-idle\") | .status")" = stopped ]'
  run --separate-stderr sbx exec lab-02-idle cat README.txt
  [ "$status" -eq 0 ]
  [ "$output" = "hello from the host" ]
  [[ "$stderr" == *"started"* ]]
}

@test "a sandbox started with run -d stays running" {
  sleep 35
  [ "$(sandbox_status "$NAME")" = running ]
}

@test "stop keeps files inside the VM" {
  sx "$NAME" sh -c 'echo kept > ~/keep.txt'
  sbx stop "$NAME"
  [ "$(sandbox_status "$NAME")" = stopped ]
  run --separate-stderr sbx exec "$NAME" cat /home/agent/keep.txt
  [ "$output" = kept ]
}

@test "cp copies files in and out" {
  echo "copied in" >"$BATS_TEST_TMPDIR/in.txt"
  sbx cp "$BATS_TEST_TMPDIR/in.txt" "$NAME:/home/agent/"
  run --separate-stderr sbx exec "$NAME" cat /home/agent/in.txt
  [ "$output" = "copied in" ]
  sbx cp "$NAME:/home/agent/keep.txt" "$BATS_TEST_TMPDIR/"
  [ "$(cat "$BATS_TEST_TMPDIR/keep.txt")" = kept ]
}

@test "cp copies a symlink as a link unless -L is given" {
  sbx cp "$NAME:/etc/os-release" "$BATS_TEST_TMPDIR/link"
  [ -L "$BATS_TEST_TMPDIR/link" ]
  sbx cp -L "$NAME:/etc/os-release" "$BATS_TEST_TMPDIR/real"
  [ -f "$BATS_TEST_TMPDIR/real" ] && [ ! -L "$BATS_TEST_TMPDIR/real" ]
  grep -q '^PRETTY_NAME=' "$BATS_TEST_TMPDIR/real"
}

@test "cp can write where the agent user cannot" {
  echo x >"$BATS_TEST_TMPDIR/in.txt"
  sbx cp "$BATS_TEST_TMPDIR/in.txt" "$NAME:/etc/"
  run --separate-stderr sbx exec "$NAME" cat /etc/in.txt
  [ "$output" = x ]
}

@test "without a workspace the agent starts in the VM's own directory" {
  sbx create --name lab-02-nows shell </dev/null >/dev/null 2>&1
  run --separate-stderr sbx exec lab-02-nows pwd
  [ "$output" = /home/agent/workspace ]
  run sbx ls --json
  [ "$(jq -r '.[] | select(.name == "lab-02-nows") | .workspaces | length' <<<"$output")" = 0 ]
}

@test "run --rm removes the sandbox when the session ends" {
  # run needs a terminal for the agent session; script gives it one.
  run script -qec "sbx run --rm --name lab-02-once shell $WS -- -c 'echo once-ok'" /dev/null </dev/null
  [[ "$output" == *once-ok* ]]
  [ -z "$(sandbox_status lab-02-once)" ]
}

@test "rm refuses without a terminal unless --force is given" {
  run sbx rm lab-02-nows </dev/null
  [ "$status" -ne 0 ]
  [[ "$output" == *"--force"* ]]
  run sbx rm --force lab-02-nows
  [ "$status" -eq 0 ]
  [ -z "$(sandbox_status lab-02-nows)" ]
}
