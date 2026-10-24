#!/usr/bin/env bash
# Lab 01 solution: shows the installed, signed-in state on this host.
source "$(dirname "$0")/../../scripts/autoplay.sh"

say "Lab 01 — Install sbx and sign in"
say "Installed with: sudo apt-get install -y docker-sbx=0.49.2-1~ubuntu.24.04~noble && sudo apt-mark hold docker-sbx"
run 'apt-cache policy docker-sbx | head -6; apt-mark showhold'
run 'sbx version'
say "What the package put on the machine"
run "dpkg -L docker-sbx | grep -E '^/(usr/bin|usr/libexec|etc)/' | grep -v '/lib\$'"
say "Signed in with: sbx login (device code in the browser), then: sbx policy init balanced"
run 'sbx setup < /dev/null'
say "The daemon: one per user, started by the CLI when needed"
run 'sbx daemon status'
run "grep Groups /proc/\$(pgrep -f '^/usr/bin/sbx daemon start')/status; getent group kvm"
run "tail -20 ~/.local/state/sandboxes/sandboxes/sandboxd/daemon.log | grep '}\$' | jq -c '{time, level, msg}' | tail -3"
say "One command checks the whole installation"
run 'sbx diagnose'
