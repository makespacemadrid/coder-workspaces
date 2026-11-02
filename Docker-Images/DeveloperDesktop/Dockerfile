# Escritorio de desarrollo general (sustituye a Developer). FROM Desktop-KDE,
# que ya trae KDE real, Firefox/Chrome, Docker Engine, Node24+CLIs IA, Claude
# Desktop y OpenCode Desktop. Aquí solo se añade lo que es específico de este
# template: GitHub Desktop, Antigravity, VS Code+extensiones, AppImage Pool.
FROM ghcr.io/makespacemadrid/coder-mks-desktop-kde:latest

LABEL org.opencontainers.image.title="coder-mks-developer-desktop" \
      org.opencontainers.image.description="Coder Desktop KDE extendido con GitHub Desktop, Antigravity, VS Code y AppImage Pool" \
      org.opencontainers.image.source="https://github.com/makespacemadrid/coder-workspaces" \
      org.opencontainers.image.url="ghcr.io/makespacemadrid/coder-mks-developer-desktop:latest" \
      com.centurylinklabs.watchtower.enable="true" \
      com.centurylinklabs.watchtower.scope="coder-workspaces" \
      com.centurylinklabs.watchtower.lifecycle="rolling"

USER root

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install -y --no-install-recommends geany && \
    rm -rf /var/lib/apt/lists/*

# Antigravity: el módulo de Coder solo registra el botón/app (verificado en el
# código del módulo), el binario tiene que estar instalado aquí.
RUN install -m 0755 -d /etc/apt/keyrings && \
    curl -fsSL https://us-central1-apt.pkg.dev/doc/repo-signing-key.gpg | gpg --dearmor --yes -o /etc/apt/keyrings/antigravity-repo-key.gpg && \
    chmod a+r /etc/apt/keyrings/antigravity-repo-key.gpg && \
    echo "deb [signed-by=/etc/apt/keyrings/antigravity-repo-key.gpg] https://us-central1-apt.pkg.dev/projects/antigravity-auto-updater-dev/ antigravity-debian main" \
      | tee /etc/apt/sources.list.d/antigravity.list > /dev/null && \
    apt-get update && \
    apt-get install -y --no-install-recommends antigravity && \
    rm -rf /var/lib/apt/lists/*

# Visual Studio Code (repositorio oficial Microsoft)
RUN install -m 0755 -d /etc/apt/keyrings && \
    curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor -o /etc/apt/keyrings/microsoft.gpg && \
    chmod a+r /etc/apt/keyrings/microsoft.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/code stable main" \
      | tee /etc/apt/sources.list.d/vscode.list > /dev/null && \
    apt-get update && \
    apt-get install -y --no-install-recommends code && \
    rm -rf /var/lib/apt/lists/*

# GitHub Desktop (shiftkey build)
ARG GITHUB_DESKTOP_REPO=shiftkey/desktop
RUN set -e; \
    GH_DESKTOP_URL="$(curl -fsSL "https://api.github.com/repos/${GITHUB_DESKTOP_REPO}/releases/latest" | \
      jq -r '.assets[] | select(.name | test("GitHubDesktop-linux-amd64-.*\\.deb$")) | .browser_download_url' | head -n1)"; \
    if [ -z "$GH_DESKTOP_URL" ]; then \
      echo "No se encontró URL .deb válida para GitHub Desktop" >&2; \
      exit 1; \
    fi; \
    curl -fsSL "$GH_DESKTOP_URL" -o /tmp/github-desktop.deb; \
    apt-get update && \
    apt-get install -y --no-install-recommends gnome-keyring /tmp/github-desktop.deb; \
    rm -rf /var/lib/apt/lists/* /tmp/github-desktop.deb

# Electron apps dentro de contenedores Docker necesitan desactivar el sandbox
# (no hay user namespaces). Los wrappers añaden --no-sandbox y pistas de Ozone.
# ELECTRON_DISABLE_SANDBOX/OZONE/COWORK_VM_BACKEND ya son ENV globales de la base.
RUN <<'EOSH'
set -e
wrap() {
  local name="$1"; local target="$2"; local extra="$3"
  if [ -x "$target" ]; then
    mv "$name" "${name}.real" || true
    cat > "$name" <<SHWRAP
#!/bin/sh
exec env ELECTRON_DISABLE_SANDBOX=1 ELECTRON_OZONE_PLATFORM_HINT="${ELECTRON_OZONE_PLATFORM_HINT:-auto}" COWORK_VM_BACKEND="${COWORK_VM_BACKEND:-host}" \
  "$target" --no-sandbox --disable-gpu-sandbox --disable-setuid-sandbox --disable-seccomp-filter-sandbox --no-zygote $EXTRA_FLAGS "$@"
SHWRAP
    chmod +x "$name"
  fi
}
TARGET_BIN=/usr/lib/github-desktop/github-desktop EXTRA_FLAGS="--password-store=basic" wrap /usr/bin/github-desktop /usr/lib/github-desktop/github-desktop
TARGET_BIN=/usr/share/code/bin/code EXTRA_FLAGS="" wrap /usr/bin/code /usr/share/code/bin/code
EOSH

# Extensiones VS Code preinstaladas para escritorio/remoto
RUN su - coder -c 'set -e; \
  EXT_LIST="anthropic.claude-code opencodeai.opencode google.gemini-code-assistant qwen-team.qwen-vscode openai.openai"; \
  for ext in $EXT_LIST; do \
    code --install-extension "$ext" --force --user-data-dir /home/coder/.vscode/data --extensions-dir /home/coder/.vscode/extensions || true; \
  done; \
  mkdir -p /home/coder/.vscode-server/extensions'

# AppImage Pool (gestor de AppImages con actualizaciones e integración en menú)
ARG APPIMAGEPOOL_VERSION=5.1.0
RUN <<'EOSH'
set -e
mkdir -p /opt/appimagepool
APPIMAGE_URLS=" \
  https://github.com/prateekmedia/appimagepool/releases/download/${APPIMAGEPOOL_VERSION}/appimagepool-${APPIMAGEPOOL_VERSION}-x86_64.AppImage \
  https://github.com/prateekmedia/appimagepool/releases/download/${APPIMAGEPOOL_VERSION}/AppImagePool-${APPIMAGEPOOL_VERSION}-x86_64.AppImage \
  https://github.com/prateekmedia/appimagepool/releases/download/${APPIMAGEPOOL_VERSION}/AppImagePool-${APPIMAGEPOOL_VERSION}.x86_64.AppImage \
  https://github.com/prateekmedia/appimagepool/releases/latest/download/appimagepool-latest-x86_64.AppImage \
  https://github.com/prateekmedia/appimagepool/releases/latest/download/AppImagePool-latest-x86_64.AppImage \
"
found=""
for url in $APPIMAGE_URLS; do
  if curl -fLsS "${url}" -o /opt/appimagepool/AppImagePool.AppImage; then
    found="$url"
    break
  fi
done
if [ -z "$found" ] || [ ! -s /opt/appimagepool/AppImagePool.AppImage ]; then
  echo "AppImage Pool download failed" >&2
  exit 1
fi
chmod +x /opt/appimagepool/AppImagePool.AppImage
ln -sf /opt/appimagepool/AppImagePool.AppImage /usr/local/bin/appimagepool
cat <<'EOFICON' > /usr/share/icons/hicolor/scalable/apps/appimagepool.svg
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" role="img">
  <defs>
    <linearGradient id="grad" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0%" stop-color="#1b8cf2"/>
      <stop offset="100%" stop-color="#0c5ea8"/>
    </linearGradient>
  </defs>
  <rect width="64" height="64" rx="12" fill="url(#grad)"/>
  <path fill="#fff" d="M32 10c-3 0-5.4 2.4-5.4 5.4S29 20.8 32 20.8s5.4-2.4 5.4-5.4S35 10 32 10Zm0 12.9c-3 0-5.4 2.4-5.4 5.4S29 33.6 32 33.6s5.4-2.4 5.4-5.4S35 22.9 32 22.9Zm0 12.9c-3 0-5.4 2.4-5.4 5.4S29 46.6 32 46.6s5.4-2.4 5.4-5.4S35 35.8 32 35.8Z"/>
  <path fill="#e8f3ff" d="M18 18h4v28h-4zm24 0h4v28h-4z"/>
</svg>
EOFICON
cat <<'EOF' > /usr/share/applications/appimagepool.desktop
[Desktop Entry]
Type=Application
Name=AppImage Pool
Exec=appimagepool
Icon=appimagepool
Categories=Utility;
EOF
EOSH
RUN update-desktop-database /usr/share/applications || true && \
    gtk-update-icon-cache -q /usr/share/icons/hicolor || true

# Accesos directos en el escritorio por defecto
RUN set -e; \
    mkdir -p /etc/skel/Desktop && \
    for f in com.microsoft.VSCode.desktop github-desktop.desktop com.anthropic.Claude.desktop OpenCode.desktop firefox.desktop geany.desktop appimagepool.desktop; do \
      src="/usr/share/applications/$f"; \
      if [ -f "$src" ]; then ln -sf "$src" "/etc/skel/Desktop/$f"; fi; \
    done; \
    chmod +x /etc/skel/Desktop/*.desktop || true
