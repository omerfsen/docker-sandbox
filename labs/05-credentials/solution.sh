#!/usr/bin/env bash
# Lab 05 solution: replays the lab against your sbx daemon. Uses fake secret values only.
source "$(dirname "$0")/../../scripts/autoplay.sh"

say "Lab 05 — Credentials the agent never sees"
run_quiet 'sbx rm --force lab-05-cred'
run 'sbx create --name lab-05-cred shell && sbx run -d --name lab-05-cred && sbx policy allow network --sandbox lab-05-cred postman-echo.com,httpbin.org'
say "Store a secret bound to one host (a fake value: never put a real one in a recording)"
run 'sbx secret set-custom --sandbox lab-05-cred --host postman-echo.com --env DEMO_TOKEN --value fake-training-secret-123'
run "sbx secret ls | grep -E 'SCOPE|lab-05-cred'"
say "The sandbox only ever holds the placeholder"
run "P=\$(sbx secret ls --json | jq -r '.custom_secrets[] | select(.scope == \"lab-05-cred\" and .env == \"DEMO_TOKEN\") | .placeholder'); echo \"P=\$P\" > ~/.lab05-placeholder; cat ~/.lab05-placeholder"
run "sbx exec lab-05-cred sh -c 'echo \"DEMO_TOKEN=[\$DEMO_TOKEN]\"'"
run ". ~/.lab05-placeholder; sbx exec -e DEMO_TOKEN=\$P lab-05-cred sh -c 'echo \"inside: \$DEMO_TOKEN\"'"
say "The proxy swaps it in headers, only on the way to the bound host"
run ". ~/.lab05-placeholder; sbx exec -e DEMO_TOKEN=\$P lab-05-cred sh -c 'curl -s -H \"Authorization: Bearer \$DEMO_TOKEN\" https://postman-echo.com/headers | jq -r .headers.authorization'"
run ". ~/.lab05-placeholder; sbx exec -e DEMO_TOKEN=\$P lab-05-cred sh -c 'curl -s -H \"X-Api-Key: \$DEMO_TOKEN\" https://postman-echo.com/headers | jq -r \".headers[\\\"x-api-key\\\"]\"'"
run ". ~/.lab05-placeholder; sbx exec -e DEMO_TOKEN=\$P lab-05-cred sh -c 'curl -s -H \"Authorization: Bearer \$DEMO_TOKEN\" https://httpbin.org/headers | jq -r .headers.Authorization'"
run ". ~/.lab05-placeholder; sbx exec -e DEMO_TOKEN=\$P lab-05-cred sh -c 'curl -s \"https://postman-echo.com/get?key=\$DEMO_TOKEN\" | jq -r .args.key; curl -s -d \"token=\$DEMO_TOKEN\" https://postman-echo.com/post | jq -r .form.token'"
say "A secret from a command instead of a value"
run "sbx secret set-custom --sandbox lab-05-cred --host httpbin.org --env CMD_TOKEN --placeholder lab-{rand} --command 'printf %s fake-from-a-command'"
run "P2=\$(sbx secret ls --json | jq -r '.custom_secrets[] | select(.scope == \"lab-05-cred\" and .env == \"CMD_TOKEN\") | .placeholder'); sbx exec lab-05-cred curl -s -H \"Authorization: Bearer \$P2\" https://httpbin.org/headers | jq -r .headers.Authorization"
run "P2=\$(sbx secret ls --json | jq -r '.custom_secrets[] | select(.scope == \"lab-05-cred\" and .env == \"CMD_TOKEN\") | .placeholder'); sbx secret rm --placeholder \$P2 -f; echo \"exit \$?\"; sbx secret ls | grep -c CMD_TOKEN"
say "Without --sandbox it exits 0 and removes nothing. Name the scope:"
run "P2=\$(sbx secret ls --json | jq -r '.custom_secrets[] | select(.scope == \"lab-05-cred\" and .env == \"CMD_TOKEN\") | .placeholder'); sbx secret rm --placeholder \$P2 --sandbox lab-05-cred -f; sbx secret ls | grep -E 'SCOPE|lab-05-cred'"
say "SSH agent forwarding: the sandbox can use your keys, it never holds them"
run 'D=$(mktemp -d "$XDG_RUNTIME_DIR/l05.XXXX"); eval "$(ssh-agent -a $D/a.sock)" >/dev/null; ssh-keygen -q -t ed25519 -N "" -C lab-05-throwaway -f $D/k; SSH_AUTH_SOCK=$D/a.sock ssh-add -q $D/k; SSH_AUTH_SOCK=$D/a.sock sbx exec lab-05-cred sh -c "ssh-add -l | cut -d\" \" -f3-; ls ~/.ssh"; kill $SSH_AGENT_PID; rm -rf $D'
say "Clean up: rm also deletes the sandbox's secrets"
run "sbx rm --force lab-05-cred; rm -f ~/.lab05-placeholder; sbx secret ls | grep lab-05-cred || echo no lab-05-cred secrets left"
