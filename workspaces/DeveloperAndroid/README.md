---
display_name: Developer Android
description: "Workspace KDE con toolchain Android (SDK/CLI), Node 24 y VS Code"
icon: icon.svg
maintainer_github: makespacemadrid
tags: [android, mobile, kde, workspace, ocabra]
---

# Developer Android

Workspace gráfico KDE real vía Selkies (streaming WebRTC) con toolchain Android preinstalado. Usa la imagen `ghcr.io/makespacemadrid/coder-mks-developer-android:latest`.

## Qué incluye
- Android SDK CLI en `/home/coder/Android/Sdk` con `platform-tools`, emulator y `cmdline-tools;latest` (instala tus propias plataformas/ build-tools según el proyecto).
- Android Studio Quail 4 Patch 1 (2026.1.4), Android command-line tools 23.0 y Gradle 9.8.0.
- Java 17, Node.js 24 (npm/pnpm/yarn), git/git-lfs y utilidades de desarrollo.
- VS Code listo para personalizar tus extensiones (sin bundle preinstalado) y soporte C/C++ vía paquetes base.
- JetBrains Toolbox + módulo JetBrains de Coder para lanzar IntelliJ IDEA remoto (instala el plugin Android) vía JetBrains Gateway/Coder Desktop.
- Google Chrome, Firefox y OpenCode Desktop preinstalados.
- Módulos Coder: Selkies (KDE), code-server, Filebrowser, OpenCode, git-config, tmux, JetBrains.
- Autoprovisiona una key de IA Ocabra (30 días) por defecto; configurable en `[AI] Clave Ocabra`.
- Antigravity auto-updater (`antigravity`) preinstalado.
- Docker Engine interno (DinD) y limpieza automática semanal configurable en `[Maintenance] Limpieza automática de Docker`.
- Si existe `$TF_VAR_users_storage/_provisioning/desktop/wallpapers`, se monta de solo lectura y aplica el fondo de escritorio compartido en el primer arranque; no sobrescribe un fondo que ya hayas cambiado.

## Creación rápida en Coder
- [Compute] Aceleración gráfica: `Software` (CPU) o `GPU NVIDIA` (NVENC/CUDA).
- [Storage] Persistencia: `Ninguna` (volumen Docker), `Home completo` o `Solo ~/Projects` en el host.
- [Network] Exponer puertos al host: usa el rango de puertos para publicar servicios.
- [Maintenance] Limpieza automática de Docker: activa por defecto; no elimina volúmenes ni contenedores y se puede desactivar.
- [AI] Clave Ocabra: auto-aprovisionar una key nueva (por defecto) o usar la tuya.
- [AI] Provisionar API key FreeAPI automáticamente: activo por defecto.

## Utilidades extra
- Android: `adb` y `scrcpy`.
- CLI: `httpie`, `yq`, `xmlstarlet`, `sqlite3`.

## Notas
- Escritorio KDE real vía Selkies; VS Code (web y desktop) listo para configurar a tu gusto.
- El SDK Android canónico del workspace es `/home/coder/Android/Sdk`; `/opt/android-sdk` queda como compatibilidad para tooling heredado.
- El emulador Android usa `-gpu swiftshader` por defecto para evitar cierres con `-gpu host` en escritorios remotos; puedes sobrescribirlo con `ANDROID_EMULATOR_DEFAULT_GPU` o pasando `-gpu` manualmente.
- Bloqueo de pantalla/ahorro de energía deshabilitado para no interrumpir builds largos.
- Botones JetBrains disponibles en el dashboard (IntelliJ IDEA remoto); instala el plugin de Android para emular Android Studio y requiere JetBrains Gateway/Coder Desktop.
- Home persistente en `/home/coder` (volumen o bind mount según parámetros); labels de Watchtower habilitadas.
- Script `gen_ocabra_key` disponible en el workspace para regenerar/aplicar una nueva key de IA.
