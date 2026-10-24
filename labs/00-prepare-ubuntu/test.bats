#!/usr/bin/env bats
# Lab 00: the host can run sbx microVMs.

load ../../tests/helpers

@test "host check script passes" {
  run "$REPO_ROOT/scripts/check-host.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Host is ready for Docker Sandboxes."* ]]
}

@test "the CPU exposes hardware virtualization" {
  [ "$(uname -m)" != x86_64 ] && skip "vmx/svm flags are an x86 check"
  grep -qwE 'vmx|svm' /proc/cpuinfo
}

@test "/dev/kvm exists and this user can open it" {
  [ -c /dev/kvm ]
  [ -r /dev/kvm ]
  [ -w /dev/kvm ]
}

@test "the user is in the kvm group" {
  run id -nG
  [[ " $output " == *" kvm "* ]]
}
