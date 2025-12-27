#!/usr/bin/env bash
set -euo pipefail

# Push all Coder templates under workspaces/
# Requires: coder CLI logged in (`coder login`)

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACES=(
  "Developer"
  "AdvancedHostDANGER"
  "DeveloperAndroid"
  "Maker"
  "Minimal"
)

ICON_BASE_URL="https://raw.githubusercontent.com/makespacemadrid/coder-workspaces/main"

for ws in "${WORKSPACES[@]}"; do
  dir="${ROOT_DIR}/workspaces/${ws}"
  if [ ! -d "$dir" ]; then
    echo "Skipping ${ws}: not found at ${dir}" >&2
    continue
  fi
  echo ">> Pushing template ${ws}..."
  coder templates push --yes --directory "$dir"

  icon_path="$dir/icon.svg"
  if [ -f "$icon_path" ]; then
    icon_url="${ICON_BASE_URL}/workspaces/${ws}/icon.svg"
    echo ">> Updating icon for ${ws}..."
    coder templates edit --yes --icon "$icon_url" "$ws"
  else
    echo "!! Missing icon for ${ws}: ${icon_path}" >&2
  fi
done

echo "Done."
