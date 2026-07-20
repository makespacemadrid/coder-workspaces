---
display_name: OpenClaw
description: "Workspace OpenClaw con escritorio básico (KasmVNC), Chrome y Docker in Docker"
icon: icon.svg
maintainer_github: makespacemadrid
tags: [openclaw, agents, docker, dind, workspace, ocabra]
---

# OpenClaw (Inicial)

Template inicial para ejecutar OpenClaw sobre la imagen `ghcr.io/makespacemadrid/coder-mks-developer:latest`, con escritorio básico XFCE en KasmVNC, Chrome y Docker in Docker.

## Cuándo usarlo
- Quieres un workspace orientado a agentes/OpenClaw con escritorio básico web.
- Necesitas ajustar puerto/directorio de OpenClaw por proyecto.

## Qué incluye
- Imagen `ghcr.io/makespacemadrid/coder-mks-developer:latest` con escritorio y tooling dev.
- Escritorio XFCE con módulo `kasmvnc`.
- Navegador Chrome (con fallback a Chromium si no está disponible el paquete).
- Docker instalado al iniciar y ejecutando DinD (dockerd dentro del contenedor).
- Node.js actualizado automáticamente a `>=22.12` cuando hace falta (requisito de OpenClaw).
- Homebrew instalado en `~/.linuxbrew` (persistente en `/home/coder`) para facilitar instalación de skills/plugins opcionales.
- Parámetros de OpenClaw: autoarranque, puerto y directorio.
- Instalación oficial de OpenClaw en primer arranque (`curl -fsSL https://openclaw.ai/install.sh | bash`) en modo no interactivo.
- Script `~/.local/bin/start-openclaw` y logs en `~/.local/state/openclaw/openclaw.log`.
- App dedicada `OpenClaw UI` en Coder (reverse proxy al puerto configurado).
- Home persistente en `/home/coder` (volumen o bind mount según parámetros) y datos de Docker en `/var/lib/docker`.
- Labels `com.centurylinklabs.watchtower.*` para actualizaciones con Watchtower.

## Creación rápida en Coder
- Puedes entrar por KasmVNC (escritorio) o terminal.
- `[OpenClaw] Auto-iniciar servicio`: arranca OpenClaw al iniciar.
- `[OpenClaw] Directorio de trabajo`: directorio desde el que se ejecuta OpenClaw.
- `[OpenClaw] Modelo por defecto`: modelo por defecto para OpenClaw (por defecto `ocabra/qwen3:14b`).
- `Provisionar API key Ocabra automáticamente`: genera una key de 30 días si no aportas una.
- `Provisionar API key FreeAPI automáticamente`: genera y precarga una key de FreeAPI al crear el workspace.
- `TF_VAR_ocabra_endpoint_base_url`: base URL OpenAI-compatible de Ocabra por defecto.
- `TF_VAR_freeapi_base_url` + `TF_VAR_freeapi_key_endpoint`: endpoint OpenAI-compatible y endpoint de provisionado para FreeAPI.

