---
display_name: DeveloperDesktop
description: "Workspace con escritorio KDE (Selkies), Docker in Docker y GPU opcional. Para quien necesite GUI; si no, usa Developer."
icon: icon.svg
maintainer_github: makespacemadrid
tags: [docker, dind, gpu, workspace, ocabra, desktop]
---

# DeveloperDesktop (KDE + Selkies, Docker in Docker)

Workspace de desarrollo general con escritorio KDE real vía **Selkies** (streaming WebRTC), **Docker in Docker (DinD)** y aislamiento del host. Usa la imagen `ghcr.io/makespacemadrid/coder-mks-developer-desktop:latest`.

## Para qué sirve
- Igual que `Developer`, pero con escritorio gráfico: apps de escritorio, navegador, IDEs visuales.
- Si no necesitas GUI, usa el template `Developer` (headless, más ligero).
- Proyectos que necesitan GPU opcional (NVENC/CUDA) y mapeo de puertos a host.

## Qué incluye
- Docker Engine y docker-compose-plugin internos (DinD, no se usa el socket del host).
- Escritorio KDE Plasma vía Selkies, accesible como app "Desktop" desde Coder.
- Apps desktop: VS Code, GitHub Desktop, Claude Desktop, OpenCode Desktop, Google Chrome, Firefox, Geany, AppImage Pool, Antigravity.
- Node.js 24, CLIs de IA (OpenAI/Codex, Claude, Gemini, Continue, Qwen), git/gh.
- Persistencia en `/home/coder` (volumen o bind mount) y `/var/lib/docker`.
- Limpieza automática semanal del Docker interno: caché de build sin uso durante 7 días e imágenes sin contenedores asociadas de más de 30 días.
- Si existe `$TF_VAR_users_storage/_provisioning/desktop/wallpapers`, se monta de solo lectura y aplica el fondo de escritorio compartido en el primer arranque; no sobrescribe un fondo que ya hayas cambiado.

## Creación rápida en Coder
- Si es tu primera vez, probablemente no necesitas tocar nada: baja al final y pulsa `Create workspace`.
- [Compute] Aceleración gráfica: `Software` (CPU, sin GPU) o `GPU NVIDIA` (pasa la GPU completa, habilita NVENC/CUDA).
- [Storage] Persistencia: `Ninguna` (volumen Docker), `Home completo` o `Solo ~/Projects` en el host.
- [Network] Exponer puertos al host: usa el rango de puertos para publicar servicios.
- [Maintenance] Limpieza automática de Docker: activa por defecto; no elimina volúmenes ni contenedores y se puede desactivar desde los parámetros del workspace.
- [AI] Clave Ocabra: auto-aprovisionar una key nueva (por defecto) o usar la tuya.
- [AI] Provisionar API key FreeAPI automáticamente: activo por defecto.
- [AI] Modelo por defecto de OpenCode: `opencode/glm-5.3-flash-free` (gratuito); también acepta `auto` o cualquier `provider/model` del catálogo.

## Notas de uso
- El daemon Docker se arranca dentro del contenedor (`dockerd` con overlay2) y guarda datos en `/var/lib/docker`.
- `Docker auto-prune` se ejecuta los domingos a las 04:30 mientras el workspace está encendido. También comprueba la última ejecución al arrancar para recuperar semanas en las que estuviera apagado; los resultados aparecen en los logs de scripts de Coder.
- El contenedor lleva labels `com.centurylinklabs.watchtower.*` para auto-actualización vía Watchtower.
- Claude Desktop fuerza `COWORK_VM_BACKEND=host` para que el modo cowork no intente usar `bwrap` dentro del contenedor.

### Limitaciones de DinD
- No hay Swarm ni orquestador, por lo que `docker compose` ignora la sección `deploy.*` (incluidos `resources.reservations/limits`, `placement`, `replicas`); solo aplican los flags directos de `docker run`/`docker compose` como `--cpus` o `--memory`.
- Las reservas de recursos son contra el propio workspace: los contenedores hijos comparten el presupuesto de CPU/RAM que tenga asignado el workspace y no pueden reservar más que eso.
- El Docker interno no ve el Docker del host.

## Cómo publicar cambios
- Edita este template y la imagen base en `Docker-Images/DeveloperDesktop/Dockerfile`.
- Tras el merge a `main`, ejecuta `coder templates push` para desplegar el template en Coder.
