---
display_name: Developer
description: "Workspace de desarrollo general con Docker in Docker y GPU opcional (autoprovisiona key MakeSpace de IA por defecto, configurable)"
icon: icon.svg
maintainer_github: makespacemadrid
tags: [docker, dind, gpu, workspace, makespace]
---

# Developer (Docker in Docker)

Workspace de desarrollo general, con **Docker in Docker (DinD)**, escritorio XFCE/KasmVNC y aislamiento del host. Usa la imagen `ghcr.io/makespacemadrid/coder-mks-developer:latest`.

## Para qué sirve
- Entornos de desarrollo aislados sin tocar el Docker del host.
- Proyectos que necesitan GPU opcional y mapeo de puertos a host.
- Sesiones gráficas ligeras (KasmVNC) con herramientas dev y CLIs de IA.

## Qué incluye
- Docker Engine y docker-compose-plugin internos (DinD, no se usa el socket del host).
- Escritorio XFCE/KasmVNC, code-server y Filebrowser. RDP solo aplica a workspaces Windows según [la guía de Coder](https://coder.com/docs/user-guides/workspace-access/remote-desktops).
- Apps desktop: VS Code, GitHub Desktop, Claude Desktop, Google Chrome, Firefox, Geany, AppImage Pool.
- Node.js 20, CLIs de IA (OpenAI/Codex, Claude, Gemini, Continue, Qwen), git/gh y audio (PulseAudio/ALSA).
- Utilidades CLI extra: `yq`, `sqlite3`.
- Python con `python3-venv` y venv base en `~/.venvs/base`.
- Persistencia en `/home/coder` (volumen o bind mount) y `/var/lib/docker`.
- Antigravity auto-updater (`antigravity`) preinstalado.

## Creación rápida en Coder
- Si es tu primera vez, probablemente no necesitas tocar nada: baja al final y pulsa `Create workspace`.
- Qué es: workspace con Docker DinD, code-server/VS Code y tooling de IA listo para usar.
- **Identidad**: deja vacío “Full Name for Git config” para usar el nombre de tu usuario Coder.
- [Compute] GPU (opcional): activa `Habilitar GPUs` si lo necesitas.
- [Network] Exponer puertos al host: usa `Exponer puertos al host` + `Puerto inicial/final` para publicar servicios.
- [Storage] Persistir home en el host: monta `/home/coder` en `TF_VAR_users_storage/<usuario>/<workspace>`.
- [Storage] Persistir solo ~/Projects: monta `/home/coder/Projects` en `TF_VAR_users_storage/<usuario>/<workspace>/Projects`.
- [Storage] Montar ruta host en ~/host: monta una ruta del host en `/home/coder/host`.
- [Storage] Especificar UID para montar la ruta host: UID para ejecutar el contenedor cuando montas `/home/coder/host` (por defecto 1000).
- [Storage] Docker data persistente: `/var/lib/docker` se guarda en un volumen interno automático.
- [Code] Repositorio Git (opcional): pre-rellenado con `TF_VAR_default_repo_url`, clona en `~/Projects` al primer arranque.
- Code-server abre por defecto la carpeta clonada en `~/Projects/<repo>`.
- [AI/OpenCode] Provisionar API_KEY de MakeSpace automáticamente: viene activo por defecto, genera la key MakeSpace (30 días), configura OpenCode (base URL por entorno si no pones URL) y exporta `MKS_BASE_URL`/`MKS_API_KEY`.
- [AI/OpenAI] Base URL / API key (opcionales): rellénalas para usar tu proveedor o desactiva la casilla anterior si no quieres la llave preprovisionada. La autoprovisión requiere `TF_VAR_opencode_default_base_url` y `TF_VAR_mks_key_endpoint`.
- [AI/Claude] Token: si lo rellenas se instalará Claude Code (subdomain=false) y las tareas de Coder usarán Claude; OpenCode no instala módulo (solo CLI via script) para evitar conflictos.

## Notas de uso
- El daemon Docker se arranca dentro del contenedor (`dockerd` con overlay2) y guarda datos en `/var/lib/docker`.
- Usa KasmVNC para escritorio XFCE (consola del workspace -> abrir URL de KasmVNC).
- El contenedor lleva labels `com.centurylinklabs.watchtower.*` para auto-actualización vía Watchtower.

### Limitaciones de DinD
- No hay Swarm ni orquestador, por lo que `docker compose` ignora la sección `deploy.*` (incluidos `resources.reservations/limits`, `placement`, `replicas`); solo aplican los flags directos de `docker run`/`docker compose` como `--cpus` o `--memory`.
- Las reservas de recursos son contra el propio workspace: los contenedores hijos comparten el presupuesto de CPU/RAM que tenga asignado el workspace y no pueden reservar más que eso.
- El Docker interno no ve el Docker del host; si necesitas gestionar contenedores/volúmenes del nodo, usa el template AdvancedHostDANGER.

## Cómo publicar cambios
- Edita este template y la imagen base en `Docker-Images/Developer/Dockerfile`.
- Tras el merge a `main`, ejecuta `coder templates push` para desplegar el template en Coder.
