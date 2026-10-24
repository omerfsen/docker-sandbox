#!/usr/bin/env bash
# Lab 07 solution: cleans up what the course created. Global commands (prune,
# secret rm anthropic, logout, reset, uninstall) are shown, not run.
source "$(dirname "$0")/../../scripts/autoplay.sh"

say "Lab 07 — Clean up"
say "Two leftovers to clean: one running, one stopped"
run_quiet 'sbx rm --force lab-07-a lab-07-b'
run 'sbx create --name lab-07-a shell && sbx run -d --name lab-07-a && sbx create --name lab-07-b shell && sbx stop lab-07-b'
run "sbx ls | grep -E 'SANDBOX|lab-'"
say "prune removes every stopped sandbox, not just the course's: look first"
run "sbx prune --dry-run | grep -E 'Would|SANDBOX|lab-'"
say "The course's cleanup script only touches lab-* sandboxes and ~/sbx-labs"
run 'scripts/cleanup.sh'
run "sbx ls | grep -E 'lab-' || echo no lab sandboxes left"
say "Where the disk space goes"
run 'du -sh ~/.local/state/sandboxes; sbx template ls'
say "Remove the Anthropic key from Lab 06 when you are done: sbx secret rm anthropic -f"
say "Sign out (stops running sandboxes): sbx logout"
say "Back to a fresh install (deletes ALL sandboxes, images, policies, secrets): sbx reset"
say "Uninstall: sudo apt-mark unhold docker-sbx && sudo apt-get purge -y docker-sbx"
