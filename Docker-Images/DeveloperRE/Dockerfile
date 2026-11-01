# Developer + toolchain de ingeniería inversa para trabajar con rea
# (https://github.com/morluto/rea). Solo incluye motores/herramientas
# GRATUITAS y de código abierto.
#
# Explícitamente NO instalados por requerir licencia comercial (o licencia
# sin confirmar como libre) — tráete tu propia licencia si los quieres:
#   - IDA Pro / Hex-Rays (comercial)
#   - Hopper (comercial; su demo es de tiempo/función limitada, no es gratis)
#   - JEB (comercial)
#   - Kuna (licencia no confirmada como libre)
FROM ghcr.io/makespacemadrid/coder-mks-developer:latest

LABEL org.opencontainers.image.title="coder-mks-developer-re" \
      org.opencontainers.image.description="Coder Developer extendido con toolchain de ingenieria inversa gratuita (Ghidra, JADX, apktool, GDB+pwndbg, binwalk, unblob, pwntools, mitmproxy, tshark, sigrok, WABT, rizin) para usar con rea" \
      org.opencontainers.image.source="https://github.com/makespacemadrid/coder-workspaces" \
      org.opencontainers.image.url="ghcr.io/makespacemadrid/coder-mks-developer-re:latest" \
      com.centurylinklabs.watchtower.enable="true" \
      com.centurylinklabs.watchtower.scope="coder-workspaces" \
      com.centurylinklabs.watchtower.lifecycle="rolling"

USER root

ENV DEBIAN_FRONTEND=noninteractive

# --- Paquetes de sistema ---------------------------------------------------
# tshark pregunta en instalación si los no-root pueden capturar paquetes;
# lo preseedeamos a "sí" y añadimos al usuario coder al grupo wireshark.
RUN echo 'wireshark-common wireshark-common/install-setuid boolean true' | debconf-set-selections && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        openjdk-21-jdk-headless \
        gdb \
        android-tools-adb \
        tshark \
        wireshark-common \
        sigrok-cli \
        wabt \
        binutils \
    && usermod -aG wireshark coder \
    && rm -rf /var/lib/apt/lists/*

# rizin no esta en los repos de Ubuntu Noble; usamos el build estatico oficial.
ARG RIZIN_VERSION=0.9.1
RUN set -e; \
    curl -fsSL "https://github.com/rizinorg/rizin/releases/download/v${RIZIN_VERSION}/rizin-v${RIZIN_VERSION}-static-x86_64.tar.xz" -o /tmp/rizin.tar.xz; \
    mkdir -p /opt/rizin; \
    tar -xJf /tmp/rizin.tar.xz -C /opt/rizin; \
    rm -f /tmp/rizin.tar.xz; \
    for bin in /opt/rizin/bin/*; do ln -sf "$bin" "/usr/local/bin/$(basename "$bin")"; done

# --- Ghidra (descompilador nativo, NSA, gratuito) ---------------------------
ARG GHIDRA_VERSION=12.2
ARG GHIDRA_BUILD_DATE=20261016
ARG GHIDRA_URL="https://github.com/NationalSecurityAgency/ghidra/releases/download/Ghidra_${GHIDRA_VERSION}_build/ghidra_${GHIDRA_VERSION}_PUBLIC_${GHIDRA_BUILD_DATE}.zip"
RUN set -e; \
    curl -fsSL "$GHIDRA_URL" -o /tmp/ghidra.zip; \
    unzip -q /tmp/ghidra.zip -d /opt; \
    mv /opt/ghidra_*_PUBLIC /opt/ghidra; \
    rm -f /tmp/ghidra.zip; \
    ln -sf /opt/ghidra/support/analyzeHeadless /usr/local/bin/analyzeHeadless
ENV GHIDRA_INSTALL_DIR=/opt/ghidra

# --- JADX (descompilador Android, gratuito) ---------------------------------
ARG JADX_VERSION=1.5.6
RUN set -e; \
    curl -fsSL "https://github.com/skylot/jadx/releases/download/v${JADX_VERSION}/jadx-${JADX_VERSION}.zip" -o /tmp/jadx.zip; \
    unzip -q /tmp/jadx.zip -d /opt/jadx; \
    rm -f /tmp/jadx.zip; \
    ln -sf /opt/jadx/bin/jadx /usr/local/bin/jadx; \
    ln -sf /opt/jadx/bin/jadx-gui /usr/local/bin/jadx-gui

# --- Apktool (recursos/resources de APKs, gratuito) -------------------------
ARG APKTOOL_VERSION=3.0.3
RUN set -e; \
    curl -fsSL "https://raw.githubusercontent.com/iBotPeaches/Apktool/master/scripts/linux/apktool" -o /usr/local/bin/apktool; \
    curl -fsSL "https://github.com/iBotPeaches/Apktool/releases/download/v${APKTOOL_VERSION}/apktool_${APKTOOL_VERSION}.jar" -o /usr/local/bin/apktool.jar; \
    chmod +x /usr/local/bin/apktool

# --- pwndbg (GDB con pwndbg integrado, gratuito) ----------------------------
# Instalador oficial: deja /usr/local/bin/pwndbg a nivel de sistema, sin
# tocar ~/.gdbinit por usuario (evita el método legacy setup.sh).
RUN curl --proto '=https' --tlsv1.2 -LsSf 'https://install.pwndbg.re' | sh -s -- -t pwndbg-gdb

# --- CLIs Python aisladas via pipx (mismo patron que el resto de Developer) -
RUN su - coder -c '\
    set -e; \
    export PATH="/opt/pipx/bin:$PATH"; \
    pipx install pwntools; \
    pipx install binwalk; \
    pipx install unblob; \
    pipx install mitmproxy \
    '

USER root
