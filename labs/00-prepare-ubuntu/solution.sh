#!/usr/bin/env bash
# Lab 00 solution: replays the lab's checks on this host.
source "$(dirname "$0")/../../scripts/autoplay.sh"

say "Lab 00 — Prepare a fresh Ubuntu 24.04 host"
run '. /etc/os-release; echo "$PRETTY_NAME"; uname -r; nproc; free -h | head -2'
say "KVM: the CPU flag, the device, and the group"
run "grep -owE 'vmx|svm' /proc/cpuinfo | sort | uniq -c"
run 'ls -l /dev/kvm'
run 'id -nG | tr " " "\n" | grep -x kvm'
say "The course's host check"
run 'scripts/check-host.sh'
