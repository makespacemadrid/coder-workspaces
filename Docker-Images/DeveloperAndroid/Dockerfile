# Developer Android: toolchain Android sobre DeveloperDesktop (KDE real,
# VS Code, GitHub Desktop, Antigravity, Claude/OpenCode Desktop, AppImage Pool
# ya vienen de la base; aquí solo se añade lo específico de Android).
FROM ghcr.io/makespacemadrid/coder-mks-developer-desktop:latest

LABEL org.opencontainers.image.title="coder-mks-developer-android" \
      org.opencontainers.image.description="Coder Developer Desktop con toolchain Android (SDK/CLI, Studio, Gradle, JetBrains Toolbox)" \
      org.opencontainers.image.source="https://github.com/makespacemadrid/coder-workspaces" \
      org.opencontainers.image.url="ghcr.io/makespacemadrid/coder-mks-developer-android:latest" \
      com.centurylinklabs.watchtower.enable="true" \
      com.centurylinklabs.watchtower.scope="coder-workspaces" \
      com.centurylinklabs.watchtower.lifecycle="rolling"

USER root

ENV DEBIAN_FRONTEND=noninteractive

# Paquetes específicos de Android (la base ya trae KDE, VS Code, Antigravity,
# GitHub Desktop, Claude/OpenCode Desktop, Node24+CLIs IA, Docker Engine)
RUN dpkg --add-architecture i386 && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        openjdk-17-jdk \
        libc6:i386 libstdc++6:i386 libgcc-s1:i386 libz1:i386 libncurses6:i386 \
        libpulse0 \
        adb \
        httpie \
        xmlstarlet \
        scrcpy \
        acl \
        libglu1-mesa \
        qemu-kvm \
    && rm -rf /var/lib/apt/lists/*

# Añadir coder al grupo KVM para aceleración del emulador
RUN usermod -aG kvm coder

# Android SDK commandline tools + componentes principales
ENV ANDROID_HOME=/home/coder/Android/Sdk \
    ANDROID_SDK_ROOT=/home/coder/Android/Sdk \
    ANDROID_EMULATOR_DEFAULT_GPU=swiftshader \
    ANDROID_USER_HOME=/home/coder/.android \
    PATH=$PATH:/home/coder/Android/Sdk/platform-tools:/home/coder/Android/Sdk/cmdline-tools/latest/bin:/home/coder/Android/Sdk/emulator:/opt/gradle/latest/bin

ARG ANDROID_SDK_VERSION=16111833
RUN mkdir -p /home/coder/Android/Sdk/cmdline-tools && \
    curl -fsSL "https://dl.google.com/android/repository/commandlinetools-linux-${ANDROID_SDK_VERSION}_latest.zip" -o /tmp/cmdline-tools.zip && \
    unzip -q /tmp/cmdline-tools.zip -d /home/coder/Android/Sdk/cmdline-tools && \
    mv /home/coder/Android/Sdk/cmdline-tools/cmdline-tools /home/coder/Android/Sdk/cmdline-tools/latest && \
    rm /tmp/cmdline-tools.zip && \
    yes | /home/coder/Android/Sdk/cmdline-tools/latest/bin/sdkmanager --licenses >/dev/null || true && \
    /home/coder/Android/Sdk/cmdline-tools/latest/bin/sdkmanager --update && \
    /home/coder/Android/Sdk/cmdline-tools/latest/bin/sdkmanager \
      "platform-tools" \
      "emulator" && \
    mv /home/coder/Android/Sdk/emulator/emulator /home/coder/Android/Sdk/emulator/emulator.real && \
    { \
      printf '%s\n' '#!/usr/bin/env bash' 'set -e' ''; \
      printf '%s\n' 'default_gpu="${ANDROID_EMULATOR_DEFAULT_GPU:-swiftshader}"'; \
      printf '%s\n' 'for arg in "$@"; do'; \
      printf '%s\n' '  if [ "$arg" = "-gpu" ]; then'; \
      printf '%s\n' '    exec /home/coder/Android/Sdk/emulator/emulator.real "$@"'; \
      printf '%s\n' '  fi'; \
      printf '%s\n' 'done' ''; \
      printf '%s\n' 'exec /home/coder/Android/Sdk/emulator/emulator.real -gpu "$default_gpu" "$@"'; \
    } > /home/coder/Android/Sdk/emulator/emulator && \
    chmod +x /home/coder/Android/Sdk/emulator/emulator && \
    ln -sfn /home/coder/Android/Sdk /opt/android-sdk && \
    chown -R coder:coder /home/coder/Android /home/coder/.android && \
    install -d -o coder -g coder /home/coder/.android

# Android Studio
ARG ANDROID_STUDIO_VERSION=2026.1.4
ARG ANDROID_STUDIO_BUILD=2026.1.4.8
ARG ANDROID_STUDIO_PACKAGE=android-studio-quail4-patch1-linux.tar.gz
RUN curl -fsSL "https://edgedl.me.gvt1.com/android/studio/ide-zips/${ANDROID_STUDIO_BUILD}/${ANDROID_STUDIO_PACKAGE}" -o /tmp/android-studio.tar.gz && \
    tar -xzf /tmp/android-studio.tar.gz -C /opt && \
    rm /tmp/android-studio.tar.gz && \
    chown -R coder:coder /opt/android-studio && \
    ln -sf /opt/android-studio/bin/studio /usr/local/bin/android-studio && \
    ln -sf /opt/android-studio/bin/studio /usr/local/bin/studio

# JetBrains Toolbox (para JetBrains Gateway/IDE remotos)
ARG JETBRAINS_TOOLBOX_VERSION=3.8.1.88030
RUN curl -fsSL "https://download.jetbrains.com/toolbox/jetbrains-toolbox-${JETBRAINS_TOOLBOX_VERSION}.tar.gz" -o /tmp/jetbrains-toolbox.tar.gz && \
    mkdir -p /opt/jetbrains-toolbox && \
    tar -xzf /tmp/jetbrains-toolbox.tar.gz -C /opt/jetbrains-toolbox --strip-components=1 && \
    rm /tmp/jetbrains-toolbox.tar.gz && \
    chown -R coder:coder /opt/jetbrains-toolbox && \
    ln -sf /opt/jetbrains-toolbox/jetbrains-toolbox /usr/local/bin/jetbrains-toolbox

# Acceso directo de escritorio para Android Studio (el resto de apps ya los
# deja listos la base DeveloperDesktop en /etc/skel/Desktop).
RUN install -d /etc/skel/Desktop && \
    cat <<'EOF' >/usr/share/applications/android-studio.desktop
[Desktop Entry]
Name=Android Studio
Comment=Android IDE
Exec=/opt/android-studio/bin/studio
Icon=/opt/android-studio/bin/studio.png
Terminal=false
Type=Application
Categories=Development;IDE;
EOF
RUN chmod +x /usr/share/applications/android-studio.desktop && \
    ln -sf /usr/share/applications/android-studio.desktop /etc/skel/Desktop/android-studio.desktop

# Gradle
ARG GRADLE_VERSION=9.8.0
RUN curl -fsSL "https://services.gradle.org/distributions/gradle-${GRADLE_VERSION}-bin.zip" -o /tmp/gradle.zip && \
    unzip -q /tmp/gradle.zip -d /opt/gradle && \
    ln -sfn "/opt/gradle/gradle-${GRADLE_VERSION}" /opt/gradle/latest && \
    rm /tmp/gradle.zip
