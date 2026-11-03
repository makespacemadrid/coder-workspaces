#!/usr/bin/env bash
set -euo pipefail

# Pull latest images from GHCR

ORG="ghcr.io/makespacemadrid"
IMAGES=(
  "coder-mks-devtools-base"
  "coder-mks-developer-cli"
  "coder-mks-desktop-kde"
  "coder-mks-design"
  "coder-mks-developer-desktop"
  "coder-mks-developer-re"
  "coder-mks-developer-android"
  "coder-mks-desktop"
  "coder-mks-developer"
)

for img in "${IMAGES[@]}"; do
  echo ">> Pulling ${ORG}/${img}:latest"
  docker pull "${ORG}/${img}:latest"
done

echo "Done."
