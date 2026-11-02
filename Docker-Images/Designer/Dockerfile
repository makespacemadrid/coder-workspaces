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

# Paquetes adicionales de diseño (la base ya incluye KDE, Firefox, Chrome, Node+CLIs
# IA, Docker Engine, Perl/VNC, vcable, Vulkan/Mesa y utilidades de consola)
RUN dpkg --add-architecture i386 && \
    apt-get update && \
    apt-get install -y --no-install-recommends software-properties-common && \
    add-apt-repository -y ppa:freecad-maintainers/freecad-stable && \
    add-apt-repository -y ppa:kicad/kicad-10.0-releases && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
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
        uidmap \
        simulide \
        wine64 \
        wine32 \
        winbind \
        geany \
    && rm -rf /var/lib/apt/lists/*

# KiCad autorouter: Freerouting requiere Java 21 (el sistema trae 11). El jar se
# hornea en /opt; el template de Maker lo enlaza a ~/.kicad-mcp/freerouting.jar,
# que es donde lo busca el MCP (check_freerouting/autoroute).
ARG FREEROUTING_VERSION=2.4.1
RUN apt-get update && \
    apt-get install -y --no-install-recommends openjdk-21-jre-headless && \
    update-alternatives --set java /usr/lib/jvm/java-21-openjdk-amd64/bin/java && \
    mkdir -p /opt/freerouting && \
    curl -fsSL -o /opt/freerouting/freerouting.jar \
      "https://github.com/freerouting/freerouting/releases/download/v${FREEROUTING_VERSION}/freerouting-${FREEROUTING_VERSION}.jar" && \
    rm -rf /var/lib/apt/lists/*

# OrcaSlicer (AppImage), LaserGRBL (Wine) y VisiCut (.deb). OpenCode Desktop y
# Claude Desktop ya vienen de la base (Desktop-KDE), que las comparte con Developer.
RUN <<'EOSH'
set -e
ORCA_VERSION="2.4.2"
# OrcaSlicer publica AppImage para Ubuntu 24.04; libwebkit2gtk-4.1 se instala arriba.
ORCA_URLS=" \
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
apt-get install -y --no-install-recommends libwebkit2gtk-4.1-0
apt-get install -y --no-install-recommends /tmp/visicut.deb
rm /tmp/visicut.deb
rm -rf /var/lib/apt/lists/*
EOSH

# Blender 5.2 LTS (binario oficial; requerido por el MCP oficial de Blender Lab)
ARG BLENDER_VERSION=5.2.2
RUN <<'EOSH'
set -e
BLENDER_DIR="/opt/blender"
BLENDER_PKG="blender-${BLENDER_VERSION}-linux-x64"
# Directorio de release = serie mayor.menor (p.ej. 4.5.11 -> Blender4.5)
BLENDER_SERIES="$(echo "${BLENDER_VERSION}" | cut -d. -f1-2)"
BLENDER_URL="https://download.blender.org/release/Blender${BLENDER_SERIES}/${BLENDER_PKG}.tar.xz"
mkdir -p /opt
curl -fL "${BLENDER_URL}" -o /tmp/blender.tar.xz
tar -xJf /tmp/blender.tar.xz -C /opt
rm -f /tmp/blender.tar.xz
rm -rf "${BLENDER_DIR}"
mv "/opt/${BLENDER_PKG}" "${BLENDER_DIR}"
ln -sf "${BLENDER_DIR}/blender" /usr/local/bin/blender
ln -sf "${BLENDER_DIR}/blender-thumbnailer" /usr/local/bin/blender-thumbnailer || true
install -D -m 0644 "${BLENDER_DIR}/blender.svg" /usr/share/icons/hicolor/scalable/apps/blender.svg
cat > /usr/share/applications/blender.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=Blender
Exec=blender
Icon=blender
Categories=Graphics;3DGraphics;
Terminal=false
EOF
EOSH

# Versiones oficiales modernas para aplicaciones que Ubuntu Noble mantiene muy atrasadas.
# Se conservan los paquetes APT como dependencias/fallback y se priorizan estos AppImages.
ARG FREECAD_VERSION=1.1.3
ARG GIMP_VERSION=3.2.6
ARG KRITA_VERSION=5.3.4
RUN <<'EOSH'
set -e
install_appimage() {
  name="$1"
  url="$2"
  destination="/opt/appimages/${name}.AppImage"
  mkdir -p /opt/appimages
  curl -fL "$url" -o "$destination"
  chmod +x "$destination"
  ln -sfn "$destination" "/usr/local/bin/$name"
}
install_appimage freecad "https://github.com/FreeCAD/FreeCAD/releases/download/${FREECAD_VERSION}/FreeCAD_${FREECAD_VERSION}-Linux-x86_64-py311.AppImage"
install_appimage gimp "https://download.gimp.org/gimp/v3.2/linux/GIMP-${GIMP_VERSION}-x86_64.AppImage"
install_appimage krita "https://download.kde.org/stable/krita/${KRITA_VERSION}/krita-${KRITA_VERSION}-x86_64.AppImage"

cat > /usr/share/applications/org.gimp.GIMP.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=GIMP
Exec=gimp %U
Icon=gimp
Categories=Graphics;2DGraphics;
Terminal=false
EOF
EOSH

# MCP oficial mantenido por Blender Lab, fijado a una revisión reproducible.
# Se hornean tanto el servidor Python como el paquete del add-on para no depender
# de Git/PyPI durante el arranque de cada workspace.
ARG BLENDER_MCP_REVISION=dbbf836ad4b1025f14a2b3b504c43903f39e0b04
RUN <<'EOSH'
set -e
source_dir=/opt/blender-mcp-source
git init "$source_dir"
git -C "$source_dir" remote add origin https://projects.blender.org/lab/blender_mcp.git
git -C "$source_dir" fetch --depth 1 origin "$BLENDER_MCP_REVISION"
git -C "$source_dir" checkout --detach FETCH_HEAD
test "$(git -C "$source_dir" rev-parse HEAD)" = "$BLENDER_MCP_REVISION"
python3 -m venv /opt/blender-mcp-venv
/opt/blender-mcp-venv/bin/pip install --no-cache-dir "$source_dir/mcp"
ln -sfn /opt/blender-mcp-venv/bin/blender-mcp /usr/local/bin/blender-mcp
blender --command extension build \
  --source-dir "$source_dir/addon/blender_mcp_addon" \
  --output-filepath /opt/blender-mcp-addon.zip
rm -rf "$source_dir/.git"
printf '%s\n' "$BLENDER_MCP_REVISION" > /opt/blender-mcp-revision
EOSH

# Configuración FUSE para permitir AppImages (allow_other)
RUN echo "user_allow_other" > /etc/fuse.conf

# Locales
RUN locale-gen es_ES.UTF-8 en_US.UTF-8 && \
    update-locale LANG=es_ES.UTF-8

# `startkde`/el alternative de x-session-manager ya los fija Desktop-KDE (KDE
# real está instalado ahí, a diferencia del viejo caso Developer/MATE).

ENV LANG=es_ES.UTF-8 \
    LC_ALL=es_ES.UTF-8

# uv (Astral) para MCPs en Python. El CLI de OpenCode NO se hornea aquí: el
# módulo Terraform `opencode` instala su propia copia en ~/.opencode/bin y la
# antepone al PATH en cada arranque, dejando muerto cualquier binario horneado
# en la imagen (confirmado en la auditoría) — MakerSelkies ya no lo hornea.
RUN curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR=/usr/local/bin UV_NO_MODIFY_PATH=1 sh


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
    for f in firefox.desktop org.freecadweb.FreeCAD.desktop org.inkscape.Inkscape.desktop gimp.desktop org.kde.krita.desktop org.kicad.kicad.desktop openscad.desktop PrusaSlicer.desktop librecad.desktop meshlab.desktop org.fritzing.Fritzing.desktop net.launchpad.code.simulide.desktop geany.desktop VisiCut.desktop orcaslicer.desktop appimagepool.desktop OpenCode.desktop com.anthropic.Claude.desktop; do \
      src="/usr/share/applications/$f"; \
      if [ -f "$src" ]; then ln -sf "$src" "/etc/skel/Desktop/$f"; fi; \
    done && \
    chmod +x /etc/skel/Desktop/*.desktop || true

# Qt WebEngine sandbox workaround (FreeCAD/QtWebEngine apps inside containers)
ENV QTWEBENGINE_DISABLE_SANDBOX=1 \
    QTWEBENGINE_CHROMIUM_FLAGS="--no-sandbox"
