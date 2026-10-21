# Webtop KDE acelerado por Selkies para el template Coder MakerSelkies.
# La imagen base aporta KDE, Wayland/X11, audio, WebCodecs/WebRTC y deteccion GPU.
FROM lscr.io/linuxserver/webtop:ubuntu-kde

LABEL org.opencontainers.image.title="coder-mks-design-selkies" \
      org.opencontainers.image.description="Webtop KDE/Selkies para impresion 3D con OrcaSlicer, PrusaSlicer, Cura y herramientas CAD" \
      org.opencontainers.image.source="https://github.com/makespacemadrid/coder-workspaces" \
      org.opencontainers.image.url="ghcr.io/makespacemadrid/coder-mks-design-selkies:latest" \
      com.centurylinklabs.watchtower.enable="true" \
      com.centurylinklabs.watchtower.scope="coder-workspaces" \
      com.centurylinklabs.watchtower.lifecycle="rolling"

ARG DEBIAN_FRONTEND=noninteractive
ARG ORCA_VERSION=2.4.2
ARG CURA_VERSION=5.13.0
ARG FREECAD_VERSION=1.1.4
ARG BLENDER_VERSION=5.2.2
ARG GIMP_VERSION=3.2.6
ARG KRITA_VERSION=5.3.4
ARG FREEROUTING_VERSION=2.4.1
ARG APPIMAGEPOOL_VERSION=5.1.0

ENV TITLE="MakeSpace Maker (Selkies)" \
    TZ="Europe/Madrid" \
    LANG="es_ES.UTF-8" \
    LC_ALL="es_ES.UTF-8" \
    START_DOCKER="false" \
    SELKIES_MODE="websockets" \
    NVIDIA_DRIVER_CAPABILITIES="compute,utility,graphics,video" \
    ELECTRON_DISABLE_SANDBOX="1" \
    ELECTRON_OZONE_PLATFORM_HINT="auto" \
    COWORK_VM_BACKEND="host" \
    QTWEBENGINE_DISABLE_SANDBOX="1" \
    QTWEBENGINE_CHROMIUM_FLAGS="--no-sandbox"

