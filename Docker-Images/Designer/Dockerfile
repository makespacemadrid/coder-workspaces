# Imagen base para diseño 2D/3D y electrónica (MakeSpace) basada en coder-mks-desktop-kde
FROM ghcr.io/makespacemadrid/coder-mks-desktop-kde:latest

LABEL org.opencontainers.image.title="coder-mks-design" \
      org.opencontainers.image.description="Entorno de escritorio para diseño 2D/3D y electrónica (FreeCAD, Inkscape, GIMP, KiCad, Blender, PrusaSlicer, OpenSCAD)" \
      org.opencontainers.image.source="https://github.com/makespacemadrid/coder-workspaces" \
      org.opencontainers.image.url="ghcr.io/makespacemadrid/coder-mks-design:latest" \
      com.centurylinklabs.watchtower.enable="true" \
      com.centurylinklabs.watchtower.scope="coder-workspaces" \
      com.centurylinklabs.watchtower.lifecycle="rolling"

USER root

ENV DEBIAN_FRONTEND=noninteractive

# Paquetes adicionales de diseño (la base ya incluye KDE + Firefox)
RUN dpkg --add-architecture i386 && \
    apt-get update && \
    apt-get install -y --no-install-recommends software-properties-common && \
    add-apt-repository -y universe && \
    add-apt-repository -y ppa:mozillateam/ppa && \
    add-apt-repository -y ppa:freecad-maintainers/freecad-stable && \
    printf 'Package: firefox*\nPin: release o=LP-PPA-mozillateam\nPin-Priority: 1001\n' > /etc/apt/preferences.d/mozillateam-firefox && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        build-essential \
        pkg-config \
        python3 python3-venv python3-pip pipx \
        zip unzip p7zip-full \
        fuse3 \
        libfuse2 \
        inkscape \
        gimp \
        krita \
        freecad \
        freecad-common \
        openscad \
        prusa-slicer \
        librecad \
        meshlab \
        kicad \
        kicad-demos \
        kicad-symbols \
        kicad-footprints \
        kicad-packages3d \
        kicad-templates \
        fritzing \
        fritzing-data \
        fritzing-parts \
        imagemagick \
        ffmpeg \
        exiftool \
        pandoc \
        fontforge \
        cifs-utils \
        nfs-common \
        sshfs \
        uidmap \
        # dependencias runtime (Perl/VNC) que queremos preinstalar
        libdatetime-perl \
        liblist-moreutils-perl \
        libyaml-tiny-perl \
        libhash-merge-simple-perl \
        libxfont2 \
        libfontenc1 \
        ssl-cert \
        simulide \
        wine64 \
        wine32 \
        winbind \
        geany \
        desktop-file-utils \
        command-not-found \
        bash-completion \
        nano \
        iputils-ping \
        byobu \
        pulseaudio \
        pulseaudio-utils \
        alsa-utils \
    && rm -rf /var/lib/apt/lists/*

# OrcaSlicer (AppImage), LaserGRBL (Wine) y VisiCut (.deb)
RUN <<'EOSH'
set -e
ORCA_VERSION="2.3.1"
# Prefer the Ubuntu 22.04 build to avoid newer WebKit (libwebkit2gtk-4.1) requirement,
# but keep fallbacks so future tags still resolve.
ORCA_URLS=" \
  https://github.com/OrcaSlicer/OrcaSlicer/releases/download/v${ORCA_VERSION}/OrcaSlicer_Linux_AppImage_Ubuntu2204_V${ORCA_VERSION}.AppImage \
  https://github.com/OrcaSlicer/OrcaSlicer/releases/download/v${ORCA_VERSION}/OrcaSlicer_Linux_AppImage_Ubuntu2404_V${ORCA_VERSION}.AppImage \
  https://github.com/OrcaSlicer/OrcaSlicer/releases/download/v${ORCA_VERSION}/OrcaSlicer_Linux_AppImage_V${ORCA_VERSION}.AppImage \
  https://github.com/OrcaSlicer/OrcaSlicer/releases/download/v${ORCA_VERSION}/OrcaSlicer_Linux.AppImage \
"
found=""
for url in $ORCA_URLS; do
  if curl -fL "$url" -o /usr/local/bin/orcaslicer; then
    found="$url"
    break
  fi
done
if [ -z "$found" ] || [ ! -s /usr/local/bin/orcaslicer ]; then
  echo "OrcaSlicer download failed" >&2
  exit 1
fi
chmod +x /usr/local/bin/orcaslicer
mkdir -p /opt/lasergrbl
LASERGRBL_VERSION="7.14.1"
LASERGRBL_URL="https://github.com/arkypita/LaserGRBL/releases/download/v${LASERGRBL_VERSION}/install.exe"
curl -fL "${LASERGRBL_URL}" -o /opt/lasergrbl/LaserGRBL-install.exe
curl -fL "https://github.com/t-oster/VisiCut/releases/download/2.1/visicut_2.1%2Bdevel-1_all.deb" -o /tmp/visicut.deb
apt-get update
apt-get install -y --no-install-recommends /tmp/visicut.deb
rm /tmp/visicut.deb
rm -rf /var/lib/apt/lists/*
EOSH

# Configuración FUSE para permitir AppImages (allow_other)
RUN echo "user_allow_other" > /etc/fuse.conf

# Locales
RUN locale-gen es_ES.UTF-8 en_US.UTF-8 && \
    update-locale LANG=es_ES.UTF-8

ENV LANG=es_ES.UTF-8 \
    LC_ALL=es_ES.UTF-8

# Utilidades NVIDIA para `nvidia-smi` cuando se habilitan GPUs
RUN set -e; \
    apt-get update; \
    if ! apt-get install -y --no-install-recommends nvidia-utils-535; then \
      if ! apt-get install -y --no-install-recommends nvidia-utils-530; then \
        apt-get install -y --no-install-recommends nvidia-utils-525 || true; \
      fi; \
    fi; \
    rm -rf /var/lib/apt/lists/*

# Desactivar bloqueo/ahorro de pantalla (KDE)
RUN printf '[Daemon]\nTimeout=0\nLockOnResume=false\nLockOnSuspend=false\nAutolock=false\n' > /etc/xdg/kscreenlockerrc

# Extensiones VS Code preinstaladas para escritorio/remoto
RUN su - coder -c 'set -e; \
  EXT_LIST="anthropic.claude-code opencodeai.opencode google.gemini-code-assistant qwen-team.qwen-vscode openai.openai"; \
  for ext in $EXT_LIST; do \
    code --install-extension "$ext" --force --user-data-dir /home/coder/.vscode/data --extensions-dir /home/coder/.vscode/extensions || true; \
  done; \
  mkdir -p /home/coder/.vscode-server/extensions'

# AppImage Pool (gestor de AppImages con actualizaciones e integración en menú)
ARG APPIMAGEPOOL_VERSION=5.0.0
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
cat <<'EOFORCA' > /usr/share/applications/orcaslicer.desktop
[Desktop Entry]
Type=Application
Name=OrcaSlicer
Exec=orcaslicer
Icon=orcaslicer
Categories=Graphics;Utility;
EOFORCA
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

# Crear accesos directos en Desktop para todas las aplicaciones
RUN mkdir -p /etc/skel/Desktop && \
    for f in firefox.desktop org.freecadweb.FreeCAD.desktop org.inkscape.Inkscape.desktop gimp.desktop org.kde.krita.desktop org.kicad.kicad.desktop openscad.desktop PrusaSlicer.desktop librecad.desktop meshlab.desktop org.fritzing.Fritzing.desktop net.launchpad.code.simulide.desktop geany.desktop VisiCut.desktop orcaslicer.desktop appimagepool.desktop; do \
      src="/usr/share/applications/$f"; \
      if [ -f "$src" ]; then ln -sf "$src" "/etc/skel/Desktop/$f"; fi; \
    done && \
    chmod +x /etc/skel/Desktop/*.desktop || true

# Qt WebEngine sandbox workaround (FreeCAD/QtWebEngine apps inside containers)
ENV QTWEBENGINE_DISABLE_SANDBOX=1 \
    QTWEBENGINE_CHROMIUM_FLAGS="--no-sandbox"
