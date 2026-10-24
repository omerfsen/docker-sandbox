#!/usr/bin/env bash
# Remove everything the course creates: sandboxes whose names start with
# "lab-" and the lab workspaces under ~/sbx-labs. It never touches other
# sandboxes, your secrets, your global policy, or the sbx installation.
#
# Usage: scripts/cleanup.sh
set -uo pipefail

echo "Deleting course sandboxes..."
mapfile -t existing < <(sbx ls -q 2>/dev/null)
for name in "${existing[@]}"; do
  if [[ "$name" == lab-* ]]; then
    sbx rm --force "$name" >/dev/null 2>&1 && echo "  sandbox $name"
  fi
done

if [[ -d "$HOME/sbx-labs" ]]; then
  echo "Removing lab workspaces..."
  rm -rf "$HOME/sbx-labs" && echo "  $HOME/sbx-labs"
fi

echo "Done."
