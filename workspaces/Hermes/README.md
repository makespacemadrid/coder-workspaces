---
display_name: Hermes
description: "Workspace Hermes Agent (Nous Research) sin escritorio: dashboard web headless, sin Docker in Docker"
icon: icon.svg
maintainer_github: makespacemadrid
tags: [hermes, agents, workspace, ocabra]
---

# Hermes (Inicial)

Template para ejecutar [Hermes Agent](https://hermes-agent.nousresearch.com/) sobre la imagen `ghcr.io/makespacemadrid/coder-mks-developer:latest`, sin escritorio gráfico y sin Docker in Docker. Hermes gestiona su propio runtime (Python y Node propios vía `uv`), así que la imagen base solo aporta las herramientas de desarrollo habituales; el agente se ejecuta directamente en el contenedor del workspace (`terminal.backend: local`), igual que ya lo hacen Codex/Claude Code/OpenCode en el resto de templates — sin aislamiento extra porque el propio contenedor ya es el límite de aislamiento.

## Cuándo usarlo
- Quieres un workspace orientado a un agente persistente tipo Hermes, accesible por su dashboard web o por terminal.
- Quieres comparar la experiencia de aprovisionamiento frente a `OpenClaw` (Hermes usa ficheros planos `config.yaml`/`.env`, sin migraciones ni pairing de dispositivo).

## Qué incluye
- Imagen `ghcr.io/makespacemadrid/coder-mks-developer:latest` (sin arrancar su escritorio ni instalar Docker).
- Instalación oficial de Hermes en primer arranque (`curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash -s -- --non-interactive --skip-computer-use`). Se omite el driver de *computer use* porque no hay sesión gráfica donde automatizar nada; el skill de navegador (headless) se mantiene.
- Dashboard web de Hermes (`hermes dashboard --no-open`) en segundo plano, puerto `9119`, expuesto como app `Hermes Dashboard` en Coder.
- Autoprovisión de credenciales Ocabra/FreeAPI (igual que en `Developer`/`OpenClaw`): si hay endpoint configurado, genera una key y la escribe en `~/.hermes/.env` (permisos 600), y registra el proveedor correspondiente en `~/.hermes/config.yaml` vía `hermes config set` (sin tocar JSON anidado ni bases de datos).
- Descubrimiento del catálogo vivo de modelos (mismo script `sync_llm_models.py` que `Developer`/`OpenClaw`) para elegir el modelo de mayor capacidad disponible cuando `[Hermes] Modelo por defecto` está en `auto`.
- `terminal.cwd` fijado al directorio de trabajo configurado (por defecto `~/Projects`).
- Home persistente en `/home/coder` (volumen Docker).
- Labels `com.centurylinklabs.watchtower.*` para actualizaciones con Watchtower.

## Creación rápida en Coder
- Entras por el dashboard de Hermes o por terminal (SSH/consola web); no hay escritorio gráfico ni code-server en este template.
- `[Hermes] Directorio de trabajo`: directorio desde el que opera el agente.
- `[Hermes] Modelo por defecto`: `auto` por defecto para elegir el modelo de mayor capacidad del catálogo vivo; también acepta `provider/model`.
- `Provisionar API key Ocabra automáticamente`: genera una key de 30 días si no aportas una.
- `Provisionar API key FreeAPI automáticamente`: genera y precarga una key de FreeAPI al crear el workspace.
- `TF_VAR_ocabra_endpoint_base_url`: base URL OpenAI-compatible de Ocabra por defecto.
- `TF_VAR_freeapi_base_url` + `TF_VAR_freeapi_key_endpoint`: endpoint OpenAI-compatible y endpoint de provisionado para FreeAPI.

## Notas
- El dashboard de Hermes solo activa su "auth gate" (usuario/contraseña) cuando se hace *bind* a una dirección no-loopback. Como todo el tráfico llega vía el túnel del agente de Coder a `127.0.0.1` dentro del propio contenedor, el dashboard no pide autenticación propia — el único control de acceso es el login de Coder al proxy, igual que el resto de apps de estos templates (KasmVNC, Selkies, code-server...).
- `terminal.backend` se deja en su valor por defecto (`local`): el agente ejecuta comandos directamente en el contenedor del workspace, sin sandbox adicional. Es el mismo modelo de confianza que ya tienen Codex/Claude Code/OpenCode en estos templates; no se usa Docker in Docker.
- No se preconfigura ningún canal de chat (Telegram/Discord/Slack/...). Quien quiera uno lo añade con `hermes gateway setup` desde su propia terminal; eso arranca un proceso de gateway independiente del dashboard.
- *Computer use* (`cua-driver`) está deliberadamente desactivado en la instalación porque no hay escritorio gráfico donde automatizar nada. Si en el futuro se añade un escritorio ligero (p. ej. vía el addon oficial de Selkies), se puede revisar si merece la pena reactivarlo.
- Las credenciales Ocabra/FreeAPI se guardan en `~/.hermes/.env` (permisos 600), referenciadas desde `config.yaml` vía `key_env` por proveedor, para poder tener Ocabra y FreeAPI configurados a la vez sin que compartan la misma variable de entorno.
- Puedes relanzar manualmente el dashboard con `~/.local/bin/start-hermes-dashboard`; sus logs están en `~/.local/state/hermes/hermes-dashboard.log`.
- Tras merge a `main`, ejecuta `coder templates push` para publicar el template en Coder.
