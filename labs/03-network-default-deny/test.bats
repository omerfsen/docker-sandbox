#!/usr/bin/env bats
# Lab 03: Balanced default-deny egress, bypass attempts, per-sandbox rules.

load ../../tests/helpers

NAME=lab-03-check

setup_file() {
  create_sandbox "$NAME"
}

teardown_file() {
  delete_sandbox "$NAME"
}

@test "Balanced allows a package registry" {
  run http_code "$NAME" https://pypi.org
  [ "$output" = 200 ]
}

@test "Balanced blocks other hosts with a 403 from the proxy" {
  run http_code "$NAME" https://example.com
  [ "$output" = 403 ]
  run http_code "$NAME" http://169.254.169.254/
  [ "$output" = 403 ]
}

@test "the block is in the policy log with its reason" {
  log_has "$NAME" 'example\.com:443.*No matching allow rule \(default deny\)'
}

@test "sandbox programs are pointed at the daemon's proxy" {
  run sx "$NAME" printenv HTTPS_PROXY
  [ "$output" = "http://gateway.docker.internal:3128" ]
}

@test "skipping the proxy fails: blocked hosts do not resolve" {
  run sx "$NAME" curl -sS --noproxy '*' --max-time 8 -o /dev/null https://example.com
  [ "$status" -eq 6 ]
  run sx "$NAME" getent hosts example.com
  [ "$status" -ne 0 ]
}

@test "a direct connection by IP is caught by the transparent proxy" {
  ip="$(getent ahostsv4 tcpbin.com | awk 'NR==1 {print $1}')"
  [ -n "$ip" ] || skip "tcpbin.com does not resolve on the host"
  run sx "$NAME" bash -c "exec 3<>/dev/tcp/$ip/4242; echo hello >&3; timeout 5 head -1 <&3"
  [ -z "$output" ]
  log_has "$NAME" "$ip:4242 +transparent"
}

@test "a sandbox-scoped allow opens one host for that sandbox only" {
  sbx policy allow network --sandbox "$NAME" postman-echo.com
  EVENTUALLY_TRIES=5 eventually bash -c "[ \"\$(sbx exec $NAME curl -s -o /dev/null -w '%{http_code}' https://postman-echo.com/get)\" = 200 ]"
  run sbx policy check network postman-echo.com
  [[ "$output" == *"Denied:"* ]]
  run sbx policy check network --sandbox "$NAME" postman-echo.com
  [[ "$output" == *"Allowed:"* ]]
}

@test "every program gets the same answer (no per-program rules)" {
  run sx "$NAME" python3 -c 'import urllib.request as u; print(u.urlopen(u.Request("https://postman-echo.com/get", headers={"User-Agent": "curl/8"}), timeout=10).status)'
  [ "$output" = 200 ]
}

@test "a sandbox-scoped deny on ** beats every allow" {
  sbx policy deny network --sandbox "$NAME" '**'
  EVENTUALLY_TRIES=5 eventually bash -c "[ \"\$(sbx exec $NAME curl -s -o /dev/null -w '%{http_code}' https://pypi.org)\" = 403 ]"
  run http_code "$NAME" https://postman-echo.com/get
  [ "$output" = 403 ]
}

@test "removing the rules restores Balanced" {
  sbx policy rm network --sandbox "$NAME" --resource '**' --force
  sbx policy rm network --sandbox "$NAME" --resource postman-echo.com --force
  EVENTUALLY_TRIES=5 eventually bash -c "[ \"\$(sbx exec $NAME curl -s -o /dev/null -w '%{http_code}' https://pypi.org)\" = 200 ]"
  run http_code "$NAME" https://postman-echo.com/get
  [ "$output" = 403 ]
}

@test "rm removes the sandbox's scoped rules" {
  sbx policy allow network --sandbox "$NAME" postman-echo.com
  delete_sandbox "$NAME"
  run sbx policy ls --json
  [ "$(jq --arg s "sandbox:$NAME" '[.rules[] | select(.applies_to == $s)] | length' <<<"$output")" = 0 ]
}
