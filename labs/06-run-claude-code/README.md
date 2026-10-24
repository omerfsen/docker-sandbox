# Lab 06 — Capstone: run Claude Code

**Goal:** run a real coding agent in a sandbox, see how it authenticates without holding a key,
watch it hit the network policy, and grant what it asks for.
**Time:** ~20 minutes. **Prerequisite:** [Lab 05](../05-credentials/README.md), an Anthropic
API key (the lab spends a few cents).

## Concepts

Everything from the earlier labs comes together:

| Piece | Lab | Here |
|---|---|---|
| microVM with its own kernel, your project shared with virtiofs | 02 | Claude edits `~/sbx-labs/06` |
| Balanced policy, every connection through the proxy | 03 | Claude reaches Anthropic and package registries, nothing else |
| Approval queue | 04 | Claude's blocked request waits for you |
| Credentials as placeholders | 05 | The Anthropic key never enters the VM |

Inside the sandbox Claude Code runs with **`bypassPermissions`**: no "may I run this?" prompts.
That is the point of a sandbox. The agent can do anything inside the VM; the VM, the policy,
and the proxy decide what reaches your machine and the internet.

## 1. Store the key once, on the host

```shell
printf %s "$ANTHROPIC_API_KEY" | sbx secret set anthropic
sbx secret ls | grep -E "SCOPE|anthropic"
```

```text
SCOPE      TYPE      NAME        SECRET
(global)   service   anthropic   (stored)
```

Use `printf %s`, not `echo`: a trailing newline becomes part of the key. Console keys start
with `sk-ant-`. This is a built-in service secret, so you don't bind it to a host yourself:
sbx knows where Anthropic traffic goes. If you replace the key while a sandbox runs, the sandbox
picks up the new one after a few minutes.

## 2. Create the sandbox

```shell
mkdir -p ~/sbx-labs/06
printf 'def add(a, b):\n    return a - b\n\n\nif __name__ == "__main__":\n    print(add(2, 3))\n' > ~/sbx-labs/06/calc.py
sbx run -d --name lab-06-agent claude ~/sbx-labs/06
```

```text
  SANDBOX
    Name:       lab-06-agent
    Agent:      claude
    Workspace:  ~/sbx-labs/06 (rw)
    Skills:     0 entries · linked, read-only
      Source:   ~/.local/state/sandboxes/sandboxes/agent-skills
      Target:   /home/agent/.claude/skills
    Image:      docker/sandbox-templates:claude-code-docker
    CPU:        4
    Memory:     3.9 GiB
    ...
    ✓ Created sandbox lab-06-agent
```

The first time, the Claude Code image is pulled (about a minute on the course host). `Skills`
links a shared skills folder read-only into `~/.claude/skills` in the sandbox.

## 3. What the agent gets

```shell
sbx exec lab-06-agent sh -c 'claude --version; echo "ANTHROPIC_API_KEY=[$ANTHROPIC_API_KEY]"; jq -c "{apiKeyHelper, permissions}" ~/.claude/settings.json'
```

```text
2.1.306 (Claude Code)
ANTHROPIC_API_KEY=[]
{"apiKeyHelper":"echo proxy-managed","permissions":{"defaultMode":"bypassPermissions"}}
```

No key in the environment. Claude's `apiKeyHelper` prints the word `proxy-managed`, and the proxy
puts the real key on the request on its way to Anthropic. The sandbox also gets its own allow
rule for Anthropic's hosts:

```shell
sbx policy ls --json | jq -r '.rules[] | select(.applies_to == "sandbox:lab-06-agent") | "\(.decision) via \(.provenance.created_via): \(.resources | join(", "))"'
```

```text
allow via provisioned: api.anthropic.com:443, platform.claude.com:443, downloads.claude.ai:443, claude.com:443, code.claude.com:443, mcp-proxy.anthropic.com:443, bridge.claudeusercontent.com:443
```

You will also find a `GH_TOKEN` in the environment. It is a placeholder shaped like a GitHub
token, and GitHub rejects it with a 401. `github` is one of the built-in services of
`sbx secret set` (with `anthropic`, `openai`, `google`, `openrouter`, and others), the same
mechanism as the Anthropic key.

## 4. A real task

Ask Claude to fix the bug and to fetch a host the policy does not allow:

