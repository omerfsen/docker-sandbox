#!/usr/bin/env bash
# Checks that this host can run Docker Sandboxes (sbx) microVMs.
# Prints one line per requirement and exits non-zero if any check fails.
set -u

fail=0
ok()   { printf '  [ok]   %s\n' "$*"; }
bad()  { printf '  [FAIL] %s\n' "$*"; fail=1; }
warn() { printf '  [warn] %s\n' "$*"; }

echo "Docker Sandboxes host check"

if [[ -r /etc/os-release ]]; then
  . /etc/os-release
  if [[ "${ID:-}" == ubuntu && "${VERSION_ID:-}" == 24.04 ]]; then
    ok "OS: $PRETTY_NAME"
  else
    warn "OS: ${PRETTY_NAME:-unknown} (the labs are written for Ubuntu 24.04)"
  fi
fi

arch="$(uname -m)"
case "$arch" in
  x86_64 | aarch64) ok "architecture: $arch" ;;
  *) bad "architecture: $arch (the labs need x86_64 or aarch64)" ;;
esac

# On x86 the CPU must expose hardware virtualization. Inside a cloud VM that
# means nested virtualization is switched on.
if [[ "$arch" == x86_64 ]]; then
  if grep -qwE 'vmx|svm' /proc/cpuinfo; then
    ok "CPU virtualization: $(grep -owE 'vmx|svm' /proc/cpuinfo | sort -u | xargs)"
  else
    bad "CPU has no vmx/svm flag (turn on nested virtualization for this VM)"
  fi
fi

if [[ -c /dev/kvm ]]; then
  ok "/dev/kvm present"
else
  bad "/dev/kvm is missing (KVM is not available on this machine)"
fi

if id -nG | tr ' ' '\n' | grep -qx kvm; then
  ok "$USER is in the kvm group"
else
  bad "$USER is not in the kvm group (sudo usermod -aG kvm \$USER, then log out and back in)"
fi

if [[ -r /dev/kvm && -w /dev/kvm ]]; then
  ok "/dev/kvm is readable and writable by this shell"
else
  bad "/dev/kvm is not accessible from this shell (log out and back in after joining kvm)"
fi

# The sandbox daemon runs under the systemd user manager. If that manager was
# started before you joined kvm, the daemon still has the old groups.
pid="$(pgrep -u "$USER" -f '^/usr/bin/sbx daemon start' | head -1)"
if [[ -n "$pid" ]]; then
  kvm_gid="$(getent group kvm | cut -d: -f3)"
  if grep '^Groups:' "/proc/$pid/status" | tr -s ' \t' '\n' | grep -qx "$kvm_gid"; then
    ok "sandbox daemon (pid $pid) has the kvm group"
  else
    bad "sandbox daemon (pid $pid) lacks the kvm group (log out fully or reboot, then sbx daemon restart)"
  fi
fi

avail_gb="$(df -BG --output=avail "$HOME" | tail -1 | tr -dc '0-9')"
if ((avail_gb >= 15)); then
  ok "disk: ${avail_gb} GB free in $HOME"
else
  warn "disk: ${avail_gb} GB free in $HOME (each agent image needs a few GB; 15 GB or more is comfortable)"
fi

for tool in curl git jq; do
  if command -v "$tool" >/dev/null 2>&1; then ok "$tool"; else bad "$tool is missing (sudo apt install $tool)"; fi
done

if command -v bats >/dev/null 2>&1; then
  ok "bats $(bats --version | awk '{print $2}') (lab tests)"
else
  warn "bats is missing; install it to run the lab tests (sudo apt install bats)"
fi

if command -v sbx >/dev/null 2>&1; then
  ok "sbx installed: $(sbx version | awk '{print $3}')"
else
  warn "sbx is not installed yet (Lab 01 installs it)"
fi

if ((fail)); then
  echo "Some checks failed. Fix them before installing Docker Sandboxes."
  exit 1
fi
echo "Host is ready for Docker Sandboxes."
