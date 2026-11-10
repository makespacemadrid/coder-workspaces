---
display_name: OpenClaw
description: "Workspace OpenClaw sin escritorio: gateway headless con Control UI web, sin privilegios"
icon: icon.svg
maintainer_github: makespacemadrid
tags: [openclaw, agents, workspace, ocabra]
---

# OpenClaw (Inicial)

Template para ejecutar OpenClaw sobre la imagen headless `ghcr.io/makespacemadrid/coder-mks-developer-cli:latest`, sin escritorio gráfico y sin nada que no haga falta para OpenClaw. OpenClaw es un gateway headless por diseño (pensado para `systemd`/`launchd`, sin necesidad de X11) y su propia herramienta de navegador corre headless por defecto, así que no hace falta KasmVNC ni Chrome instalados en el workspace. Tampoco se gestiona configuración de Codex/OpenCode ni se instala `gh`: ese tooling vive en otros templates (`Developer`, `Maker`...), no es necesario para que OpenClaw funcione.

## Cuándo usarlo
- Quieres un workspace orientado solo a agentes/OpenClaw accesible desde el navegador (app `OpenClaw UI`) o por terminal, sin el coste de un escritorio gráfico ni de tooling de otros CLIs de IA.
- Necesitas ajustar puerto/directorio de OpenClaw por proyecto.

## Qué incluye
- Imagen `ghcr.io/makespacemadrid/coder-mks-developer-cli:latest` (Node.js 24 ya incluido; sin escritorio).
- Contenedor **sin `privileged` y sin Docker in Docker** (ver Notas).
- Node.js se actualiza automáticamente a `>=24.22.1` solo si la imagen trae uno más antiguo (requisito actual de OpenClaw).
- Homebrew instalado en `~/.linuxbrew` (persistente en `/home/coder`) para facilitar instalación de skills/plugins opcionales de OpenClaw.
- Parámetros de OpenClaw: autoarranque, puerto y directorio.
- Instalación oficial de OpenClaw en primer arranque (`curl -fsSL https://openclaw.ai/install.sh | bash`) en modo no interactivo.
- Gateway y proxy de la UI supervisados: si se caen (o OpenClaw se reinicia tras un cambio de config) vuelven a arrancar solos.
- Scripts `~/.local/bin/start-openclaw` / `stop-openclaw`; logs en `~/.local/state/openclaw/openclaw.log` y `ui-proxy.log`.
- App `OpenClaw UI` en Coder: un clic y entras ya autenticado y con el navegador emparejado, sin pegar token ni aprobar dispositivos.
- App `Conectar móvil`: página con el QR para vincular la app oficial de OpenClaw (iOS/Android). Avisa si el gateway aún no es accesible desde Internet. Ver "Conectar el móvil".
- **Preconfiguración MakeSpace** (se reaplica en cada arranque):
  - Control UI en español y zona horaria del agente `Europe/Madrid`.
  - Voz con Ocabra: TTS `recomendado-tts` y transcripción de audio entrante con `recomendado-stt`. Talk en modo `stt-tts`, porque Ocabra no tiene realtime.
  - Memoria con búsqueda semántica: embeddings `recomendado-embedding` de Ocabra. Se reindexa solo si cambia el modelo. OpenClaw no tiene reranker configurable.
  - Contexto de MakeSpace (`assistant_persona.md`) en una sección gestionada al final de `~/.openclaw/workspace/AGENTS.md`, entre marcadores `<!-- makespace:begin/end -->`. `SOUL.md`, `IDENTITY.md` y el resto de `AGENTS.md` no se tocan.
- **Telegram (opcional):** `[Telegram] Token del bot` conecta OpenClaw a tu bot de @BotFather. Con `[Telegram] IDs de usuario permitidos` solo esos usuarios pueden escribirle (allowlist). Sin IDs se usa emparejamiento: `openclaw pairing approve telegram <CODIGO>`, y el primero aprobado queda como owner. En grupos solo responde si lo mencionan.
- Home persistente en `/home/coder` (volumen Docker).
- Labels `com.centurylinklabs.watchtower.*` para actualizaciones con Watchtower.

