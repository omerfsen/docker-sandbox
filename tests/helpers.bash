# Shared helpers for the lab tests. Each lab's test.bats loads this file with
#   load ../../tests/helpers
# The tests drive the real local sandbox daemon, so they create and delete real
# microVMs. Every sandbox name starts with "lab-" so cleanup can find leftovers;
# the tests never touch any other sandbox.

TRAINING_VERSION="$(cat "${BATS_TEST_DIRNAME}/../../VERSION")"
REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"

# Run a command inside a sandbox. Output is exactly what the command printed,
# as long as the sandbox is already running (see create_sandbox).
sx() {
  local name="$1"
  shift
  sbx exec "$name" "$@"
}

# HTTP status code of a request made with curl inside the sandbox. A blocked
# connection prints 000.
http_code() {
  local name="$1"
  shift
  sx "$name" curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$@" || true
}

# Retry a command until it succeeds, for changes that apply asynchronously.
eventually() {
  local tries="${EVENTUALLY_TRIES:-10}" delay="${EVENTUALLY_DELAY:-3}"
  local i
  for ((i = 1; i <= tries; i++)); do
    if "$@"; then
      return 0
    fi
    sleep "$delay"
  done
  return 1
}

# Status of a sandbox as `sbx ls --json` reports it (running, stopped, ...),
# empty when it does not exist.
sandbox_status() {
  sbx ls --json | jq -r --arg n "$1" '.[] | select(.name == $n) | .status'
}

# Create a shell sandbox and keep it running. A sandbox made with `sbx create`
# stops by itself when nothing is attached (and the next exec then prints a
# "started" line); `sbx run -d --name` starts it detached, which keeps it up.
# Create first: `sbx run` without a path would mount the current directory.
# Usage: create_sandbox NAME [WORKSPACE] [extra sbx create flags...]
# Without a workspace the sandbox gets no host bind mount.
create_sandbox() {
  local name="$1" workspace="${2:-}"
  shift $(($# < 2 ? $# : 2))
  delete_sandbox "$name"
  sbx create --name "$name" "$@" shell ${workspace:+"$workspace"} </dev/null >/dev/null 2>&1
  sbx run -d --name "$name" </dev/null >/dev/null 2>&1
}

delete_sandbox() {
  sbx rm --force "$1" >/dev/null 2>&1 || true
  local i
  for ((i = 0; i < 20; i++)); do
    [[ -z "$(sandbox_status "$1")" ]] && return 0
    sleep 1
  done
}

# Succeeds once `sbx policy log NAME` has a line matching an extended regex.
# The proxy writes its log asynchronously, so poll for a few seconds.
log_has() {
  local name="$1" pattern="$2"
  EVENTUALLY_TRIES=8 EVENTUALLY_DELAY=2 eventually _log_matches "$name" "$pattern"
}

_log_matches() {
  sbx policy log "$1" 2>/dev/null | grep -qE "$2"
}