# Aplicaciones instaladas desde Ubuntu. OrcaSlicer, Cura y FreeCAD se extraen
# de sus AppImages para no necesitar FUSE ni SYS_ADMIN durante la ejecucion.
RUN <<'EOSH'
set -eux
# Webtop usa XtraDeb para Chromium. Ya esta instalado en la imagen base y ese
# PPA resulta innecesariamente fragil para el gran lote CAD de esta capa.
for source in /etc/apt/sources.list.d/*xtradeb*; do
  [ -e "$source" ] || continue
  mv "$source" "/etc/apt/$(basename "$source").disabled"
done
apt-get update
dpkg --add-architecture i386
apt-get update
apt-get install -y --no-install-recommends \
    admesh \
    assimp-utils \
    avrdude \
    alsa-utils \
    bash-completion \
    build-essential \
    byobu \
    ca-certificates \
    cifs-utils \
    command-not-found \
    curl \
    desktop-file-utils \
    dfu-util \
    file \
    ffmpeg \
    fontforge \
    fritzing \
    fritzing-data \
    fritzing-parts \
    fuse3 \
    geany \
    gimp \
    git \
    gnupg \
    imagemagick \
    inkscape \
    iputils-ping \
    jq \
    kicad \
    kicad-demos \
    kicad-libraries \
    kicad-packages3d \
    kicad-templates \
    krita \
    libgl1 \
    libgl1-mesa-dri \
    libimage-exiftool-perl \
    libfuse2 \
    librecad \
    libvulkan1 \
    locales \
    mesa-utils \
    mesa-vulkan-drivers \
    meshlab \
    nano \
    nfs-common \
    openjdk-21-jre-headless \
    openscad \
    pandoc \
    p7zip-full \
    pipx \
    pkg-config \
    prusa-slicer \
    pulseaudio-utils \
    python3-pip \
    python3-requests \
    python3-serial \
    python3-venv \
    simulide \
    sshfs \
    unzip \
    uidmap \
    usbutils \
    vainfo \
    vulkan-tools \
    wget \
    winbind \
    wine32 \
    wine64 \
    xz-utils \
    zip
locale-gen es_ES.UTF-8 en_US.UTF-8
update-alternatives --set java /usr/lib/jvm/java-21-openjdk-amd64/bin/java
rm -rf /var/lib/apt/lists/* /var/tmp/* /tmp/*
EOSH

# Freerouting, usado por el flujo de autorouter de KiCad.
RUN install -d /opt/freerouting && \
    curl -fsSL -o /opt/freerouting/freerouting.jar \
      "https://github.com/freerouting/freerouting/releases/download/v${FREEROUTING_VERSION}/freerouting-${FREEROUTING_VERSION}.jar"

RUN <<'EOSH'
set -eux
workdir="$(mktemp -d)"
cd "$workdir"
orca_found=""
for url in \
  "https://github.com/OrcaSlicer/OrcaSlicer/releases/download/v${ORCA_VERSION}/OrcaSlicer_Linux_AppImage_Ubuntu2404_V${ORCA_VERSION}.AppImage" \
  "https://github.com/OrcaSlicer/OrcaSlicer/releases/download/v${ORCA_VERSION}/OrcaSlicer_Linux_AppImage_Ubuntu2204_V${ORCA_VERSION}.AppImage" \
  "https://github.com/OrcaSlicer/OrcaSlicer/releases/download/v${ORCA_VERSION}/OrcaSlicer_Linux_AppImage_V${ORCA_VERSION}.AppImage"; do
  if curl -fL "$url" -o orca.AppImage; then
    orca_found="$url"
    break
  fi
done
if [ -z "$orca_found" ] || [ ! -s orca.AppImage ]; then
  echo "No se pudo descargar OrcaSlicer ${ORCA_VERSION}" >&2
  exit 1
fi
chmod +x orca.AppImage
./orca.AppImage --appimage-extract >/dev/null
mv squashfs-root /opt/orcaslicer

curl -fL \
  "https://github.com/Ultimaker/Cura/releases/download/${CURA_VERSION}/UltiMaker-Cura-${CURA_VERSION}-linux-X64.AppImage" \
  -o cura.AppImage
chmod +x cura.AppImage
./cura.AppImage --appimage-extract >/dev/null
mv squashfs-root /opt/cura

curl -fL \
  "https://github.com/FreeCAD/FreeCAD/releases/download/${FREECAD_VERSION}/FreeCAD_${FREECAD_VERSION}-Linux-x86_64-py311.AppImage" \
  -o freecad.AppImage
printf '%s  %s\n' \
  'f6dc6ba676e5ac96a565ebc8d657232f94c6158e85b4352141bd1a46f6b43434' \
  'freecad.AppImage' | sha256sum -c -
chmod +x freecad.AppImage
./freecad.AppImage --appimage-extract >/dev/null
mv squashfs-root /opt/freecad

curl -fL \
  "https://download.gimp.org/gimp/v3.2/linux/GIMP-${GIMP_VERSION}-x86_64.AppImage" \
  -o gimp.AppImage
chmod +x gimp.AppImage
./gimp.AppImage --appimage-extract >/dev/null
mv squashfs-root /opt/gimp

curl -fL \
  "https://download.kde.org/stable/krita/${KRITA_VERSION}/krita-${KRITA_VERSION}-x86_64.AppImage" \
  -o krita.AppImage
chmod +x krita.AppImage
./krita.AppImage --appimage-extract >/dev/null
mv squashfs-root /opt/krita

ln -s /opt/orcaslicer/AppRun /usr/local/bin/orcaslicer
ln -s /opt/cura/AppRun /usr/local/bin/cura
ln -s /opt/freecad/AppRun /usr/local/bin/freecad
ln -s /opt/gimp/AppRun /usr/local/bin/gimp
ln -s /opt/krita/AppRun /usr/local/bin/krita
rm -rf "$workdir"
EOSH

# El metapaquete aporta el selector /usr/bin/wine para aplicaciones como
# LaserGRBL. Firefox se instala desde el tarball oficial (el paquete de Ubuntu
# es un lanzador de Snap, que no funciona bien dentro del contenedor).
RUN <<'EOSH'
set -eux
apt-get update
apt-get install -y --no-install-recommends wine
curl -fL "https://download.mozilla.org/?product=firefox-latest&os=linux64&lang=es-ES" -o /tmp/firefox.tar.xz
tar -xf /tmp/firefox.tar.xz -C /opt
ln -s /opt/firefox/firefox /usr/local/bin/firefox
rm -f /tmp/firefox.tar.xz
rm -rf /var/lib/apt/lists/*
EOSH

# Blender oficial, LaserGRBL, VisiCut y los clientes de IA presentes en Maker.
RUN <<'EOSH'
set -eux
blender_pkg="blender-${BLENDER_VERSION}-linux-x64"
blender_series="$(printf '%s' "$BLENDER_VERSION" | cut -d. -f1-2)"
curl -fL "https://download.blender.org/release/Blender${blender_series}/${blender_pkg}.tar.xz" -o /tmp/blender.tar.xz
tar -xJf /tmp/blender.tar.xz -C /opt
mv "/opt/${blender_pkg}" /opt/blender
ln -s /opt/blender/blender /usr/local/bin/blender

install -d /opt/lasergrbl
curl -fL "https://github.com/arkypita/LaserGRBL/releases/download/v7.14.1/install.exe" \
  -o /opt/lasergrbl/LaserGRBL-install.exe
curl -fL "https://github.com/t-oster/VisiCut/releases/download/2.1/visicut_2.1%2Bdevel-1_all.deb" \
  -o /tmp/visicut.deb
curl -fL "https://opencode.ai/es/download/stable/linux-x64-deb" \
  -o /tmp/opencode-desktop.deb
apt-get update
apt-get install -y --no-install-recommends libwebkit2gtk-4.1-0 /tmp/visicut.deb /tmp/opencode-desktop.deb
if [ -x /opt/OpenCode/ai.opencode.desktop ]; then
  mv /opt/OpenCode/ai.opencode.desktop /opt/OpenCode/ai.opencode.desktop.real
  printf '%s\n' '#!/bin/sh' \
    'exec /opt/OpenCode/ai.opencode.desktop.real --no-sandbox --disable-gpu-sandbox --disable-setuid-sandbox --disable-seccomp-filter-sandbox --no-zygote "$@"' \
    > /opt/OpenCode/ai.opencode.desktop
  chmod +x /opt/OpenCode/ai.opencode.desktop
fi
if [ -f /usr/share/applications/ai.opencode.desktop.desktop ]; then
  ln -sf /usr/share/applications/ai.opencode.desktop.desktop /usr/share/applications/OpenCode.desktop
fi
rm -f /tmp/blender.tar.xz /tmp/visicut.deb /tmp/opencode-desktop.deb
rm -rf /var/lib/apt/lists/*
EOSH

RUN <<'EOSH'
set -e
if curl -fsSLo /usr/share/keyrings/claude-desktop-archive-keyring.asc https://downloads.claude.ai/claude-desktop/key.asc; then
  echo "deb [arch=amd64,arm64 signed-by=/usr/share/keyrings/claude-desktop-archive-keyring.asc] https://downloads.claude.ai/claude-desktop/apt/stable stable main" > /etc/apt/sources.list.d/claude-desktop.list
  apt-get update && apt-get install -y --no-install-recommends claude-desktop || \
    echo "WARN: Claude Desktop no se pudo instalar; se continua sin la aplicacion" >&2
fi
rm -rf /var/lib/apt/lists/*
EOSH

# Node 24, CLIs de IA, uv y OpenCode CLI.
RUN <<'EOSH'
set -eux
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg
echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_24.x nodistro main" > /etc/apt/sources.list.d/nodesource.list
apt-get update
apt-get install -y --no-install-recommends nodejs
npm install -g --omit=dev --no-update-notifier --no-fund @openai/codex @anthropic-ai/claude-code
npm cache clean --force
curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR=/usr/local/bin UV_NO_MODIFY_PATH=1 sh
export HOME=/opt/opencode-cli
mkdir -p "$HOME"
curl -fsSL https://opencode.ai/install | bash -s -- --no-modify-path
install -m 0755 /opt/opencode-cli/.opencode/bin/opencode /usr/local/bin/opencode
rm -rf /var/lib/apt/lists/*
EOSH

# VS Code y las mismas extensiones de asistencia que lleva Maker.
RUN <<'EOSH'
set -eux
curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor -o /usr/share/keyrings/packages.microsoft.gpg
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" > /etc/apt/sources.list.d/vscode.list
apt-get update
apt-get install -y --no-install-recommends code
install -d /opt/maker-defaults/vscode/data /opt/maker-defaults/vscode/extensions
for extension in anthropic.claude-code opencodeai.opencode google.gemini-code-assistant qwen-team.qwen-vscode openai.openai; do
  code --no-sandbox --install-extension "$extension" --force \
    --user-data-dir /opt/maker-defaults/vscode/data \
    --extensions-dir /opt/maker-defaults/vscode/extensions || true
done
rm -rf /var/lib/apt/lists/*
EOSH

# MCP oficial de Blender fijado y preparado en la imagen.
ARG BLENDER_MCP_REVISION=dbbf836ad4b1025f14a2b3b504c43903f39e0b04
RUN <<'EOSH'
set -eux
source_dir=/opt/blender-mcp-source
git init "$source_dir"
git -C "$source_dir" remote add origin https://projects.blender.org/lab/blender_mcp.git
git -C "$source_dir" fetch --depth 1 origin "$BLENDER_MCP_REVISION"
git -C "$source_dir" checkout --detach FETCH_HEAD
test "$(git -C "$source_dir" rev-parse HEAD)" = "$BLENDER_MCP_REVISION"
python3 -m venv /opt/blender-mcp-venv
/opt/blender-mcp-venv/bin/pip install --no-cache-dir "$source_dir/mcp"
ln -s /opt/blender-mcp-venv/bin/blender-mcp /usr/local/bin/blender-mcp
blender --command extension build \
  --source-dir "$source_dir/addon/blender_mcp_addon" \
  --output-filepath /opt/blender-mcp-addon.zip
rm -rf "$source_dir/.git"
printf '%s\n' "$BLENDER_MCP_REVISION" > /opt/blender-mcp-revision
EOSH

# AppImage Pool se extrae para conservar la utilidad sin requerir FUSE/SYS_ADMIN.
RUN <<'EOSH'
set -eux
workdir="$(mktemp -d)"
cd "$workdir"
found=""
for url in \
  "https://github.com/prateekmedia/appimagepool/releases/download/${APPIMAGEPOOL_VERSION}/appimagepool-${APPIMAGEPOOL_VERSION}-x86_64.AppImage" \
  "https://github.com/prateekmedia/appimagepool/releases/download/${APPIMAGEPOOL_VERSION}/AppImagePool-${APPIMAGEPOOL_VERSION}-x86_64.AppImage"; do
  if curl -fLsS "$url" -o appimagepool.AppImage; then found="$url"; break; fi
done
test -n "$found"
chmod +x appimagepool.AppImage
./appimagepool.AppImage --appimage-extract >/dev/null
mv squashfs-root /opt/appimagepool
ln -s /opt/appimagepool/AppRun /usr/local/bin/appimagepool
rm -rf "$workdir"
EOSH

RUN <<'EOSH'
set -eux
install -d /usr/share/applications /opt/maker-defaults/Desktop
cat > /usr/share/applications/orcaslicer.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=OrcaSlicer
Comment=Laminador principal para impresion 3D
Exec=/usr/local/bin/orcaslicer %F
Icon=applications-graphics
Categories=Graphics;3DGraphics;Engineering;
Terminal=false
MimeType=model/stl;model/3mf;application/vnd.ms-3mfdocument;
EOF
cat > /usr/share/applications/ultimaker-cura.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=UltiMaker Cura
Comment=Laminador para impresion 3D
Exec=/usr/local/bin/cura %F
Icon=applications-graphics
Categories=Graphics;3DGraphics;Engineering;
Terminal=false
MimeType=model/stl;model/3mf;application/vnd.ms-3mfdocument;
EOF
cat > /usr/share/applications/freecad-appimage.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=FreeCAD
Comment=Modelado parametrico 3D
Exec=/usr/local/bin/freecad %F
Icon=applications-engineering
Categories=Graphics;3DGraphics;Engineering;
Terminal=false
MimeType=application/x-extension-fcstd;model/stl;model/3mf;
EOF
cat > /usr/share/applications/gimp-appimage.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=GIMP
Exec=/usr/local/bin/gimp %U
Icon=gimp
Categories=Graphics;2DGraphics;
Terminal=false
EOF
cat > /usr/share/applications/krita-appimage.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=Krita
Exec=/usr/local/bin/krita %F
Icon=krita
Categories=Graphics;2DGraphics;
Terminal=false
EOF
cat > /usr/share/applications/blender.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=Blender
Exec=/usr/local/bin/blender %F
Icon=blender
Categories=Graphics;3DGraphics;
Terminal=false
EOF
cat > /usr/share/applications/lasergrbl.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=LaserGRBL
Exec=wine /opt/lasergrbl/LaserGRBL-install.exe
Icon=applications-engineering
Categories=Graphics;Engineering;
Terminal=false
EOF
cat > /usr/share/applications/appimagepool.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=AppImage Pool
Exec=/usr/local/bin/appimagepool
Icon=applications-utilities
Categories=Utility;
Terminal=false
EOF
cat > /usr/share/applications/firefox-maker.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=Firefox
Exec=/usr/local/bin/firefox %u
Icon=firefox
Categories=Network;WebBrowser;
Terminal=false
MimeType=text/html;x-scheme-handler/http;x-scheme-handler/https;
EOF

for desktop in \
  firefox-maker.desktop \
  orcaslicer.desktop \
  ultimaker-cura.desktop \
  freecad-appimage.desktop \
  gimp-appimage.desktop \
  krita-appimage.desktop \
  PrusaSlicer.desktop \
  prusa-slicer.desktop \
  openscad.desktop \
  blender.desktop \
  meshlab.desktop \
  librecad.desktop \
  org.inkscape.Inkscape.desktop \
  org.kicad.kicad.desktop \
  org.fritzing.Fritzing.desktop \
  net.launchpad.code.simulide.desktop \
  geany.desktop \
  VisiCut.desktop \
  OpenCode.desktop \
  com.anthropic.Claude.desktop \
  com.microsoft.VSCode.desktop \
  lasergrbl.desktop \
  appimagepool.desktop; do
  if [ -f "/usr/share/applications/$desktop" ]; then
    cp "/usr/share/applications/$desktop" "/opt/maker-defaults/Desktop/$desktop"
  fi
done
chmod 0755 /opt/maker-defaults/Desktop/*.desktop
update-desktop-database /usr/share/applications || true
EOSH

COPY root/ /

RUN chmod 0755 \
      /custom-cont-init.d/10-maker-desktop \
      /custom-services.d/coder-agent

EXPOSE 3000 3001
VOLUME /config