## Creación rápida en Coder
- Crea el workspace y, cuando termine el arranque (el primero tarda 2-3 minutos por la instalación), pulsa **OpenClaw UI**. También tienes terminal (SSH/consola web); no hay escritorio gráfico ni code-server.
- `[OpenClaw] Auto-iniciar servicio`: arranca OpenClaw al iniciar.
- `[OpenClaw] Directorio de trabajo`: directorio desde el que se ejecuta OpenClaw.
- `[OpenClaw] Modelo por defecto`: `auto` por defecto, que usa `recomendado-sota` de Ocabra (alias del mejor modelo de chat disponible) o, si no existe, el de mayor capacidad del catálogo vivo; también acepta `provider/model`.
- `Provisionar API key Ocabra automáticamente`: genera una key de 30 días si no aportas una.
- `TF_VAR_ocabra_endpoint_base_url`: base URL OpenAI-compatible de Ocabra por defecto.

## Conectar el móvil
1. Activa **`[OpenClaw] Acceso desde el móvil`** en los parámetros del workspace, al crearlo o después en *Settings → Parameters → Update*.
2. Pulsa la app **Conectar móvil**: muestra el QR y confirma que el gateway es accesible desde Internet.
3. En la app oficial de OpenClaw: *Settings → Gateway* (u *Onboarding → Scan QR*) y escanea el QR. Se vincula sola. El código es de un solo uso, caduca en unos minutos y con *Generar código nuevo* sale otro.

Cómo funciona:
- El checkbox crea una app de Coder **pública y oculta** (`openclaw-gateway`) que apunta directamente al gateway (`:3333`). Coder no permite marcar un puerto como público desde Terraform; una app con `share = "public"` es el equivalente.
- El QR codifica el *setup code* de `openclaw qr` con la URL `wss://openclaw-gateway--<workspace>--<owner>.<host-coder>/openclaw` (`plugins.entries.device-pair.config.publicUrl`).
- El gateway queda accesible desde Internet, protegido por su token y por el emparejamiento de dispositivos. `gateway.trustedProxies` en loopback hace que ese tráfico se atribuya al cliente real y se trate como remoto. La UI del navegador no cambia: sigue entrando por `loopback-proxy` como conexión local.
- Sin el checkbox, el QR apunta al puerto compartido `wss://3333--main--<workspace>--<owner>.<host-coder>`, que funciona si pones el **3333** en **Public** a mano desde el panel *Ports* de Coder.
- Para dejar de exponerlo, desactiva el checkbox. Los móviles ya vinculados se pueden revocar en *Configuración → Dispositivos* de la UI.

Para CLI o app de escritorio no hace falta hacer público nada: `coder port-forward <workspace> --tcp 18789:3333` y conecta a `ws://127.0.0.1:18789` con el token del gateway.

