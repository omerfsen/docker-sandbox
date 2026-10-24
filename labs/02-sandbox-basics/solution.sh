#!/usr/bin/env bash
# Lab 02 solution: replays the lab against your sbx daemon.
source "$(dirname "$0")/../../scripts/autoplay.sh"

say "Lab 02 — Sandbox basics"
run_quiet 'sbx rm --force lab-02-basics lab-02-nows lab-02-once; rm -rf ~/sbx-labs/02 ~/sbx-labs/02-out'
run 'mkdir -p ~/sbx-labs/02 && echo "hello from the host" > ~/sbx-labs/02/README.txt'
run 'sbx create --name lab-02-basics shell ~/sbx-labs/02'
run "sbx ls | grep -E 'SANDBOX|lab-'"
say "A microVM with its own kernel, and your workspace at the same path"
run "uname -r; sbx exec lab-02-basics sh -c '. /etc/os-release; echo \$PRETTY_NAME; uname -r'"
run 'sbx exec lab-02-basics id'
run 'sbx exec lab-02-basics sh -c "pwd; cat README.txt"'
run "sbx exec lab-02-basics sh -c 'echo written-in-the-sandbox > from-sandbox.txt'; cat ~/sbx-labs/02/from-sandbox.txt"
run "sbx exec lab-02-basics sh -c 'mount | grep virtiofs'"
say "Not root by default, but root is one sudo away inside the VM"
run "sbx exec lab-02-basics sh -c 'touch /etc/probe'"
run 'sbx exec lab-02-basics sudo -n id -u; sbx exec -u root lab-02-basics id -u'
say "exec behaves like docker exec: exit codes, stdin, env"
run "sbx exec lab-02-basics sh -c 'exit 3'; echo \"exit code: \$?\""
run 'echo "piped stdin" | sbx exec -i lab-02-basics cat'
run "sbx exec -e GREETING=merhaba lab-02-basics sh -c 'echo \$GREETING'"
say "A created sandbox stops by itself when nothing is attached"
run "sleep 35; sbx ls --json | jq -r '.[] | select(.name == \"lab-02-basics\") | .status'"
run 'sbx exec lab-02-basics cat README.txt'
say "run -d keeps it running, detached"
run 'sbx run -d --name lab-02-basics'
run "sleep 35; sbx ls | grep -E 'SANDBOX|lab-02'"
say "stop keeps everything inside the VM"
run "sbx exec lab-02-basics sh -c 'echo kept > ~/keep.txt' && sbx stop lab-02-basics"
run 'sbx exec lab-02-basics cat /home/agent/keep.txt'
say "Copy files in and out"
run 'mkdir -p ~/sbx-labs/02-out && echo "copied in" > ~/sbx-labs/02-out/in.txt'
run 'sbx cp ~/sbx-labs/02-out/in.txt lab-02-basics:/home/agent/ && sbx exec lab-02-basics cat /home/agent/in.txt'
run 'sbx cp lab-02-basics:/etc/os-release ~/sbx-labs/02-out/ && ls -l ~/sbx-labs/02-out/os-release'
run 'sbx cp -L lab-02-basics:/etc/os-release ~/sbx-labs/02-out/os-release-real && head -1 ~/sbx-labs/02-out/os-release-real'
run 'sbx cp ~/sbx-labs/02-out/in.txt lab-02-basics:/etc/ && sbx exec lab-02-basics ls -l /etc/in.txt'
say "No workspace: the agent works in the VM's own filesystem"
run 'sbx create --name lab-02-nows shell'
run 'sbx exec lab-02-nows sh -c "pwd; ls -A"'
say "Throwaway sandbox: run --rm removes it when the session ends"
run "sbx run --rm --name lab-02-once shell ~/sbx-labs/02 -- -c 'echo hello from \$(hostname) as \$(id -un)'"
run 'sbx ls -q | grep lab-02'
say "Clean up (rm asks for confirmation in a terminal; --force skips it)"
run 'sbx rm --force lab-02-basics lab-02-nows'
run 'rm -rf ~/sbx-labs/02 ~/sbx-labs/02-out'
