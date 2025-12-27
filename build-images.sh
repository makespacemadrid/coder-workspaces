#!/usr/bin/env bash
set -euo pipefail

# Build all workspace images locally (tags use ghcr.io/makespacemadrid/*:latest)

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

build() {
  local context="$1"
  local tag="$2"
  echo ">> Building ${tag} from ${context}"
  docker build -t "${tag}" "${ROOT_DIR}/${context}"
}

build "Docker-Images/Desktop" "ghcr.io/makespacemadrid/coder-mks-desktop:latest"
build "Docker-Images/Desktop-KDE" "ghcr.io/makespacemadrid/coder-mks-desktop-kde:latest"
build "Docker-Images/Developer" "ghcr.io/makespacemadrid/coder-mks-developer:latest"
build "Docker-Images/DeveloperAndroid" "ghcr.io/makespacemadrid/coder-mks-developer-android:latest"
build "Docker-Images/Designer" "ghcr.io/makespacemadrid/coder-mks-design:latest"

echo "Done."
