#!/usr/bin/env bash
# Lab 08 solution: sbx 0.51 changes. Expects sbx 0.51.0 already installed (README section 2).
source "$(dirname "$0")/../../scripts/autoplay.sh"

say "Lab 08 (bonus) — What's new in sbx 0.51"
run_quiet 'sbx rm --force lab-08-new lab-08-mounts lab-08-wd; rm -rf ~/sbx-labs/08'
run "sbx version; sbx diagnose | grep -E 'Version match|passed'"
say "Built-in agents are now published kits; the shell agent is Debian 13"
run 'mkdir -p ~/sbx-labs/08/ws ~/sbx-labs/08/victim ~/sbx-labs/08/out && sbx create --name lab-08-new shell ~/sbx-labs/08/ws >/dev/null && sbx run -d --name lab-08-new'
run "sbx exec lab-08-new sh -c '. /etc/os-release; echo \$PRETTY_NAME'"
run "sbx inspect lab-08-new | grep -E 'Kits|Created with|Image:'"
say "The agent plants symlinks to host paths in the shared workspace"
run 'echo host-canary > ~/sbx-labs/08/host-canary.txt'
run "W=\$HOME/sbx-labs/08/ws; sbx exec lab-08-new sh -c \"ln -sfn \$HOME/sbx-labs/08/host-canary.txt \$W/notes.txt; ln -sfn \$HOME/sbx-labs/08/victim \$W/drop; ln -sfn .. \$W/up; ls -l \$W\""
say "sbx cp resolves every path inside the VM, so the links lead nowhere"
run 'sbx cp lab-08-new:$HOME/sbx-labs/08/ws/notes.txt ~/sbx-labs/08/out/a.txt'
run 'sbx cp -L lab-08-new:$HOME/sbx-labs/08/ws/up/host-canary.txt ~/sbx-labs/08/out/c.txt'
run 'echo payload > ~/sbx-labs/08/out/payload.txt && sbx cp ~/sbx-labs/08/out/payload.txt lab-08-new:$HOME/sbx-labs/08/ws/drop/payload.txt'
run 'sbx cp ~/sbx-labs/08/out/payload.txt lab-08-new:$HOME/sbx-labs/08/ws/up/escaped.txt'
run 'ls -A ~/sbx-labs/08/victim; ls ~/sbx-labs/08; cat ~/sbx-labs/08/host-canary.txt'
run 'sbx exec lab-08-new ls /home/serra/sbx-labs/08/'
say "Query-parameter rules (0.50.0): must include, not only"
run 'sbx policy allow network --sandbox lab-08-new httpbin.org --method GET --path /anything/report --query format=csv'
run "sleep 3; for q in format=csv format=json '' format=CSV 'format=csv&extra=1' 'format=cs%76'; do printf '%-22s ' \"?\$q\"; sbx exec lab-08-new curl -s -o /dev/null -w '%{http_code}\n' \"https://httpbin.org/anything/report?\$q\"; done"
say "The approval queue still shows only method, host and path"
run "sbx exec lab-08-new curl -s -o /dev/null -w '%{http_code}\n' 'https://httpbin.org/anything/delete?id=42'; sleep 2; sbx policy approval ls | grep -o 'GET httpbin.org:443/anything/delete'"
say "Extra workspaces at a custom target, read-only"
run 'mkdir -p ~/sbx-labs/08/docs && echo "docs from host" > ~/sbx-labs/08/docs/guide.txt'
run "sbx create --name lab-08-mounts shell ~/sbx-labs/08/ws ~/sbx-labs/08/docs:/opt/docs:ro | grep -A1 Workspace"
run "sbx run -d --name lab-08-mounts >/dev/null && sbx exec lab-08-mounts sh -c 'cat /opt/docs/guide.txt; touch /opt/docs/x'"
say "--workdir starts the agent in a subdirectory of the workspace"
run 'mkdir -p ~/sbx-labs/08/ws/src && sbx run --rm --name lab-08-wd --workdir ~/sbx-labs/08/ws/src shell ~/sbx-labs/08/ws -- -c pwd'
say "Stricter checks"
run 'sbx policy allow network --sandbox "" example.org'
run 'sbx exec lab-08-nope true; echo "exit=$?"'
run 'sbx secret set-custom --sandbox lab-08-new --env NOHOST_TOKEN --value fake-nohost-123'
run "sbx settings ls | grep -E 'clipboard|fuse'"
say "Clean up"
run 'sbx rm --force lab-08-new lab-08-mounts'
run 'rm -rf ~/sbx-labs/08'
