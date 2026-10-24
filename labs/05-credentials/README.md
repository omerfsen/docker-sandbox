# Lab 05 — Credentials the agent never sees

**Goal:** give a sandbox an API key it can use but never read, see exactly where the proxy puts
the real value, and find the edges: other hosts, query strings, echo services, and SSH keys.
**Time:** ~20 minutes. **Prerequisite:** [Lab 04](../04-l7-rules-and-approvals/README.md).

## Concepts

An agent needs keys to call APIs. If the key sits in an environment variable inside the sandbox,
anything the agent runs can print it or send it somewhere. sbx keeps the key on the **host**:

```text
  sandbox                        host proxy                         api host
  Authorization: Bearer   ──►  placeholder? bound host? ──►  Authorization: Bearer
    sbx-cs-bq2ud...             swap in the real value          the-real-key
```

- `sbx secret set-custom` stores a value and gives you a **placeholder** (`sbx-cs-...`).
- The sandbox only ever sees the placeholder.
- When a request leaves for a **bound host** (`--host`), the proxy replaces the placeholder
  with the real value **in the request headers**. Nowhere else, for no other host.
- `sbx secret set` does the same for built-in services (`anthropic`, `openai`, `github`, ...);
  Lab 06 uses it for Claude Code.

OpenShell calls these **providers**: credential profiles bound to endpoints, with placeholders
swapped by the supervisor. The model is the same.

This lab uses a **fake** value (`fake-training-secret-123`). Never put a real key in a command
you record or share. `--value` also lands in your shell history; `--command` and `--ref`
(1Password, AWS Secrets Manager) avoid that.

## 1. Store a secret for one host

```shell
sbx run -d --name lab-05-cred shell && sbx policy allow network --sandbox lab-05-cred postman-echo.com,httpbin.org
sbx secret set-custom --sandbox lab-05-cred --host postman-echo.com --env DEMO_TOKEN --value fake-training-secret-123
```

```text
  warning: no keychain detected; this secret will be stored on disk, protected by file permissions rather than a password
  Applied secret updates to sandbox lab-05-cred
  Saved custom secret sbx-cs-bq2udC4Et0iH4qMI for target postman-echo.com env DEMO_TOKEN (lab-05-cred)

    Generated placeholder:  sbx-cs-bq2udC4Et0iH4qMI

  You may need to update environment variable DEMO_TOKEN inside sandbox "lab-05-cred" to "sbx-cs-bq2udC4Et0iH4qMI" (the placeholder value).
```

```shell
sbx secret ls | grep -E 'SCOPE|lab-05-cred'
```

```text
SCOPE      TYPE      NAME        SECRET
SCOPE         TARGETS            ENV          PLACEHOLDER               SECRET
lab-05-cred   postman-echo.com   DEMO_TOKEN   sbx-cs-bq2udC4Et0iH4qMI   fake-t**************-123
```

Without a desktop keychain the value is stored on disk under your home directory, protected by
file permissions. Anyone who can read your files can read it.

## 2. The sandbox holds only the placeholder

```shell
sbx exec lab-05-cred sh -c 'echo "DEMO_TOKEN=[$DEMO_TOKEN]"'
```

```text
DEMO_TOKEN=[]
```

`--env DEMO_TOKEN` did **not** set the variable in this sandbox, even after a restart. The CLI
says so ("You may need to update environment variable..."). Pass the placeholder yourself:

```shell
P=$(sbx secret ls --json | jq -r '.custom_secrets[] | select(.scope == "lab-05-cred" and .env == "DEMO_TOKEN") | .placeholder')
sbx exec -e DEMO_TOKEN=$P lab-05-cred sh -c 'echo "inside: $DEMO_TOKEN"'
```

```text
inside: sbx-cs-bq2udC4Et0iH4qMI
```

The placeholder is not secret. It is only useful when it goes through the proxy to the bound
host.

## 3. Where the proxy swaps it

To the bound host, in any header:

```shell
sbx exec -e DEMO_TOKEN=$P lab-05-cred sh -c 'curl -s -H "Authorization: Bearer $DEMO_TOKEN" https://postman-echo.com/headers | jq -r .headers.authorization'
sbx exec -e DEMO_TOKEN=$P lab-05-cred sh -c 'curl -s -H "X-Api-Key: $DEMO_TOKEN" https://postman-echo.com/headers | jq -r ".headers[\"x-api-key\"]"'
```

```text
Bearer fake-training-secret-123
fake-training-secret-123
```

To another allowed host, nothing is swapped:

```shell
sbx exec -e DEMO_TOKEN=$P lab-05-cred sh -c 'curl -s -H "Authorization: Bearer $DEMO_TOKEN" https://httpbin.org/headers | jq -r .headers.Authorization'
```

```text
Bearer sbx-cs-bq2udC4Et0iH4qMI
```

In the query string or the body, nothing is swapped, even for the bound host:

```shell
sbx exec -e DEMO_TOKEN=$P lab-05-cred sh -c 'curl -s "https://postman-echo.com/get?key=$DEMO_TOKEN" | jq -r .args.key
  curl -s -d "token=$DEMO_TOKEN" https://postman-echo.com/post | jq -r .form.token'
```

