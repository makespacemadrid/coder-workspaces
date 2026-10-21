#!/usr/bin/env bash
set -euo pipefail

# Pull latest images from GHCR

ORG="ghcr.io/makespacemadrid"
IMAGES=(
  "coder-mks-desktop"
  "coder-mks-desktop-kde"
  "coder-mks-developer"
  "coder-mks-developer-android"
  "coder-mks-design"
  "coder-mks-design-selkies"
  "coder-mks-developer-android-selkies"
)

for img in "${IMAGES[@]}"; do
  echo ">> Pulling ${ORG}/${img}:latest"
  docker pull "${ORG}/${img}:latest"
done

echo "Done."
