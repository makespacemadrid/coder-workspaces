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

# Orden de dependencias: DevTools-Base -> {DeveloperCLI, Desktop-KDE} ->
# Desktop-KDE -> {Designer, DeveloperDesktop} -> DeveloperDesktop -> {DeveloperRE, DeveloperAndroid}
build "Docker-Images/DevTools-Base" "ghcr.io/makespacemadrid/coder-mks-devtools-base:latest"
build "Docker-Images/DeveloperCLI" "ghcr.io/makespacemadrid/coder-mks-developer-cli:latest"
build "Docker-Images/Desktop-KDE" "ghcr.io/makespacemadrid/coder-mks-desktop-kde:latest"
build "Docker-Images/Designer" "ghcr.io/makespacemadrid/coder-mks-design:latest"
build "Docker-Images/DeveloperDesktop" "ghcr.io/makespacemadrid/coder-mks-developer-desktop:latest"
build "Docker-Images/DeveloperRE" "ghcr.io/makespacemadrid/coder-mks-developer-re:latest"
build "Docker-Images/DeveloperAndroid" "ghcr.io/makespacemadrid/coder-mks-developer-android:latest"

# Cadena heredada (MATE/KasmVNC), todavía en uso por OpenClaw/Hermes.
build "Docker-Images/Desktop" "ghcr.io/makespacemadrid/coder-mks-desktop:latest"
build "Docker-Images/Developer" "ghcr.io/makespacemadrid/coder-mks-developer:latest"

echo "Done."
