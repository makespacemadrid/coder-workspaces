# Base de escritorio KDE para Coder workspaces, sobre DevTools-Base (Docker
# Engine + Node/CLIs IA ya instalados). La usan Developer/Designer/DeveloperAndroid
# — todo lo común de escritorio vive aquí una sola vez, en vez de triplicado.
FROM ghcr.io/makespacemadrid/coder-mks-devtools-base:latest

LABEL org.opencontainers.image.title="coder-mks-desktop-kde" \
      org.opencontainers.image.description="Base desktop image (KDE Plasma) for Coder workspaces" \
      org.opencontainers.image.source="https://github.com/makespacemadrid/coder-workspaces" \
      org.opencontainers.image.url="ghcr.io/makespacemadrid/coder-mks-desktop-kde:latest"

USER root

ENV DEBIAN_FRONTEND=noninteractive

# Core deps + KDE Plasma desktop + Firefox (mozillateam)
RUN dpkg --add-architecture i386 && \
    apt-get update && \
    apt-get install -y --no-install-recommends software-properties-common && \
    add-apt-repository -y universe && \
    add-apt-repository -y ppa:mozillateam/ppa && \
    printf 'Package: firefox*\nPin: release o=LP-PPA-mozillateam\nPin-Priority: 1001\n' > /etc/apt/preferences.d/mozillateam-firefox && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        sudo \
        tzdata \
        # deps X11 / audio / GL
        dbus-x11 \
        xauth \
        x11-xserver-utils \
        libasound2t64 \
        libgl1 \
        libgl1-mesa-dri \
        mesa-utils \
        pulseaudio \
        pulseaudio-utils \
        alsa-utils \
        # dependencias de KasmVNC (Perl) y de Xvfb/Selkies — compartidas por los
        # dos backends de escritorio que usan esta base
        libdatetime-perl \
        liblist-moreutils-perl \
        libyaml-tiny-perl \
        libhash-merge-simple-perl \
        libxfont2 \
        libfontenc1 \
        ssl-cert \
        # navegadores
        firefox \
        # escritorio KDE Plasma (sesión X11)
        kde-plasma-desktop \
        kwin-x11 \
        plasma-workspace \
        konsole \
        dolphin \
        systemsettings \
        plasma-discover \
        # Soporte SMB en Dolphin (KIO + cliente Samba)
        kio-extras \
        smbclient \
    && rm -rf /var/lib/apt/lists/*

# Vulkan loader + Mesa Vulkan drivers (Vulkan/GL genérico vía Mesa; en NVIDIA
# sin --gpus completo cae a software LLVMpipe, confirmado en vivo — no depender
# de esto para aceleración real en GPU NVIDIA, ver coder_parameter de aceleración
# gráfica en los templates).
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        libvulkan1 \
        mesa-vulkan-drivers \
    && rm -rf /var/lib/apt/lists/*

# Google Chrome (repositorio oficial) — disponible en cualquier escritorio KDE
RUN install -m 0755 -d /etc/apt/keyrings && \
    curl -fsSL https://dl.google.com/linux/linux_signing_key.pub | gpg --dearmor -o /etc/apt/keyrings/google-chrome.gpg && \
    chmod a+r /etc/apt/keyrings/google-chrome.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/google-chrome.gpg] https://dl.google.com/linux/chrome/deb/ stable main" \
      | tee /etc/apt/sources.list.d/google-chrome.list > /dev/null && \
    apt-get update && \
    apt-get install -y --no-install-recommends google-chrome-stable && \
    rm -rf /var/lib/apt/lists/* && \
    if [ -x /opt/google/chrome/google-chrome ]; then \
      mv /usr/bin/google-chrome-stable /usr/bin/google-chrome-stable.real 2>/dev/null || true; \
      printf '%s\n' '#!/bin/sh' \
        'exec /opt/google/chrome/google-chrome --no-sandbox --disable-gpu-sandbox --disable-setuid-sandbox \' \
        '  --use-gl=angle --use-angle=swiftshader --enable-unsafe-swiftshader \' \
        '  --ignore-gpu-blocklist --disable-dev-shm-usage "$@"' \
        > /usr/bin/google-chrome-stable; \
      chmod +x /usr/bin/google-chrome-stable; \
      ln -sf google-chrome-stable /usr/bin/google-chrome 2>/dev/null || true; \
    fi

# KasmVNC (módulo de Coder) y Selkies arrancan KDE como session manager
RUN update-alternatives --set x-session-manager /usr/bin/startplasma-x11

# Desactivar bloqueo/ahorro de pantalla de KDE: en un escritorio remoto sin
# interacción física real (ratón/teclado locales), el detector de inactividad
# de KDE bloquea la sesión igualmente y no hay forma de desbloquearla desde
# Selkies/KasmVNC sin la contraseña del usuario del sistema.
RUN printf '[Daemon]\nTimeout=0\nLockOnResume=false\nLockOnSuspend=false\nAutolock=false\n' > /etc/xdg/kscreenlockerrc

# PulseAudio: null-sink virtual para contenedores sin hardware de audio.
# Pensado originalmente para que KasmVNC capturase audio de aquí. Bajo Selkies
# esto rompe el audio (su propio PulseAudio hereda este default-sink y el
# audio nunca llega al sink que Selkies realmente captura) — ya hay un fix a
# nivel Terraform (coder_script que fuerza el sink "output") mientras KasmVNC
# siga en producción. Retirar este bloque cuando KasmVNC se retire del todo.
RUN mkdir -p /etc/pulse/default.pa.d && \
    printf 'load-module module-null-sink sink_name=vcable sink_properties=device.description="VirtualCable"\nset-default-sink vcable\n' \
    > /etc/pulse/default.pa.d/10-null-sink.pa

# Configuración FUSE para permitir AppImages (allow_other) — ya la fija
# DevTools-Base, pero se repite por si esta imagen se usa como base directa
RUN echo "user_allow_other" > /etc/fuse.conf

# Utilidades NVIDIA (`nvidia-smi`) — cualquier escritorio puede pedir GPU NVIDIA
# vía el coder_parameter de aceleración gráfica, no solo Developer.
RUN set -e; \
    apt-get update; \
    if ! apt-get install -y --no-install-recommends nvidia-utils-580; then \
      if ! apt-get install -y --no-install-recommends nvidia-utils-570; then \
        apt-get install -y --no-install-recommends nvidia-utils-565 || true; \
      fi; \
    fi; \
    rm -rf /var/lib/apt/lists/*

# OpenCode Desktop y Claude Desktop: apps de chat con IA que quiere cualquier
# escritorio (Developer y Designer ya los pedían cada uno por su lado).
ENV ELECTRON_DISABLE_SANDBOX=1 \
    ELECTRON_OZONE_PLATFORM_HINT=auto \
    COWORK_VM_BACKEND=host
ARG OPENCODE_DESKTOP_URL=https://opencode.ai/es/download/stable/linux-x64-deb
RUN set -e; \
    curl -fsSL "$OPENCODE_DESKTOP_URL" -o /tmp/opencode-desktop.deb; \
    apt-get update && \
    apt-get install -y --no-install-recommends gnome-keyring libwebkit2gtk-4.1-0 && \
    apt-get install -y --no-install-recommends /tmp/opencode-desktop.deb; \
    rm -rf /var/lib/apt/lists/* /tmp/opencode-desktop.deb; \
    if [ -x /opt/OpenCode/ai.opencode.desktop ]; then \
      mv /opt/OpenCode/ai.opencode.desktop /opt/OpenCode/ai.opencode.desktop.real; \
      printf '%s\n' '#!/bin/sh' \
        'exec /opt/OpenCode/ai.opencode.desktop.real --no-sandbox --disable-gpu-sandbox --disable-setuid-sandbox --disable-seccomp-filter-sandbox --no-zygote --disable-gpu "$@"' \
        > /opt/OpenCode/ai.opencode.desktop; \
      chmod +x /opt/OpenCode/ai.opencode.desktop; \
    fi; \
    if [ -f /usr/share/applications/ai.opencode.desktop.desktop ]; then \
      ln -sf /usr/share/applications/ai.opencode.desktop.desktop /usr/share/applications/OpenCode.desktop; \
    fi

# Claude Desktop desde el repo APT oficial de Anthropic. El fallo no es fatal
# para no romper el build si el repo no está disponible.
RUN set -e; \
    if curl -fsSLo /usr/share/keyrings/claude-desktop-archive-keyring.asc https://downloads.claude.ai/claude-desktop/key.asc; then \
      echo "deb [arch=amd64,arm64 signed-by=/usr/share/keyrings/claude-desktop-archive-keyring.asc] https://downloads.claude.ai/claude-desktop/apt/stable stable main" \
        > /etc/apt/sources.list.d/claude-desktop.list; \
      if ! apt-get update || ! apt-get install -y --no-install-recommends claude-desktop; then \
        echo "WARN: no se pudo instalar Claude Desktop desde el repo oficial; se continua sin esa app" >&2; \
      fi; \
    else \
      echo "WARN: no se pudo descargar la key de Claude Desktop; se continua sin esa app" >&2; \
    fi; \
    rm -rf /var/lib/apt/lists/*
