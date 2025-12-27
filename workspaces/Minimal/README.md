---
display_name: Minimal
description: "Workspace básico sin escritorio, con code-server y Docker in Docker"
icon: icon.svg
maintainer_github: makespacemadrid
tags: [docker, dind, workspace, makespace]
---

# Minimal (code-server + DinD)

Workspace ligero basado en la imagen oficial `codercom/enterprise-base:ubuntu`, sin escritorio gráfico. Incluye code-server y Docker in Docker mediante módulos de Coder.

## Cuándo usarlo
- Necesitas un entorno minimalista sin escritorio, solo code-server/terminal.
- Pruebas rápidas con Docker in Docker sin instalar tooling gráfico.

## Qué incluye
- Imagen oficial `codercom/enterprise-base:ubuntu` con tooling base y sudo.
- code-server integrado.
- Docker instalado al iniciar y ejecutando DinD (dockerd dentro del contenedor).
- OpenCode/Claude opcionales para asistentes de IA (con autoprovision de key MakeSpace si se activa).
- Home persistente en `/home/coder` (volumen o bind mount según parámetros) y datos de Docker en `/var/lib/docker`.
- Labels `com.centurylinklabs.watchtower.*` para actualizaciones con Watchtower.

## Creación rápida en Coder
- No hay escritorio; usarás code-server o la terminal.
- `GPU`: activa `--gpus all` en el contenedor.
- `Persistir home en el host`: monta `/home/coder` en `TF_VAR_users_storage/<usuario>/<workspace>`.
- `Persistir solo ~/Projects`: monta `/home/coder/Projects` en `TF_VAR_users_storage/<usuario>/<workspace>/Projects`.
- `Montar ruta host en ~/host`: monta una ruta del host en `/home/coder/host`.
- `Especificar UID para montar la ruta host`: UID para ejecutar el contenedor cuando montas `/home/coder/host` (por defecto 1000).
- `Repositorio Git`: clona en `~/Projects` al primer arranque.
- `OpenCode Base URL` + `OpenCode API key`: configura proveedor OpenAI-compatible.
- `Provisionar API key MakeSpace automáticamente`: genera una key de 30 días si no aportas una.
- `Claude Token`: usa Claude y omite OpenCode (genera el token con `claude setup-token`).

## Notas
- El contenedor se ejecuta en modo `privileged` para soportar Docker in Docker.
- No hay escritorio gráfico; conéctate vía code-server o la terminal del workspace.
- Tras merge a `main`, ejecuta `coder templates push` para publicar el template en Coder.

### Limitaciones de DinD
- No hay Swarm ni orquestador: `docker compose` ignora la sección `deploy.*`, así que no funcionan `resources.reservations/limits`, `placement`, `replicas`, etc. Usa flags de `docker run`/`docker compose` (`--cpus`, `--memory`, `--gpus`) para limitar contenedores.
- Las reservas de CPU/RAM solo pueden consumir lo que tenga asignado el workspace; los contenedores hijos no pueden reservar más allá de ese presupuesto.
- El Docker interno no accede al Docker del host; si necesitas manejar contenedores del nodo host, usa otro template con acceso al socket.
