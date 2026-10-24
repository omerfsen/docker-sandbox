#!/usr/bin/env bats
# Lab 06: Claude Code in a sandbox. The checks that talk to Anthropic run only
# when an anthropic secret is stored (sbx secret set anthropic); they spend a
# few cents.

load ../../tests/helpers

NAME=lab-06-check

setup_file() {
  export WS="$BATS_FILE_TMPDIR/ws"
  mkdir -p "$WS"
  printf 'def add(a, b):\n    return a - b\n\n\nif __name__ == "__main__":\n    print(add(2, 3))\n' >"$WS/calc.py"
  delete_sandbox "$NAME"
  sbx run -d --name "$NAME" claude "$WS" </dev/null >/dev/null 2>&1
}

teardown_file() {
  delete_sandbox "$NAME"
}

skip_without_key() {
  sbx secret ls --json | jq -e '.secrets[]? | select(.name == "anthropic")' >/dev/null ||
    skip "no anthropic secret stored (printf %s \"\$KEY\" | sbx secret set anthropic)"
}

@test "Claude Code is preinstalled" {
  run sx "$NAME" claude --version
  [ "$status" -eq 0 ]
  [[ "$output" == *"(Claude Code)"* ]]
}

@test "the sandbox holds no Anthropic key" {
  run sx "$NAME" sh -c 'printf %s "$ANTHROPIC_API_KEY"'
  [ -z "$output" ]
  run sx "$NAME" jq -r .apiKeyHelper /home/agent/.claude/settings.json
  [ "$output" = "echo proxy-managed" ]
}

@test "Claude runs without permission prompts inside the sandbox" {
  run sx "$NAME" jq -r .permissions.defaultMode /home/agent/.claude/settings.json
  [ "$output" = bypassPermissions ]
}

@test "the sandbox gets a provisioned rule for Anthropic's hosts" {
  run sbx policy ls --json
  jq -e --arg s "sandbox:$NAME" \
    '.rules[] | select(.applies_to == $s and .provenance.created_via == "provisioned") | .resources[] | select(. == "api.anthropic.com:443")' \
    <<<"$output" >/dev/null
}

@test "the proxy adds the key to any request to Anthropic" {
  skip_without_key
  run sx "$NAME" sh -c 'curl -s -H "anthropic-version: 2023-06-01" -H "x-api-key: obviously-wrong" https://api.anthropic.com/v1/models | jq ".data | length"'
  [ "$output" -gt 0 ]
}

@test "Claude Code fixes the bug in the workspace" {
  skip_without_key
  run sbx exec "$NAME" claude -p 'Fix the bug in calc.py so add() adds. Do not run anything else. Be brief.' </dev/null
  [ "$status" -eq 0 ]
  run python3 "$WS/calc.py"
  [ "$output" = 5 ]
}

@test "a host outside the policy is queued for approval and works once approved" {
  run sx "$NAME" curl -s -o /dev/null -w '%{http_code}' https://example.org
  [ "$output" = 403 ]
  EVENTUALLY_TRIES=5 eventually bash -c "sbx policy approval ls --json | jq -e '.[] | select(.title == \"example.org:443\" and .sandbox_name == \"$NAME\")' >/dev/null"
  id="$(sbx policy approval ls --json | jq -r --arg s "$NAME" '.[] | select(.title == "example.org:443" and .sandbox_name == $s) | .id')"
  sbx policy approval respond "$id" --option allow
  EVENTUALLY_TRIES=5 eventually bash -c "[ \"\$(sbx exec $NAME curl -s -o /dev/null -w '%{http_code}' https://example.org)\" = 200 ]"
}
