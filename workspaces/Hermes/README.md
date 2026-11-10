---
display_name: Hermes
description: "Workspace Hermes Agent (Nous Research) sin escritorio: dashboard web headless, sin Docker in Docker"
icon: icon.svg
maintainer_github: makespacemadrid
tags: [hermes, agents, workspace, ocabra]
---

# Hermes (Inicial)

Template para ejecutar [Hermes Agent](https://hermes-agent.nousresearch.com/) sobre la imagen headless `ghcr.io/makespacemadrid/coder-mks-developer-cli:latest`, sin escritorio gráfico y sin Docker in Docker. Hermes gestiona su propio runtime (Python y Node propios vía `uv`), así que la imagen base solo aporta las herramientas de desarrollo habituales; el agente se ejecuta directamente en el contenedor del workspace (`terminal.backend: local`), igual que ya lo hacen Codex/Claude Code/OpenCode en el resto de templates — sin aislamiento extra porque el propio contenedor ya es el límite de aislamiento.

## Cuándo usarlo
- Quieres un workspace orientado a un agente persistente tipo Hermes, accesible por su dashboard web o por terminal.
- Quieres comparar la experiencia de aprovisionamiento frente a `OpenClaw` (Hermes usa ficheros planos `config.yaml`/`.env`, sin migraciones ni pairing de dispositivo).

## Qué incluye
- Imagen `ghcr.io/makespacemadrid/coder-mks-developer-cli:latest` (sin escritorio; trae Docker pero este template no lo arranca).
- Instalación oficial de Hermes en primer arranque (`curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash -s -- --non-interactive --skip-computer-use`). Se omite el driver de *computer use* porque no hay sesión gráfica donde automatizar nada; el skill de navegador (headless) se mantiene.
- Dashboard web de Hermes (`hermes dashboard --no-open`) en `127.0.0.1:9119`, publicado como app `Hermes Dashboard` en Coder a través de `loopback-proxy` (`:19119`). Dashboard y proxy están supervisados: si se caen, vuelven a arrancar solos.
- Credencial Ocabra autoprovisionada (igual que en `Developer`/`OpenClaw`) o la tuya propia si eliges `Usar mi propia clave`: se escribe en `~/.hermes/.env` (permisos 600), y registra el proveedor en `~/.hermes/config.yaml` vía `hermes config set` (sin tocar JSON anidado ni bases de datos).
- Descubrimiento del catálogo vivo de modelos (mismo script `sync_llm_models.py` que `Developer`/`OpenClaw`) para elegir el modelo de mayor capacidad disponible cuando `[Hermes] Modelo por defecto` está en `auto`.
- `terminal.cwd` fijado al directorio de trabajo configurado (por defecto `~/Projects`).
- **Preconfiguración MakeSpace** (se reaplica en cada arranque):
  - Español y zona horaria `Europe/Madrid` (CLI/TUI, chat del dashboard y reconocimiento de voz). El idioma de la web del dashboard lo elige cada navegador en su selector; Hermes no permite fijarlo.
  - Voz con Ocabra: TTS `recomendado-tts` (voz `es_MX-claude-high`) y STT `recomendado-stt`.
  - Memoria con búsqueda semántica: plugin `holographic` con embeddings `recomendado-embedding` de Ocabra. La memoria de serie de Hermes solo busca por texto. Sin rerank, porque el de holographic no envía clave.
  - Banner *"Help improve Hermes?"* respondido como *No thanks*.
  - `~/.hermes/SOUL.md` con contexto de MakeSpace (`assistant_persona.md`), solo si es el texto por defecto de Hermes. Si lo editas, no se toca.
- **Telegram (opcional):** `[Telegram] Token del bot` conecta Hermes a tu bot de @BotFather y arranca el gateway de mensajería, supervisado. Con `[Telegram] IDs de usuario permitidos` solo responde a esos IDs. Sin IDs, quien le escriba recibe un código que apruebas con `hermes pairing approve telegram <CODIGO>`.
- Home persistente en `/home/coder` (volumen Docker).
- Labels `com.centurylinklabs.watchtower.*` para actualizaciones con Watchtower.

## Creación rápida en Coder
- Crea el workspace y, cuando termine el arranque (el primero tarda ~2 minutos por la instalación), pulsa **Hermes Dashboard**. También tienes terminal (SSH/consola web); no hay escritorio gráfico ni code-server.
- `[Hermes] Directorio de trabajo`: directorio desde el que opera el agente.
- `[Hermes] Modelo por defecto`: `auto` por defecto, que usa `recomendado-sota` de Ocabra (alias del mejor modelo de chat disponible) o, si no existe, el de mayor capacidad del catálogo vivo; también acepta `provider/model`. Hermes fija el modelo de cada conversación al crearla: tras cambiarlo, abre una sesión nueva o usa `/model <id>`.
- `Provisionar API key Ocabra automáticamente`: genera una key de 30 días si no aportas una.
- `TF_VAR_ocabra_endpoint_base_url`: base URL OpenAI-compatible de Ocabra por defecto.

## Notas
- El dashboard de Hermes solo activa su "auth gate" (usuario/contraseña) cuando se hace *bind* a una dirección no-loopback. Como todo el tráfico llega vía el túnel del agente de Coder a `127.0.0.1` dentro del propio contenedor, el dashboard no pide autenticación propia — el único control de acceso es el login de Coder al proxy, igual que el resto de apps de estos templates (KasmVNC, Selkies, code-server...).
- `terminal.backend` se deja en su valor por defecto (`local`): el agente ejecuta comandos directamente en el contenedor del workspace, sin sandbox adicional. Es el mismo modelo de confianza que ya tienen Codex/Claude Code/OpenCode en estos templates; no se usa Docker in Docker.
- No se preconfigura ningún canal de chat (Telegram/Discord/Slack/...). Quien quiera uno lo añade con `hermes gateway setup` desde su propia terminal; eso arranca un proceso de gateway independiente del dashboard.
- *Computer use* (`cua-driver`) está deliberadamente desactivado en la instalación porque no hay escritorio gráfico donde automatizar nada. Si en el futuro se añade un escritorio ligero (p. ej. vía el addon oficial de Selkies), se puede revisar si merece la pena reactivarlo.
- La credencial Ocabra se guarda en `~/.hermes/.env` (permisos 600), referenciada desde `config.yaml` vía `key_env`.
- El dashboard rechaza cualquier Host que no sea el de bind (`Invalid Host header`) y sus WebSockets exigen Origin local. `loopback-proxy` (script Node en `~/.local/bin`, sustituye al nginx que antes se instalaba con apt en cada arranque) reescribe Host/Origin a `127.0.0.1:9119` y quita las cabeceras `X-Forwarded-*` de Coder.
- Puedes relanzar/parar manualmente con `~/.local/bin/start-hermes-dashboard` / `stop-hermes-dashboard`; logs en `~/.local/state/hermes/hermes-dashboard.log` y `ui-proxy.log`.
- Tras merge a `main`, ejecuta `coder templates push` para publicar el template en Coder.