## Notas
- El arranque de OpenClaw es síncrono en startup: intenta dejar el gateway arriba antes de finalizar el arranque del workspace, lo que puede añadir 2-3 minutos al primer arranque del workspace.
- Los límites de `inotify` (`max_user_watches/max_user_instances/max_queued_events`) que necesita OpenClaw para evitar `EMFILE` no son por contenedor: se fijan en el host (`/etc/sysctl.d/99-inotify.conf`). El arranque avisa si están bajos.
- Si `openclaw` no está instalado y el autoarranque está activo, el template intenta instalarlo automáticamente con el instalador oficial.
- Tras el autoarranque, el template prueba salud operativa con `openclaw health` (best-effort) para detectar fallos tempranos del gateway.
- **Cómo funciona el acceso web**: la app `OpenClaw UI` no apunta al gateway (`:3333`) sino a `loopback-proxy` (`:13333`, script Node en `~/.local/bin`). El proxy reescribe Host/Origin a `127.0.0.1:3333` y elimina las cabeceras `X-Forwarded-*` que añade Coder, así que el gateway ve una conexión local: acepta el origen sin `allowedOrigins` y **auto-aprueba el pairing del navegador** (comportamiento documentado de OpenClaw para conexiones loopback directas). El token sigue siendo obligatorio y va en la URL de la app (`?token=`).
- Sin el proxy, el gateway trataba al navegador como remoto y cada navegador nuevo se quedaba en *"Approve this browser — openclaw devices approve …"*. `gateway.controlUi.dangerouslyDisableDeviceAuth` ya no existe en OpenClaw (inerte; `doctor --fix` lo borra), así que esa vía no sirve.
- Seguridad: el proxy solo escucha en `127.0.0.1` y solo se alcanza a través del proxy autenticado de Coder (app con sharing `owner`) o desde procesos del propio workspace, que ya pueden leer el token. Es la misma confianza que un `ssh -L` al gateway.
- La UI se sirve bajo `/openclaw` (`gateway.controlUi.basePath`), no en la raíz: como la URL de la app lleva `?token=`, Coder responde 307 a cualquier petición a `/` para añadir esa query, también al WebSocket, que la UI abre en `<basePath>`. En la raíz el WebSocket nunca se abría y la UI mostraba *"Gateway ocupado, reintentando…"*.
- La app usa subdominio (`subdomain=true`): la Control UI carga sus assets con rutas absolutas (`/assets/...`), que en modo ruta apuntarían al propio Coder. Requiere `CODER_WILDCARD_ACCESS_URL` configurado.
- En cada arranque el template retira `gateway.controlUi.allowedOrigins` y `dangerouslyAllowHostHeaderOriginFallback`, que ponían versiones anteriores. Con el proxy ya no hacen falta. `gateway.trustedProxies` se mantiene en loopback para el acceso del móvil y no afecta a la UI, porque el proxy quita las cabeceras `X-Forwarded-*`.
- El token del gateway se genera automáticamente (aleatorio) por workspace y se sincroniza en `gateway.auth.token`, de modo que `openclaw dashboard --no-open` y la app `OpenClaw UI` usan el mismo valor.
- El template fija `gateway.port` al puerto configurado del workspace (por defecto `3333`) para evitar desajustes del CLI con el puerto `18789`.
- Si abres la UI desde otro navegador/perfil (o en modo privado) se empareja de nuevo automáticamente; puedes limpiar entradas viejas con `openclaw devices list` / `openclaw devices remove <id>`.
- El template puede autoprovisionar la credencial API de Ocabra (`OCABRA_KEY`), con su propio toggle en el formulario.
- El template crea `auth-profiles.json` con el perfil `ocabra:manual`.
- El template descubre el catálogo vivo de Ocabra mediante `/v1/models` o `/models`; no mantiene un roster estático.
- Cuando está disponible `/model/info` (LiteLLM), enriquece automáticamente capacidades, tokens y costes por modelo.
- El template rellena `agents.defaults.models` con esos modelos para que aparezcan en el selector de agentes.
- El template asegura `agents.list` con entrada `id: "main"` para que los cambios de modelo en la UI de agentes se marquen como modificados y el botón `Save` se habilite.
- Las capacidades de razonamiento, visión y audio se obtienen de la metadata del endpoint, con una detección conservadora por familia como respaldo.
- En modo `auto`, el modelo por defecto se elige entre los modelos realmente descubiertos priorizando las familias de mayor capacidad; también se puede indicar cualquier `provider/model` explícito.
- Si `[OpenClaw] Modelo por defecto` no incluye prefijo de provider, el template asume `ocabra/<modelo>`.
- Si el provider del modelo por defecto no está configurado (falta base URL), el template no fuerza ese modelo para evitar `Unknown model`.
- El template persiste `OPENAI_API_KEY` y `OPENAI_BASE_URL` en `~/.openclaw/.env`.
- El template deja Homebrew inicializado en `~/.profile` y `~/.bashrc` usando `eval "$($HOME/.linuxbrew/bin/brew shellenv)"`.
- El template no parchea los assets de `control-ui`; usa el flujo nativo de OpenClaw para tomar `?token` y guardarlo en `localStorage`.
- Puedes relanzar manualmente con `~/.local/bin/start-openclaw`.
- Si ejecutas `openclaw dashboard` en una terminal sin GUI, es normal ver "No GUI detected"; en Coder abre directamente el app `OpenClaw UI`.
- **Sin `privileged` ni Docker in Docker** (antes sí): un contenedor privilegiado da root en el host a quien tenga `sudo` dentro, y aquí lo tienen tanto el usuario como el propio agente (que podría ejecutar lo que le pida una inyección de prompt). OpenClaw no necesita Docker para la UI ni para el agente. Si necesitas Docker, usa `Developer`.
- Tras merge a `main`, ejecuta `coder templates push` para publicar el template en Coder.