```shell
sbx exec lab-06-agent claude -p 'Fix the bug in calc.py so add() adds, run it to show the result, then run: curl -sS -m 10 -o /dev/null -w "%{http_code}\n" https://example.org and report the status code. Be brief.' < /dev/null
```

```text
I fixed `calc.py` by changing `a - b` to `a + b`. Running it now prints `add(2, 3)` = **5**.

The curl to example.org returned **403**. That's the sandbox firewall blocking it, not the site: the response says "Approval required for example.org:443." To allow it, run this on your host, then approve the pending request:

sbx policy approval ls
sbx policy approval respond <approval-id> --option <option-id>
```

It took about 16 seconds. `< /dev/null` stops `claude -p` from waiting for piped input. Your
file on the host changed:

```shell
head -2 ~/sbx-labs/06/calc.py
```

```text
def add(a, b):
    return a + b
```

And the policy log shows both sides:

```shell
sbx policy log lab-06-agent --json | jq -r '(.allowed[] | select(.host | test("anthropic")) | "ALLOW \(.host) \(.proxy_type)"), (.blocked[:1][] | "DENY  \(.host) \(.reason)")'
```

```text
ALLOW api.anthropic.com:443 forward
DENY  example.org:443 No matching allow rule (default deny)
```

`forward`, not `forward-bypass`: the proxy opens Anthropic traffic to add the key.

## 5. The key cannot be read, but it can be used

```shell
sbx exec lab-06-agent sh -c 'curl -s -H "anthropic-version: 2023-06-01" -H "x-api-key: obviously-wrong" https://api.anthropic.com/v1/models | jq -r "\"models listed: \(.data | length)\""'
```

```text
models listed: 14
```

A plain `curl` with a **wrong** key works: the proxy sets the real key on every request to
Anthropic, whatever the sandbox sent. Nothing in the sandbox can read the key or send it
elsewhere, but **any code in the sandbox can spend it**. A prompt-injected agent, or a
dependency's install script, can run up your bill. Use a key with a spending limit, and remove
it when you are done (Lab 07).

## 6. Grant what the agent asked for

```shell
sbx policy approval ls | cut -c1-110
```

```text
APPROVAL                                              SANDBOX        TITLE             DETAIL
network:7PBOes_MFzzwqgFT8v-lDOMORFD9bmW1dS863wiwDZs   lab-06-agent   example.org:443   Protocol: TCP Resource
```

```shell
A=$(sbx policy approval ls --json | jq -r '.[] | select(.title == "example.org:443" and .sandbox_name == "lab-06-agent") | .id')
sbx policy approval respond $A --option allow
sleep 3; sbx exec lab-06-agent curl -s -o /dev/null -w "example.org %{http_code}\n" https://example.org
```

```text
  Recorded answer Allow

example.org 200
```

The loop for real work: the agent hits a wall, tells you, you look at the request, you allow it
(or not), the agent retries.

## 7. Work with it interactively

```shell
sbx run --name lab-06-agent
```

attaches you to Claude Code inside the sandbox, in your project. Leave it running detached and
come back later with the same command. `sbx run claude .` in any project directory creates a
sandbox for that project in one step.

OpenShell's capstone ran OpenCode with a free model and built the policy up as the agent asked.
The workflow here is the same; the approval queue replaces OpenShell's policy advisor.

## 8. Clean up

```shell
sbx rm --force lab-06-agent; rm -rf ~/sbx-labs/06
```

The `anthropic` secret is global and stays. Lab 07 removes it.

## Exercises

1. Ask Claude to `pip install requests` and to `npm install left-pad` in the sandbox. Which
   registries does Balanced allow, and does the policy log show them as `forward-bypass`?
2. Ask Claude to read `~/.ssh/id_ed25519` or `~/.aws/credentials`. What does it find?
3. Create a sandbox with `--deny-network '**'` added to the provisioned rule set and see what
   Claude says when it cannot reach Anthropic.

## Watch the solution

Every step of this lab, typed and run against a real sbx daemon:

```shell
make replay LAB=06          # scriptreplay (util-linux, preinstalled)
make replay-cast LAB=06     # asciinema
labs/06-run-claude-code/solution.sh   # run it live (needs your anthropic secret, spends a few cents)
```

## Check your work

```shell
bats labs/06-run-claude-code/test.bats   # the Anthropic checks skip without a stored key
```

**Next:** [Lab 07 — Clean up](../07-cleanup/README.md)
