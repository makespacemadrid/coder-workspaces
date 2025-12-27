---
display_name: Developer Android
description: "Workspace KDE con toolchain Android (SDK/CLI), Node 20 y VS Code"
icon: icon.svg
maintainer_github: makespacemadrid
tags: [android, mobile, kde, workspace, makespace]
---

# Developer Android

Workspace gráfico KDE/KasmVNC con toolchain Android preinstalado. Usa la imagen `ghcr.io/makespacemadrid/coder-mks-developer-android:latest`.

## Qué incluye
- Android SDK CLI con `platform-tools`, emulator y `cmdline-tools;latest` (instala tus propias plataformas/ build-tools según el proyecto).
- Java 17, Node.js 20 (npm/pnpm/yarn), git/git-lfs y utilidades de desarrollo.
- VS Code listo para personalizar tus extensiones (sin bundle preinstalado) y soporte C/C++ vía paquetes base.
- JetBrains Toolbox 3.1 + módulo JetBrains de Coder para lanzar IntelliJ IDEA remoto (instala el plugin Android) vía JetBrains Gateway/Coder Desktop.
- Módulos Coder: KasmVNC (KDE), code-server, Filebrowser, OpenCode, git-config, tmux.
- Autoprovisiona una key de IA MakeSpace (30 días) si dejas activa la casilla `[AI/OpenCode] Provisionar API key MakeSpace automáticamente` y el endpoint está configurado por entorno.

## Creación rápida en Coder
- `GPU`: viene activada por defecto; desactívala si no la necesitas.
- `Persistir home en el host`: monta `/home/coder` en `TF_VAR_users_storage/<usuario>/<workspace>`.
- `Persistir solo ~/Projects`: monta `/home/coder/Projects` en `TF_VAR_users_storage/<usuario>/<workspace>/Projects`.
- `Montar ruta host en ~/host`: monta una ruta del host en `/home/coder/host`.
- `Especificar UID para montar la ruta host`: UID para ejecutar el contenedor cuando montas `/home/coder/host` (por defecto 1000).
- `Repositorio Git`: clona en `~/Projects` al primer arranque.
- `OpenCode`: deja activa la casilla `[AI/OpenCode] Provisionar API key MakeSpace automáticamente` para generar una key MakeSpace de 30 días; requiere `TF_VAR_opencode_default_base_url` y `TF_VAR_mks_key_endpoint`.

## Utilidades extra
- Android: `adb` y `scrcpy`.
- CLI: `httpie`, `yq`, `xmlstarlet`, `sqlite3`.

## Notas
- Escritorio KDE vía KasmVNC; VS Code (web y desktop) listo para configurar a tu gusto.
- Bloqueo de pantalla/ahorro de energía deshabilitado para no interrumpir builds largos.
- Botones JetBrains disponibles en el dashboard (IntelliJ IDEA remoto); instala el plugin de Android para emular Android Studio y requiere JetBrains Gateway/Coder Desktop.
- Home persistente en `/home/coder` (volumen o bind mount según parámetros); labels de Watchtower habilitadas.
- Script `gen_mks_litellm_key` disponible en el workspace para regenerar/aplicar una nueva key de IA.
