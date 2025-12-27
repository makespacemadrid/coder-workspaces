---
display_name: AdvancedHostDANGER
description: "DANGER DANGER: acceso Docker host + network host. Usa Developer si no necesitas esto."
icon: icon.svg
maintainer_github: makespacemadrid
tags: [docker, workspace, host, danger, makespace]
---

# Developer Advanced Host

**DANGER DANGER**: acceso directo al Docker del host y `network_host`. Úsalo solo si sabes lo que haces.

## Qué incluye
- Escritorio XFCE vía KasmVNC, code-server opcional y shell con tooling dev.
- Docker del host (`/var/run/docker.sock`), `network_mode = host`, GPUs del host.
- Apps desktop: VS Code, GitHub Desktop, Claude Desktop, Firefox, Geany, AppImage Pool.
- Stack dev: Docker Engine/Compose, Node.js 20, CLIs de IA (Codex, Claude, Gemini, Continue, Qwen), git/gh, pulseaudio/ALSA.
- Python listo para venvs (`python3-venv`) + venv base en `~/.venvs/base`.
- Accesos directos precreados en el escritorio y módulos KasmVNC, Filebrowser, OpenCode. RDP es solo para workspaces Windows según [la guía de Coder](https://coder.com/docs/user-guides/workspace-access/remote-desktops); esta imagen Linux usa KasmVNC.

## Uso recomendado
- Pruebas que requieran Docker/Network del host, diagnósticos de red, acceso a GPUs del host.
- Si no necesitas tocar el host, usa el template `Developer` (DinD) para más aislamiento.

## Creación rápida en Coder
- Usa esta plantilla solo cuando necesites acceso directo al host.
- `Persistir home en el host`: monta `/home/coder` en `TF_VAR_users_storage/<usuario>/<workspace>`.
- `Persistir solo ~/Projects`: monta `/home/coder/Projects` en `TF_VAR_users_storage/<usuario>/<workspace>/Projects`.
- `Montar ruta host en ~/host`: monta una ruta del host en `/home/coder/host`.
- `Especificar UID para montar la ruta host`: UID para ejecutar el contenedor cuando montas `/home/coder/host` (por defecto 1000).
- `Repositorio Git`: clona en `~/Projects` al primer arranque.
- `OpenCode`: si dejas URL/API key vacíos y hay endpoint por entorno, se autoprovisiona; requiere `TF_VAR_opencode_default_base_url` y `TF_VAR_mks_key_endpoint`.

## Parámetros
- `Persistir home en el host`: monta `/home/coder` en `TF_VAR_users_storage/<usuario>/<workspace>`.
- `Persistir solo ~/Projects`: monta `/home/coder/Projects` en `TF_VAR_users_storage/<usuario>/<workspace>/Projects`.
- `Montar ruta host en ~/host`: monta una ruta del host en `/home/coder/host`.
- `Especificar UID para montar la ruta host`: UID para ejecutar el contenedor cuando montas `/home/coder/host` (por defecto 1000).
- `Repositorio Git (opcional)`: URL para clonar en `~/Projects/<nombre-del-repo>` en el primer arranque del workspace.
- `OpenCode provider/API key (opcional)`: configura proveedor OpenAI-compatible al arrancar.

## Notas
- El contenedor lleva labels `com.centurylinklabs.watchtower.*` para que Watchtower pueda actualizarlo si activas `--label-enable`.
- Home persistente en `/home/coder` (volumen o bind mount según parámetros).
