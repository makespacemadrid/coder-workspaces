# Android sobre el mismo escritorio KDE/Selkies validado en MakerSelkies.
# Heredar la imagen Maker comparte sus capas pesadas y mantiene una unica
# integracion de Selkies, NVIDIA, audio y agente Coder.
FROM ghcr.io/makespacemadrid/coder-mks-design-selkies:latest

LABEL org.opencontainers.image.title="coder-mks-developer-android-selkies" \
      org.opencontainers.image.description="Escritorio Selkies acelerado con Android Studio, SDK, emulador y toolchain movil" \
      org.opencontainers.image.source="https://github.com/makespacemadrid/coder-workspaces" \
      org.opencontainers.image.url="ghcr.io/makespacemadrid/coder-mks-developer-android-selkies:latest" \
      com.centurylinklabs.watchtower.enable="true" \
      com.centurylinklabs.watchtower.scope="coder-workspaces" \
      com.centurylinklabs.watchtower.lifecycle="rolling"

ARG DEBIAN_FRONTEND=noninteractive
ARG ANDROID_SDK_VERSION=16111833
ARG ANDROID_STUDIO_VERSION=2026.1.4
ARG ANDROID_STUDIO_BUILD=2026.1.4.8
ARG ANDROID_STUDIO_PACKAGE=android-studio-quail4-patch1-linux.tar.gz
ARG JETBRAINS_TOOLBOX_VERSION=3.8.1.88030
ARG GRADLE_VERSION=9.8.0

ENV TITLE="MakeSpace Android (Selkies)" \
    ANDROID_HOME=/opt/android-sdk \
    ANDROID_SDK_ROOT=/opt/android-sdk \
    ANDROID_USER_HOME=/config/.android \
    ANDROID_EMULATOR_DEFAULT_GPU=swiftshader \
    PATH=$PATH:/opt/android-sdk/platform-tools:/opt/android-sdk/cmdline-tools/latest/bin:/opt/android-sdk/emulator:/opt/gradle/latest/bin

RUN <<'EOSH'
set -eux
apt-get update
apt-get install -y --no-install-recommends \
  acl adb direnv dnsutils fzf git-lfs htop httpie libglu1-mesa libpulse0 \
  lsof net-tools openjdk-17-jdk qemu-system-x86 ripgrep scrcpy sqlite3 tmux \
  xmlstarlet yq