```text
sbx-cs-bq2udC4Et0iH4qMI
sbx-cs-bq2udC4Et0iH4qMI
```

So an API that wants its key as `?api_key=...` cannot use this. A prompt-injected agent that
sends the token to a server it controls only leaks the placeholder.

**But look at the first two outputs again.** postman-echo **echoes the headers back**, so the
real value came back into the sandbox, and the agent could read it. The proxy protects the
outgoing request, not what the server sends back. Bind a secret only to the real API host,
never to a host that reflects requests (echo services, request bins, generic proxies).

## 4. A secret from a command

`--command` runs a command **on the host** to get the value when the secret is needed
(`--refresh on-demand` by default):

```shell
sbx secret set-custom --sandbox lab-05-cred --host httpbin.org --env CMD_TOKEN --placeholder lab-{rand} --command 'printf %s fake-from-a-command'
P2=$(sbx secret ls --json | jq -r '.custom_secrets[] | select(.scope == "lab-05-cred" and .env == "CMD_TOKEN") | .placeholder')
sbx exec lab-05-cred curl -s -H "Authorization: Bearer $P2" https://httpbin.org/headers | jq -r .headers.Authorization
```

```text
  Saved custom secret lab-HZXyiVZzx5DNQF3U for target httpbin.org env CMD_TOKEN (lab-05-cred)

  --command custom secrets are stored and replayed by sandboxd. Put any required environment variables directly in the command or wrapper script. Avoid embedding secret values directly because command text can appear in shell history and process listings.
  ...
Bearer fake-from-a-command
```

In real use the command reads from a vault (`op read ...`,
`aws secretsmanager get-secret-value ...`, `vault kv get ...`). `--placeholder lab-{rand}` picks the placeholder's
shape, for tools that check a key's prefix. Keep helper scripts outside any workspace a
sandbox can write: the daemon runs them on the host.

## 5. Removing a scoped secret: name the scope

```shell
sbx secret rm --placeholder $P2 -f; echo "exit $?"; sbx secret ls | grep -c CMD_TOKEN
```

```text
  Applied secret updates to 3 running sandboxes

exit 0
1
```

Exit 0, and the secret is **still there**: without `--sandbox`, `rm --placeholder` does not
remove a sandbox-scoped secret. Name the scope:

```shell
sbx secret rm --placeholder $P2 --sandbox lab-05-cred -f
```

```text
  Removed 1 custom secret for placeholder lab-HZXyiVZzx5DNQF3U (lab-05-cred)
  Applied secret updates to sandbox lab-05-cred
```

Look for `Removed 1 custom secret` before you trust a removal.

## 6. SSH agent forwarding

Lab 01's `sbx setup` showed SSH agent forwarding **Enabled**. The sandbox can ask the SSH agent
of the `sbx` command that runs it to sign things. To see that without touching your real agent,
use a throwaway agent and key:

```shell
D=$(mktemp -d "$XDG_RUNTIME_DIR/l05.XXXX"); eval "$(ssh-agent -a $D/a.sock)" >/dev/null
ssh-keygen -q -t ed25519 -N "" -C lab-05-throwaway -f $D/k; SSH_AUTH_SOCK=$D/a.sock ssh-add -q $D/k
SSH_AUTH_SOCK=$D/a.sock sbx exec lab-05-cred sh -c 'ssh-add -l | cut -d" " -f3-; ls ~/.ssh'
kill $SSH_AGENT_PID; rm -rf $D
```

```text
lab-05-throwaway (ED25519)
ls: cannot access '/home/agent/.ssh': No such file or directory
```

The sandbox has **no key files**, but it can use every key loaded in your agent: `git push`,
`ssh` to your servers, signing commits. That is a credential grant like any other. Turn it off
with `sbx settings set ssh.agentForwardingEnabled false` (needs `sbx daemon restart`), or load
only the keys you mean to share.

## 7. Clean up

```shell
sbx rm --force lab-05-cred; sbx secret ls | grep lab-05-cred || echo no lab-05-cred secrets left
```

```text
  Removed sandbox lab-05-cred

no lab-05-cred secrets left
```

Removing a sandbox deletes the secrets scoped to it.

## Exercises

1. Bind a secret to `*.postman-echo.com` and test whether `postman-echo.com` itself gets it.
2. Store a secret with `--command` reading from a vault CLI you use, and check it
   in `sbx secret ls`: what is shown in the SECRET column?
3. Make a secret global (no `--sandbox`) in a throwaway setup, create a new sandbox, and check
   whether its `--env` variable is set. Remove it afterwards with `sbx secret rm --placeholder`.

## Watch the solution

Every step of this lab, typed and run against a real sbx daemon:

```shell
make replay LAB=05          # scriptreplay (util-linux, preinstalled)
make replay-cast LAB=05     # asciinema
labs/05-credentials/solution.sh   # replay it live against your own daemon (PAUSE=0 for full speed)
```

## Check your work

```shell
bats labs/05-credentials/test.bats
```

**Next:** Lab 06 — Capstone: run Claude Code (coming in the next part of the course)
