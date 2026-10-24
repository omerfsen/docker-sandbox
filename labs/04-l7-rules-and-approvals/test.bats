#!/usr/bin/env bats
# Lab 04: HTTP method and path rules, TLS inspection, and the approval queue.

load ../../tests/helpers

NAME=lab-04-check

setup_file() {
  create_sandbox "$NAME"
}

teardown_file() {
  delete_sandbox "$NAME"
}

req() {
  sx "$NAME" curl -s -o /dev/null -w '%{http_code}' --max-time 10 -X "$1" "https://httpbin.org$2" || true
}

approval_id() {
  sbx policy approval ls --json | jq -r --arg t "$1" --arg s "$NAME" \
    '.[] | select(.title == $t and .sandbox_name == $s) | .id'
}

@test "a blocked host answers 'Approval required' and lands in the queue" {
  run sx "$NAME" curl -s https://httpbin.org/anything
  [[ "$output" == *"Approval required for httpbin.org:443"* ]]
  EVENTUALLY_TRIES=5 eventually bash -c "sbx policy approval ls | grep -q '$NAME .*httpbin.org:443'"
}

@test "a method and path rule allows only that method under that path" {
  sbx policy allow network --sandbox "$NAME" httpbin.org --method GET --path '/anything/**'
  EVENTUALLY_TRIES=5 eventually bash -c "[ \"\$(sbx exec $NAME curl -s -o /dev/null -w '%{http_code}' https://httpbin.org/anything/ok)\" = 200 ]"
  [ "$(req POST /anything/ok)" = 403 ]
  [ "$(req GET /headers)" = 403 ]
}

@test "a host with HTTP rules is served with the proxy's CA, others are not" {
  run sx "$NAME" sh -c 'curl -sv -o /dev/null https://httpbin.org/anything/ok 2>&1 | grep issuer:'
  [[ "$output" == *"CN=Docker Sandboxes Proxy CA"* ]]
  run sx "$NAME" sh -c 'curl -sv -o /dev/null https://pypi.org 2>&1 | grep issuer:'
  [[ "$output" != *"Docker Sandboxes"* ]]
}

@test "approving a request adds a narrow rule for exactly that request" {
  EVENTUALLY_TRIES=5 eventually bash -c "sbx policy approval ls | grep -q 'POST httpbin.org:443/anything/ok'"
  id="$(approval_id 'POST httpbin.org:443/anything/ok')"
  [ -n "$id" ]
  sbx policy approval respond "$id" --option allow
  EVENTUALLY_TRIES=5 eventually bash -c "[ \"\$(sbx exec $NAME curl -s -o /dev/null -w '%{http_code}' -X POST https://httpbin.org/anything/ok)\" = 200 ]"
  [ "$(req POST /anything/other)" = 403 ]
  run sbx policy ls --json
  [ "$(jq -r --arg s "sandbox:$NAME" '.rules[] | select(.applies_to == $s and .provenance.created_via == "approval") | .methods[0]' <<<"$output")" = POST ]
}

@test "dismissing an approval does not allow the request" {
  EVENTUALLY_TRIES=5 eventually bash -c "sbx policy approval ls | grep -q 'GET httpbin.org:443/headers'"
  sbx policy approval respond "$(approval_id 'GET httpbin.org:443/headers')" --option dismiss
  sleep 2
  [ "$(req GET /headers)" = 403 ]
}

@test "a plain host allow opens every method and path" {
  sbx policy allow network --sandbox "$NAME" httpbin.org
  EVENTUALLY_TRIES=5 eventually bash -c "[ \"\$(sbx exec $NAME curl -s -o /dev/null -w '%{http_code}' -X DELETE https://httpbin.org/anything/other)\" = 200 ]"
  [ "$(req GET /headers)" = 200 ]
}

@test "a method deny still applies on top of a host allow" {
  sbx policy deny network --sandbox "$NAME" httpbin.org --method DELETE
  EVENTUALLY_TRIES=5 eventually bash -c "[ \"\$(sbx exec $NAME curl -s -o /dev/null -w '%{http_code}' -X DELETE https://httpbin.org/anything/other)\" = 403 ]"
  [ "$(req POST /anything/other)" = 200 ]
}

@test "policy check judges the connection, not the HTTP request" {
  run sbx policy check network --sandbox "$NAME" https://httpbin.org/anything/ok
  [[ "$output" == *"HTTP authorization required"* ]]
}

@test "rm clears the sandbox's pending approvals" {
  delete_sandbox "$NAME"
  run sbx policy approval ls --json
  [ "$(jq --arg s "$NAME" '[.[]? | select(.sandbox_name == $s)] | length' <<<"$output")" = 0 ]
}