## Notas
- El arranque de OpenClaw es síncrono en startup: intenta dejar el gateway arriba antes de finalizar el arranque del workspace.
- Durante startup se muestra un aviso indicando que, aunque KasmVNC ya esté listo, la instalación/configuración de OpenClaw puede tardar 2-3 minutos adicionales.
- El template sube límites de `inotify` (`max_user_watches/max_user_instances/max_queued_events`) para reducir errores `EMFILE` en watchers de OpenClaw.
- Si `openclaw` no está instalado y el autoarranque está activo, el template intenta instalarlo automáticamente con el instalador oficial.
- Tras el autoarranque, el template prueba salud operativa con `openclaw health` (best-effort) para detectar fallos tempranos del gateway.
- La app `OpenClaw UI` apunta a `http://localhost:<puerto OpenClaw>/?token=<gateway token>` para inyectar credenciales en cada apertura y su healthcheck usa `/`.
- La app `OpenClaw UI` también inyecta `gatewayUrl=wss://<host-coder>/@<owner>/<workspace>.main/apps/openclaw-ui/?token=<gateway token>` para fijar el endpoint WS correcto del workspace.
- La app `OpenClaw UI` se publica en modo ruta (`subdomain=false`) y abre en pestaña normal (`open_in="tab"`), evitando dependencias de cookies efímeras de subdominio que pueden terminar en `disconnected (1006)` en algunos navegadores móviles.
- El token del gateway se genera automáticamente (aleatorio) por workspace.
- El template sincroniza ese token en `gateway.auth.token`, de modo que `openclaw dashboard --no-open` y la app `OpenClaw UI` usan el mismo valor.
- El template fija `gateway.port` al puerto configurado del workspace (por defecto `3333`) para evitar desajustes del CLI con el puerto `18789`.
- El template configura `gateway.controlUi.allowedOrigins` para permitir el acceso de la UI a través de subdominios de Coder y evitar `origin not allowed`.
- Importante: no usar `gateway.controlUi.allowedOrigins="*"` (ni `["*"]`) en este template. En práctica causa rechazos de origen y desconexiones (`1006`). Deben usarse orígenes explícitos de Coder.
- El template activa `gateway.controlUi.dangerouslyAllowHostHeaderOriginFallback=true` para compatibilidad con subdominios dinámicos de Coder.
- El template configura `gateway.trustedProxies` para aceptar headers de proxy de Coder y evitar rechazos por origen detrás del reverse proxy.
- El template desactiva el pairing de dispositivos (`gateway.controlUi.dangerouslyDisableDeviceAuth=true`) para entrar directamente con token.
- El template puede autoprovisionar 2 credenciales API (si hay endpoints): Ocabra (`OCABRA_KEY`) y FreeAPI (`FREEAPI_KEY_ENDPOINT`), cada una con su propio toggle en el formulario.
- El template crea `auth-profiles.json` con perfiles `ocabra:manual` y/o `freeapi:manual`.
- El template define `models.providers.ocabra` con `qwen3:14b`, `qwen3:32b`, `qwen3-coder:30b`, `gpt-oss:20b`.
- El template detecta modelos FreeAPI acabados en `-ha` y, cuando está disponible `/model/info` (LiteLLM), enriquece automáticamente capacidades, tokens y costes por modelo.
- El template rellena `agents.defaults.models` con esos modelos para que aparezcan en el selector de agentes.
- El template asegura `agents.list` con entrada `id: "main"` para que los cambios de modelo en la UI de agentes se marquen como modificados y el botón `Save` se habilite.
- Para los modelos de familia `qwen3*`, el template marca `reasoning=true`.
- Si `[OpenClaw] Modelo por defecto` no incluye prefijo de provider, el template asume `ocabra/<modelo>`.
- Si el provider del modelo por defecto no está configurado (falta base URL), el template no fuerza ese modelo para evitar `Unknown model`.
- El template persiste `OPENAI_API_KEY`, `OPENAI_BASE_URL`, `FREEAPI_API_KEY` y `FREEAPI_BASE_URL` en `~/.openclaw/.env`.
- El template deja Homebrew inicializado en `~/.profile` y `~/.bashrc` usando `eval "$($HOME/.linuxbrew/bin/brew shellenv)"`.
- El template no parchea los assets de `control-ui`; usa el flujo nativo de OpenClaw para tomar `?token` y guardarlo en `localStorage`.
- Puedes relanzar manualmente con `~/.local/bin/start-openclaw`.
- Si ejecutas `openclaw dashboard` en una terminal sin GUI, es normal ver "No GUI detected"; en Coder abre directamente el app `OpenClaw UI`.
- El contenedor se ejecuta en modo `privileged` para soportar Docker in Docker.
- Tras merge a `main`, ejecuta `coder templates push` para publicar el template en Coder.

### Limitaciones de DinD
- No hay Swarm ni orquestador: `docker compose` ignora la sección `deploy.*`, así que no funcionan `resources.reservations/limits`, `placement`, `replicas`, etc. Usa flags de `docker run`/`docker compose` (`--cpus`, `--memory`, `--gpus`) para limitar contenedores.
- Las reservas de CPU/RAM solo pueden consumir lo que tenga asignado el workspace; los contenedores hijos no pueden reservar más allá de ese presupuesto.
- El Docker interno no accede al Docker del host; si necesitas manejar contenedores del nodo host, usa otro template con acceso al socket.
