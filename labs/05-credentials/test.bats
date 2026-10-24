#!/usr/bin/env bats
# Lab 05: custom secrets as placeholders, swapped by the proxy only in headers
# to the bound host; SSH agent forwarding. Uses fake secret values only.

load ../../tests/helpers

NAME=lab-05-check
FAKE=fake-lab05-check-secret

setup_file() {
  create_sandbox "$NAME"
  sbx policy allow network --sandbox "$NAME" postman-echo.com,httpbin.org >/dev/null
  sbx secret set-custom --sandbox "$NAME" --host postman-echo.com --env DEMO_TOKEN --value "$FAKE" >/dev/null 2>&1
  sleep 3
}

teardown_file() {
  delete_sandbox "$NAME"
}

placeholder() {
  sbx secret ls --json | jq -r --arg s "$NAME" --arg e "$1" \
    '.custom_secrets[] | select(.scope == $s and .env == $e) | .placeholder'
}

# Run a command in the sandbox with DEMO_TOKEN set to the placeholder.
with_token() {
  sbx exec -e DEMO_TOKEN="$(placeholder DEMO_TOKEN)" "$NAME" sh -c "$1"
}

@test "secret ls shows the placeholder and masks the value" {
  run sbx secret ls
  [[ "$output" == *"$(placeholder DEMO_TOKEN)"* ]]
  [[ "$output" != *"$FAKE"* ]]
}

@test "the env var is not set in the sandbox by itself" {
  run sx "$NAME" printenv DEMO_TOKEN
  [ "$status" -ne 0 ]
}

@test "the proxy swaps the placeholder in headers to the bound host" {
  run with_token 'curl -s -H "Authorization: Bearer $DEMO_TOKEN" https://postman-echo.com/headers | jq -r .headers.authorization'
  [ "$output" = "Bearer $FAKE" ]
  run with_token 'curl -s -H "X-Api-Key: $DEMO_TOKEN" https://postman-echo.com/headers | jq -r ".headers[\"x-api-key\"]"'
  [ "$output" = "$FAKE" ]
}

@test "another host gets the placeholder, not the secret" {
  run with_token 'curl -s -H "Authorization: Bearer $DEMO_TOKEN" https://httpbin.org/headers | jq -r .headers.Authorization'
  [ "$output" = "Bearer $(placeholder DEMO_TOKEN)" ]
}

@test "the query string and body are not rewritten" {
  run with_token 'curl -s "https://postman-echo.com/get?key=$DEMO_TOKEN" | jq -r .args.key'
  [ "$output" = "$(placeholder DEMO_TOKEN)" ]
  run with_token 'curl -s -d "token=$DEMO_TOKEN" https://postman-echo.com/post | jq -r .form.token'
  [ "$output" = "$(placeholder DEMO_TOKEN)" ]
}

@test "a secret can come from a host command" {
  sbx secret set-custom --sandbox "$NAME" --host httpbin.org --env CMD_TOKEN --placeholder lab-{rand} \
    --command 'printf %s fake-from-a-command' >/dev/null 2>&1
  sleep 2
  run sx "$NAME" sh -c "curl -s -H 'Authorization: Bearer $(placeholder CMD_TOKEN)' https://httpbin.org/headers | jq -r .headers.Authorization"
  [ "$output" = "Bearer fake-from-a-command" ]
}

@test "rm --placeholder needs --sandbox for a sandbox-scoped secret" {
  p="$(placeholder CMD_TOKEN)"
  run sbx secret rm --placeholder "$p" -f
  [ "$status" -eq 0 ]
  [ "$(placeholder CMD_TOKEN)" = "$p" ]
  run sbx secret rm --placeholder "$p" --sandbox "$NAME" -f
  [[ "$output" == *"Removed 1 custom secret"* ]]
  [ -z "$(placeholder CMD_TOKEN)" ]
}

@test "SSH agent forwarding lets the sandbox use host keys without holding them" {
  dir="$(mktemp -d "${XDG_RUNTIME_DIR:-/tmp}/l05.XXXX")"
  eval "$(ssh-agent -a "$dir/a.sock")" >/dev/null
  ssh-keygen -q -t ed25519 -N '' -C lab-05-check-key -f "$dir/k"
  SSH_AUTH_SOCK="$dir/a.sock" ssh-add -q "$dir/k"
  run env SSH_AUTH_SOCK="$dir/a.sock" sbx exec "$NAME" ssh-add -l
  kill "$SSH_AGENT_PID"
  rm -rf "$dir"
  [[ "$output" == *"lab-05-check-key"* ]]
  run sx "$NAME" ls /home/agent/.ssh
  [ "$status" -ne 0 ]
}

@test "rm deletes the sandbox's secrets" {
  delete_sandbox "$NAME"
  run sbx secret ls --json
  [ "$(jq --arg s "$NAME" '[.custom_secrets[]? | select(.scope == $s)] | length' <<<"$output")" = 0 ]
}
