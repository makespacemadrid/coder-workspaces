# Imagen headless para DeveloperCLI (sustituye a Minimal). Todo el tooling
# vive ya en DevTools-Base (Docker Engine, Node24+CLIs IA, utilidades); esta
# imagen no añade nada propio. code-server se instala vía módulo de Coder en
# runtime (igual que hoy), no se hornea aquí.
FROM ghcr.io/makespacemadrid/coder-mks-devtools-base:latest

LABEL org.opencontainers.image.title="coder-mks-developer-cli" \
      org.opencontainers.image.description="DeveloperCLI: tooling de desarrollo headless (Docker Engine, Node24+CLIs IA)" \
      org.opencontainers.image.source="https://github.com/makespacemadrid/coder-workspaces" \
      org.opencontainers.image.url="ghcr.io/makespacemadrid/coder-mks-developer-cli:latest" \
      com.centurylinklabs.watchtower.enable="true" \
      com.centurylinklabs.watchtower.scope="coder-workspaces" \
      com.centurylinklabs.watchtower.lifecycle="rolling"