rm -rf /var/lib/apt/lists/*
EOSH

# Herramientas de repositorio/navegador usadas por el workspace Android actual.
RUN <<'EOSH'
set -eux
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | gpg --dearmor -o /etc/apt/keyrings/githubcli-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" > /etc/apt/sources.list.d/github-cli.list
curl -fsSL https://dl.google.com/linux/linux_signing_key.pub | gpg --dearmor -o /etc/apt/keyrings/google-chrome.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/google-chrome.gpg] https://dl.google.com/linux/chrome/deb/ stable main" > /etc/apt/sources.list.d/google-chrome.list
curl -fsSL https://us-central1-apt.pkg.dev/doc/repo-signing-key.gpg | gpg --dearmor -o /etc/apt/keyrings/antigravity-repo-key.gpg
echo "deb [signed-by=/etc/apt/keyrings/antigravity-repo-key.gpg] https://us-central1-apt.pkg.dev/projects/antigravity-auto-updater-dev/ antigravity-debian main" > /etc/apt/sources.list.d/antigravity.list
chmod a+r /etc/apt/keyrings/*.gpg
apt-get update
apt-get install -y --no-install-recommends antigravity gh google-chrome-stable
npm install -g --omit=dev --no-update-notifier --no-fund \
  pnpm yarn @google/gemini-cli @continuedev/cli @qwen-code/qwen-code
npm cache clean --force
rm -rf /var/lib/apt/lists/*
EOSH

# SDK y emulador. El SDK es global/inmutable; AVD y preferencias viven en /config.
RUN <<'EOSH'
set -eux
install -d /opt/android-sdk/cmdline-tools
curl -fsSL "https://dl.google.com/android/repository/commandlinetools-linux-${ANDROID_SDK_VERSION}_latest.zip" -o /tmp/cmdline-tools.zip
unzip -q /tmp/cmdline-tools.zip -d /opt/android-sdk/cmdline-tools
mv /opt/android-sdk/cmdline-tools/cmdline-tools /opt/android-sdk/cmdline-tools/latest
rm /tmp/cmdline-tools.zip
yes | /opt/android-sdk/cmdline-tools/latest/bin/sdkmanager --licenses >/dev/null || true
/opt/android-sdk/cmdline-tools/latest/bin/sdkmanager --update
/opt/android-sdk/cmdline-tools/latest/bin/sdkmanager "platform-tools" "emulator"
mv /opt/android-sdk/emulator/emulator /opt/android-sdk/emulator/emulator.real
cat > /opt/android-sdk/emulator/emulator <<'EOF'
#!/usr/bin/env bash
set -e
default_gpu="${ANDROID_EMULATOR_DEFAULT_GPU:-swiftshader}"
for arg in "$@"; do
  if [ "$arg" = "-gpu" ]; then
    exec /opt/android-sdk/emulator/emulator.real "$@"
  fi
done
exec /opt/android-sdk/emulator/emulator.real -gpu "$default_gpu" "$@"
EOF
chmod +x /opt/android-sdk/emulator/emulator
EOSH

RUN <<'EOSH'
set -eux
curl -fsSL "https://edgedl.me.gvt1.com/android/studio/ide-zips/${ANDROID_STUDIO_BUILD}/${ANDROID_STUDIO_PACKAGE}" -o /tmp/android-studio.tar.gz
tar -xzf /tmp/android-studio.tar.gz -C /opt
rm /tmp/android-studio.tar.gz
ln -s /opt/android-studio/bin/studio /usr/local/bin/android-studio
ln -s /opt/android-studio/bin/studio /usr/local/bin/studio

curl -fsSL "https://download.jetbrains.com/toolbox/jetbrains-toolbox-${JETBRAINS_TOOLBOX_VERSION}.tar.gz" -o /tmp/jetbrains-toolbox.tar.gz
install -d /opt/jetbrains-toolbox
tar -xzf /tmp/jetbrains-toolbox.tar.gz -C /opt/jetbrains-toolbox --strip-components=1
rm /tmp/jetbrains-toolbox.tar.gz
ln -s /opt/jetbrains-toolbox/jetbrains-toolbox /usr/local/bin/jetbrains-toolbox

curl -fsSL "https://services.gradle.org/distributions/gradle-${GRADLE_VERSION}-bin.zip" -o /tmp/gradle.zip
unzip -q /tmp/gradle.zip -d /opt/gradle
ln -s "/opt/gradle/gradle-${GRADLE_VERSION}" /opt/gradle/latest
rm /tmp/gradle.zip
EOSH

RUN <<'EOSH'
set -eux
install -d /opt/android-defaults/Desktop
cat > /usr/share/applications/android-studio.desktop <<'EOF'
[Desktop Entry]
Name=Android Studio
Comment=Android IDE
Exec=/opt/android-studio/bin/studio
Icon=/opt/android-studio/bin/studio.png
Terminal=false
Type=Application
Categories=Development;IDE;
EOF
for app in android-studio.desktop code.desktop OpenCode.desktop firefox.desktop google-chrome.desktop; do
  if [ -f "/usr/share/applications/$app" ]; then
    cp "/usr/share/applications/$app" "/opt/android-defaults/Desktop/$app"
  fi
done
chmod 0755 /opt/android-defaults/Desktop/*.desktop
update-desktop-database /usr/share/applications || true
EOSH

COPY root/ /
RUN chmod 0755 /custom-cont-init.d/20-android-desktop
