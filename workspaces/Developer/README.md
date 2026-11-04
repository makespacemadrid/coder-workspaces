---
display_name: Developer
description: "Workspace headless de desarrollo: Docker in Docker, CLIs de IA y JupyterLab. GPU opcional solo para cómputo (CUDA/NVENC)."
icon: icon.svg
maintainer_github: makespacemadrid
tags: [docker, dind, workspace, ocabra]
---

# Developer (headless, Docker in Docker)

Workspace de desarrollo general sin escritorio gráfico, con **Docker in Docker (DinD)** y aislamiento del host. Usa la imagen `ghcr.io/makespacemadrid/coder-mks-developer-cli:latest`.

## Para qué sirve
- Entornos de desarrollo aislados sin tocar el Docker del host, vía terminal/code-server.
- Proyectos que necesitan GPU opcional para cómputo (CUDA/NVENC) — no hay escritorio que acelerar, así que GPU solo tiene sentido si la vas a usar directamente en tu código.
- Si necesitas escritorio gráfico (KDE/Selkies), usa el template `DeveloperDesktop` en su lugar.

## Qué incluye
- Docker Engine y docker-compose-plugin internos (DinD, no se usa el socket del host).
- code-server y JupyterLab (módulos de Coder).
- Node.js 24, CLIs de IA (OpenAI/Codex, Claude, Gemini, Continue, Qwen), git/gh — todo horneado en la imagen, sin fallbacks de instalación en runtime.
- Python con `venv`/`pipx` y kernel Jupyter (`coder-py`) listo para usar.
- Persistencia en `/home/coder` (volumen Docker o bind mount según parámetros) y `/var/lib/docker`.
- Limpieza automática semanal del Docker interno: caché de build sin uso durante 7 días e imágenes sin contenedores asociadas de más de 30 días.

## Creación rápida en Coder
- Si es tu primera vez, probablemente no necesitas tocar nada: baja al final y pulsa `Create workspace`.
- Qué es: workspace headless con Docker DinD, code-server/JupyterLab y tooling de IA listo para usar.
- [Compute] Aceleración gráfica: déjalo en `Software` salvo que necesites GPU NVIDIA para cómputo (CUDA/NVENC) en tu propio código.
- [Storage] Persistencia: `Ninguna` (volumen Docker), `Home completo` o `Solo ~/Projects` en el host.
- [Network] Exponer puertos al host: usa el rango de puertos para publicar servicios.
- [Maintenance] Limpieza automática de Docker: activa por defecto; no elimina volúmenes ni contenedores y se puede desactivar desde los parámetros del workspace.
- [AI MakeSpace] Clave Ocabra: auto-aprovisionar una key nueva (por defecto) o usar la tuya.
- [AI] Modelo por defecto de OpenCode: `opencode/glm-5.3-flash-free` (gratuito); también acepta `auto` o cualquier `provider/model` del catálogo.
- [AI externa] Modelos gratuitos de OpenCode (Zen): activos por defecto; desactívalo si no quieres que aparezcan en el selector.
- [AI externa] Ollama Cloud / NVIDIA (build.nvidia.com): campos opcionales para tu propia API key; si la rellenas, OpenCode añade ese proveedor con su catálogo vivo.

## Notas de uso
- El daemon Docker se arranca dentro del contenedor (`dockerd` con overlay2) y guarda datos en `/var/lib/docker`.
- `Docker auto-prune` se ejecuta los domingos a las 04:30 mientras el workspace está encendido. También comprueba la última ejecución al arrancar para recuperar semanas en las que estuviera apagado; los resultados aparecen en los logs de scripts de Coder.
- El contenedor lleva labels `com.centurylinklabs.watchtower.*` para auto-actualización vía Watchtower.

### Limitaciones de DinD
- No hay Swarm ni orquestador, por lo que `docker compose` ignora la sección `deploy.*` (incluidos `resources.reservations/limits`, `placement`, `replicas`); solo aplican los flags directos de `docker run`/`docker compose` como `--cpus` o `--memory`.
- Las reservas de recursos son contra el propio workspace: los contenedores hijos comparten el presupuesto de CPU/RAM que tenga asignado el workspace y no pueden reservar más que eso.
- El Docker interno no ve el Docker del host.

## Cómo publicar cambios
- Edita este template y la imagen base en `Docker-Images/DeveloperCLI/Dockerfile`.
- Tras el merge a `main`, ejecuta `coder templates push` para desplegar el template en Coder.
