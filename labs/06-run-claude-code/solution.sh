#!/usr/bin/env bash
# Lab 06 solution: runs Claude Code in a sandbox. Needs the anthropic secret
# (printf %s "$ANTHROPIC_API_KEY" | sbx secret set anthropic) and spends a few cents.
source "$(dirname "$0")/../../scripts/autoplay.sh"

say "Lab 06 — Capstone: run Claude Code"
run_quiet 'sbx rm --force lab-06-agent; rm -rf ~/sbx-labs/06'
say "Stored once on the host: printf %s \"\$ANTHROPIC_API_KEY\" | sbx secret set anthropic"
run 'sbx secret ls | grep -E "SCOPE|anthropic"'
run "mkdir -p ~/sbx-labs/06 && printf 'def add(a, b):\n    return a - b\n\n\nif __name__ == \"__main__\":\n    print(add(2, 3))\n' > ~/sbx-labs/06/calc.py && cat ~/sbx-labs/06/calc.py"
run 'sbx run -d --name lab-06-agent claude ~/sbx-labs/06'
say "What the agent gets: no key, a helper that says proxy-managed, no permission prompts"
run "sbx exec lab-06-agent sh -c 'claude --version; echo \"ANTHROPIC_API_KEY=[\$ANTHROPIC_API_KEY]\"; jq -c \"{apiKeyHelper, permissions}\" ~/.claude/settings.json'"
run "sbx policy ls --json | jq -r '.rules[] | select(.applies_to == \"sandbox:lab-06-agent\") | \"\\(.decision) via \\(.provenance.created_via): \\(.resources | join(\", \"))\"'"
say "A real task: fix a bug, then try a host the policy does not allow"
run "sbx exec lab-06-agent claude -p 'Fix the bug in calc.py so add() adds, run it to show the result, then run: curl -sS -m 10 -o /dev/null -w \"%{http_code}\\n\" https://example.org and report the status code. Be brief.' < /dev/null"
run 'head -2 ~/sbx-labs/06/calc.py'
run "sbx policy log lab-06-agent --json | jq -r '(.allowed[] | select(.host | test(\"anthropic\")) | \"ALLOW \\(.host) \\(.proxy_type)\"), (.blocked[:1][] | \"DENY  \\(.host) \\(.reason)\")'"
say "The agent cannot read the key, but anything in the sandbox can use it"
run "sbx exec lab-06-agent sh -c 'curl -s -H \"anthropic-version: 2023-06-01\" -H \"x-api-key: obviously-wrong\" https://api.anthropic.com/v1/models | jq -r \"\\\"models listed: \\(.data | length)\\\"\"'"
say "Grant what the agent asked for, from the approval queue"
run "sbx policy approval ls | cut -c1-110"
run "A=\$(sbx policy approval ls --json | jq -r '.[] | select(.title == \"example.org:443\" and .sandbox_name == \"lab-06-agent\") | .id'); sbx policy approval respond \$A --option allow"
run 'sleep 3; sbx exec lab-06-agent curl -s -o /dev/null -w "example.org %{http_code}\n" https://example.org'
say "Interactive: sbx run --name lab-06-agent attaches you to Claude Code inside the sandbox"
say "Clean up"
run 'sbx rm --force lab-06-agent; rm -rf ~/sbx-labs/06'
