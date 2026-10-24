#!/usr/bin/env bash
# Lab 04 solution: replays the lab against your sbx daemon.
source "$(dirname "$0")/../../scripts/autoplay.sh"

say "Lab 04 — L7 rules and approvals"
run_quiet 'sbx rm --force lab-04-l7'
run 'sbx create --name lab-04-l7 shell && sbx run -d --name lab-04-l7'
say "httpbin.org is not on the Balanced list: the request waits for approval"
run 'sbx exec lab-04-l7 curl -s https://httpbin.org/anything'
run 'sleep 2; sbx policy approval ls'
say "Allow only GET under /anything/ (an allow-list rule)"
run "sbx policy allow network --sandbox lab-04-l7 httpbin.org --method GET --path '/anything/**'"
run 'sleep 3; for req in "GET /anything/ok" "POST /anything/ok" "GET /headers"; do set -- $req; sbx exec lab-04-l7 curl -s -o /dev/null -w "$1 $2 %{http_code}\n" -X $1 https://httpbin.org$2; done'
say "To read the method and path, the proxy opens TLS with its own CA"
run "sbx exec lab-04-l7 sh -c 'curl -sv -o /dev/null https://httpbin.org/anything/ok 2>&1 | grep issuer:; curl -sv -o /dev/null https://pypi.org 2>&1 | grep issuer:'"
say "Approve one request from the queue"
run "sleep 2; sbx policy approval ls | cut -c1-110"
run "A=\$(sbx policy approval ls --json | jq -r '.[] | select(.title == \"POST httpbin.org:443/anything/ok\") | .id'); sbx policy approval inspect \$A && sbx policy approval respond \$A --option allow"
run 'sleep 3; for p in /anything/ok /anything/other; do sbx exec lab-04-l7 curl -s -o /dev/null -w "POST $p %{http_code}\n" -X POST https://httpbin.org$p; done'
run "sbx policy ls --json | jq -r '.rules[] | select(.applies_to == \"sandbox:lab-04-l7\") | \"\\(.decision) \\(.methods) \\(.http_targets[0].host)\\(.http_targets[0].path)  created via \\(.provenance.created_via)\"'"
say "Dismiss is a one-time no"
run "D=\$(sbx policy approval ls --json | jq -r '.[] | select(.title == \"GET httpbin.org:443/headers\") | .id'); sbx policy approval respond \$D --option dismiss"
run 'sleep 2; sbx exec lab-04-l7 curl -s -o /dev/null -w "GET /headers %{http_code}\n" https://httpbin.org/headers; sbx policy approval ls | grep headers | cut -c1-110'
say "Deny-list style: allow the host, deny one method"
run 'sbx policy allow network --sandbox lab-04-l7 httpbin.org'
run 'sleep 3; for m in POST DELETE; do sbx exec lab-04-l7 curl -s -o /dev/null -w "$m /anything/other %{http_code}\n" -X $m https://httpbin.org/anything/other; done'
run 'sbx policy deny network --sandbox lab-04-l7 httpbin.org --method DELETE'
run 'sleep 3; for m in POST DELETE; do sbx exec lab-04-l7 curl -s -o /dev/null -w "$m /anything/other %{http_code}\n" -X $m https://httpbin.org/anything/other; done'
say "policy check evaluates the connection, not the HTTP request"
run 'sbx policy check network --sandbox lab-04-l7 https://httpbin.org/anything/ok'
say "Clean up: rm also clears the sandbox's rules and pending approvals"
run 'sbx rm --force lab-04-l7; sbx policy approval ls'
