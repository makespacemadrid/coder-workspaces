terraform {
  required_providers {
    coder = {
      source  = "coder/coder"
      version = "~> 2.18.0"
    }
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 4.6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.9.0"
    }
  }
}

variable "docker_socket" {
  default     = "unix:///var/run/docker.sock"
  description = "(Opcional) Docker socket URI (usa unix:// prefix)"
  type        = string
}

variable "ocabra_endpoint_base_url" {
  default     = ""
  description = "Base URL OpenAI-compatible por defecto (ej. $TF_VAR_ocabra_endpoint_base_url)."
  type        = string
}

variable "ocabra_key" {
  default     = ""
  description = "Endpoint para solicitar keys Ocabra (autoprovision)."
  type        = string
}

data "coder_parameter" "ocabra_key_mode" {
  name         = "60_ocabra_key_mode"
  display_name = "[AI] Clave Ocabra"
  description  = "Auto-aprovisionar una API key Ocabra nueva (30 días), o usar una que ya tengas."
  type         = "string"
  default      = "auto"
  order        = 60
  mutable      = true
  option {
    name  = "Auto-aprovisionar"
    value = "auto"
  }
  option {
    name  = "Usar mi propia clave"
    value = "manual"
  }
}

data "coder_parameter" "ocabra_key_value" {
  name         = "61_ocabra_key_value"
  display_name = "[AI] Clave Ocabra manual"
  description  = "Solo se usa si arriba elegiste 'Usar mi propia clave'."
  type         = "string"
  default      = ""
  order        = 61
  mutable      = true
}

data "coder_parameter" "hermes_workdir" {
  name         = "05_hermes_workdir"
  display_name = "[Hermes] Directorio de trabajo"
  description  = "Directorio desde el que opera el agente (terminal.cwd)."
  type         = "string"
  default      = "/home/coder/Projects"
  mutable      = true
}

data "coder_parameter" "hermes_default_model" {
  name         = "05_hermes_default_model"
  display_name = "[Hermes] Modelo por defecto"
  description  = "Modelo por defecto de Hermes. 'auto' usa recomendado-sota de Ocabra (o, si no existe, el de mayor capacidad descubierto); también admite provider/model."
  type         = "string"
  default      = "auto"
  mutable      = true
}

data "coder_parameter" "telegram_bot_token" {
  name         = "07_telegram_bot_token"
  display_name = "[Telegram] Token del bot (opcional)"
  description  = "Token de @BotFather. Si lo rellenas, Hermes queda conectado a ese bot de Telegram. Se guarda en ~/.hermes/.env (permisos 600)."
  type         = "string"
  default      = ""
  mutable      = true
}

data "coder_parameter" "telegram_allowed_users" {
  name         = "08_telegram_allowed_users"
  display_name = "[Telegram] IDs de usuario permitidos"
  description  = "IDs numéricos de Telegram separados por comas (los da @userinfobot). Vacío: quien escriba al bot recibe un código y lo apruebas con 'hermes pairing approve telegram <CODIGO>'."
  type         = "string"
  default      = ""
  mutable      = true
}

locals {
  username                   = data.coder_workspace_owner.me.name
  workspace_image            = "ghcr.io/makespacemadrid/coder-mks-developer-cli:latest"
  ocabra_endpoint_base_url   = trimspace(var.ocabra_endpoint_base_url)
  ocabra_key                 = trimspace(var.ocabra_key)
  openai_base_url            = local.ocabra_endpoint_base_url
  ocabra_key_mode            = data.coder_parameter.ocabra_key_mode.value
  ocabra_key_value           = trimspace(data.coder_parameter.ocabra_key_value.value)
  openai_api_key             = local.ocabra_key_mode == "manual" ? local.ocabra_key_value : ""
  auto_provision_ocabra_key  = local.ocabra_key_mode == "auto"
  hermes_workdir              = trimspace(data.coder_parameter.hermes_workdir.value)
  hermes_workdir_resolved     = local.hermes_workdir != "" ? local.hermes_workdir : "/home/coder/Projects"
  hermes_default_model        = trimspace(data.coder_parameter.hermes_default_model.value)
  llm_model_sync_script       = file("${path.module}/sync_llm_models.py")
  loopback_proxy_script       = file("${path.module}/loopback_proxy.mjs")
  assistant_persona           = file("${path.module}/assistant_persona.md")
}

provider "docker" {
  host = var.docker_socket != "" ? var.docker_socket : null
}

data "coder_provisioner" "me" {}
data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

resource "coder_agent" "main" {
  arch = data.coder_provisioner.me.arch
  os   = "linux"

  # Sin escritorio ni IDE instalado en este template: solo tiene sentido el
  # acceso por terminal/SSH, no el botón de VS Code Desktop.
  display_apps {
    vscode          = false
    vscode_insiders = false
  }

  startup_script = <<-EOT
    set -e

    # Asegurar /home/coder como HOME efectivo incluso si se ejecuta como root
    sudo mkdir -p /home/coder
    sudo chown "$USER:$USER" /home/coder || true

    mkdir -p /home/coder/.local/bin
    if [ ! -f /home/coder/.profile ]; then
      echo '# ~/.profile: executed by the command interpreter for login shells.' > /home/coder/.profile
      echo 'if [ -n "$BASH_VERSION" ]; then' >> /home/coder/.profile
      echo '    if [ -f "$HOME/.bashrc" ]; then' >> /home/coder/.profile
      echo '        . "$HOME/.bashrc"' >> /home/coder/.profile
      echo '    fi' >> /home/coder/.profile
      echo 'fi' >> /home/coder/.profile
    fi
    if ! grep -q "/.local/bin" /home/coder/.profile 2>/dev/null; then
      echo 'export PATH="$HOME/.local/bin:$PATH"' >> /home/coder/.profile
    fi
    if ! grep -q "/.local/bin" /home/coder/.bashrc 2>/dev/null; then
      echo 'export PATH="$HOME/.local/bin:$PATH"' >> /home/coder/.bashrc
    fi
    export PATH="$HOME/.local/bin:$PATH"

    mkdir -p ~/Projects

    # Hermes: instalación oficial no interactiva (si hace falta). Sin
    # --skip-computer-use, instalaría ademas el driver de automatizacion de
    # escritorio (cua-driver), que no sirve de nada sin sesion grafica.
    if ! command -v hermes >/dev/null 2>&1; then
      echo ">> Installing Hermes Agent (official installer)..."
      if ! curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash -s -- --non-interactive --skip-computer-use; then
        echo "WARN: instalación de Hermes falló. Revisa red/permisos y relanza el workspace." >&2
      fi
      export PATH="$HOME/.local/bin:$PATH"
    fi

    # Base URL OpenAI-compatible de Ocabra (vale para clave auto y manual).
    OCABRA_BASE_URL="$${OCABRA_BASE_URL:-$${OCABRA_ENDPOINT_BASE_URL:-}}"
    case "$OCABRA_BASE_URL" in */v1|"") ;; *) OCABRA_BASE_URL="$${OCABRA_BASE_URL%/}/v1" ;; esac
    export OCABRA_BASE_URL

    # Autoprovisionar clave Ocabra para Hermes si está habilitado
    auto_flag="$${AUTO_PROVISION_OCABRA_API_KEY:-true}"
    if printf '%s' "$auto_flag" | grep -Eq '^(1|true|TRUE|yes|on)$'; then
      if [ -z "$${OCABRA_API_KEY:-}" ]; then
        if [ -z "$${OCABRA_KEY:-}" ] || [ -z "$${OCABRA_ENDPOINT_BASE_URL:-}" ]; then
          echo "OCABRA_KEY no configurado; omitiendo autoprovision de key" >&2
        else
          workspace_slug="$(printf '%s' "$${CODER_WORKSPACE_NAME:-workspace}" | tr -cs '[:alnum:]._-' '-')"; email_slug="$(printf '%s' "$${CODER_USER_EMAIL:-unknown}" | tr -cs '[:alnum:]._-' '-')"; alias="coder-$${workspace_slug}-$${email_slug}-$(tr -dc 0-9 </dev/urandom 2>/dev/null | head -c 8 | sed 's/^$/00000000/')"
          payload=$(printf '{"name":"%s","expires_in_days":30}' "$alias")
          resp=$(curl -fsSL -X POST "$${OCABRA_ENDPOINT_BASE_URL%/}/ocabra/auth/keys" -H "Authorization: Bearer $${OCABRA_KEY:-}" -H "Content-Type: application/json" -d "$payload" 2>/dev/null || true)
          key=$(printf '%s' "$resp" | python3 -c 'import sys,json;x=json.load(sys.stdin);d=x if isinstance(x,dict) else {};dd=d.get("data") if isinstance(d.get("data"),dict) else {};print(d.get("key") or d.get("api_key") or d.get("apiKey") or dd.get("key") or dd.get("api_key") or dd.get("apiKey") or "")' 2>/dev/null || true)
          if [ -n "$key" ]; then
            OCABRA_API_KEY="$key"
            export OCABRA_API_KEY
          fi
        fi
      fi
    fi

    if command -v hermes >/dev/null 2>&1; then
      mkdir -p "$HOME/.hermes"
      touch "$HOME/.hermes/.env"
      chmod 600 "$HOME/.hermes/.env"
      if [ -n "$${OCABRA_API_KEY:-}" ]; then
        grep -v '^OCABRA_API_KEY=' "$HOME/.hermes/.env" > "$HOME/.hermes/.env.tmp" 2>/dev/null || true
        printf 'OCABRA_API_KEY=%s\n' "$OCABRA_API_KEY" >> "$HOME/.hermes/.env.tmp"
        mv "$HOME/.hermes/.env.tmp" "$HOME/.hermes/.env"
        hermes config set providers.ocabra.type openai >/dev/null 2>&1 || true
        hermes config set providers.ocabra.base_url "$${OCABRA_BASE_URL:-}" >/dev/null 2>&1 || true
        hermes config set providers.ocabra.key_env OCABRA_API_KEY >/dev/null 2>&1 || true
      fi
      # Instala el mismo descubridor de modelos vivos que usan Developer/OpenClaw
      # para elegir "el mejor modelo disponible" sin mantener un roster estático.
      mkdir -p "$HOME/.local/bin"
      cat > "$HOME/.local/bin/sync-llm-models" <<'PY'
${local.llm_model_sync_script}
PY
      chmod 0755 "$HOME/.local/bin/sync-llm-models"

      # Declarar en config.yaml todo el catálogo de chat de Ocabra (con su
      # ventana de contexto). Hermes también consulta /v1/models en vivo, pero
      # al abrir el selector usa solo su caché en disco: en un workspace recién
      # creado no existe y el selector enseñaba únicamente el modelo por
      # defecto. Un mapping {id: {...}} cuenta como metadatos, no como lista
      # cerrada, así que modelos nuevos de Ocabra siguen apareciendo.
      # Se pasa como JSON entero porque las ids llevan '.', ':' y '/'.
      ocabra_catalog_json=""
      if [ -n "$${OCABRA_API_KEY:-}" ] && [ -n "$${OCABRA_BASE_URL:-}" ]; then
        ocabra_catalog_json=$("$HOME/.local/bin/sync-llm-models" --openclaw-provider ocabra 2>/dev/null || true)
      fi

      target_model="$${HERMES_DEFAULT_MODEL:-auto}"
      if [ "$target_model" = "auto" ]; then
        target_model=$("$HOME/.local/bin/sync-llm-models" --best-model 2>/dev/null || true)
      fi
      if [ -n "$target_model" ] && ! printf '%s' "$target_model" | grep -q '/'; then
        target_model="ocabra/$target_model"
      fi

      if [ -n "$ocabra_catalog_json" ]; then
        models_json=$(CATALOG="$ocabra_catalog_json" TARGET="$target_model" python3 - <<'PY'
import json, os
models = {}
try:
    catalog = json.loads(os.environ.get("CATALOG") or "{}")
except Exception:
    catalog = {}
for m in catalog.get("models", []):
    if not isinstance(m, dict) or not isinstance(m.get("id"), str):
        continue
    entry = {"name": m["id"]}
    if m.get("contextWindow"):
        entry["context_length"] = int(m["contextWindow"])
    models[m["id"]] = entry
target = os.environ.get("TARGET", "")
if target.startswith("ocabra/") and target[len("ocabra/"):] not in models:
    models[target[len("ocabra/"):]] = {"name": target[len("ocabra/"):]}
print(json.dumps(models, separators=(",", ":")) if models else "")
PY
)
        if [ -n "$models_json" ]; then
          hermes config set providers.ocabra.models "$models_json" >/dev/null 2>&1 || echo "WARN: no se pudo declarar el catálogo de Ocabra en Hermes." >&2
        fi
      fi

      if [ -n "$target_model" ]; then
        target_provider="$${target_model%%/*}"
        target_model_id="$${target_model#*/}"
        if [ "$target_provider" = "ocabra" ] && [ -n "$${OCABRA_BASE_URL:-}" ]; then
          # Explícito: "config set model ocabra/<id>" deja provider=auto y la
          # base_url de OpenRouter hasta que Hermes lo normaliza.
          hermes config set model.provider ocabra >/dev/null 2>&1 || true
          hermes config set model.default "$target_model_id" >/dev/null 2>&1 || true
          hermes config set model.base_url "$OCABRA_BASE_URL" >/dev/null 2>&1 || true
          hermes config set model.api_mode chat_completions >/dev/null 2>&1 || true
          hermes config set model.key_env OCABRA_API_KEY >/dev/null 2>&1 || true
        elif hermes config get "providers.$target_provider" >/dev/null 2>&1; then
          hermes config set model "$target_model" >/dev/null 2>&1 || true
        else
          echo "WARN: modelo por defecto '$target_model' omitido: provider '$target_provider' no configurado." >&2
        fi
      fi

      hermes config set terminal.cwd "$${HERMES_WORKDIR:-$HOME/Projects}" >/dev/null 2>&1 || true

      # --- Preconfiguración MakeSpace (idempotente; se reaplica en cada arranque) ---
      # Idioma y zona horaria. El idioma del dashboard web no se puede fijar:
      # lo guarda cada navegador (selector de idioma de la UI).
      hermes config set display.language es >/dev/null 2>&1 || true
      hermes config set stt.language es >/dev/null 2>&1 || true
      hermes config set timezone Europe/Madrid >/dev/null 2>&1 || true
      # Banner "Help improve Hermes?" respondido como "No thanks" (offer_version
      # es necesario: sin él vuelve a preguntar).
      hermes config set telemetry.shared_metrics '{"enabled":false,"send":false,"offer_version":2}' >/dev/null 2>&1 || true

      if [ -n "$${OCABRA_API_KEY:-}" ] && [ -n "$${OCABRA_BASE_URL:-}" ]; then
        # Voz con Ocabra. "$${OCABRA_API_KEY}" va literal: Hermes lo expande al
        # leer la config (la clave vive en ~/.hermes/.env). En STT la clave debe
        # ir en stt.openai.api_key; si no, ignora base_url y va a api.openai.com.
        hermes config set tts.provider openai >/dev/null 2>&1 || true
        hermes config set tts.openai "{\"model\":\"recomendado-tts\",\"voice\":\"es_MX-claude-high\",\"base_url\":\"$OCABRA_BASE_URL\",\"api_key\":\"\$${OCABRA_API_KEY}\"}" >/dev/null 2>&1 || true
        hermes config set stt.provider openai >/dev/null 2>&1 || true
        hermes config set stt.openai "{\"model\":\"recomendado-stt\",\"base_url\":\"$OCABRA_BASE_URL\",\"api_key\":\"\$${OCABRA_API_KEY}\"}" >/dev/null 2>&1 || true

        # Memoria con embeddings de Ocabra: plugin "holographic" del catálogo
        # (la memoria de serie de Hermes es solo texto). Se instala una vez; si
        # no hay red se reintenta en el próximo arranque. Sin rerank: el de
        # holographic no envía clave y Ocabra exige una.
        if [ "$(hermes config get memory.provider 2>/dev/null | tail -1)" != "holographic" ]; then
          hermes plugins install holographic --yes-deps --enable </dev/null >/dev/null 2>&1 || echo "WARN: no se pudo instalar el plugin de memoria holographic; se reintentará." >&2
        fi
        hermes config set plugins.hermes-memory-store "{\"embeddings\":\"on\",\"embedding_url\":\"$OCABRA_BASE_URL\",\"embedding_model\":\"recomendado-embedding\",\"embedding_key_env\":\"OCABRA_API_KEY\",\"embedding_timeout\":20}" >/dev/null 2>&1 || true
      fi

      # Personalidad: SOUL.md solo si falta, está vacío o es el texto por
      # defecto de Hermes (detección del propio Hermes); nunca pisa uno editado.
      HH="$HOME/.hermes"
      soul_py=$(ls -d "$HH"/tools/python-3*/bin/python3 2>/dev/null | head -1)
      if "$${soul_py:-python3}" -I - "$HH/SOUL.md" "$HH/hermes-agent" >/dev/null 2>&1 <<'PY'
import sys, pathlib
soul, repo = pathlib.Path(sys.argv[1]), sys.argv[2]
sys.path.insert(0, repo)
from hermes_cli.default_soul import DEFAULT_SOUL_MD, is_legacy_template_soul, _normalize_soul
if not soul.exists():
    sys.exit(0)
text = soul.read_text(encoding="utf-8", errors="replace")
norm = _normalize_soul(text)
sys.exit(0 if (not norm or norm == _normalize_soul(DEFAULT_SOUL_MD) or is_legacy_template_soul(text)) else 1)
PY
      then
        cat > "$HH/SOUL.md" <<'SOUL'
Eres Hermes, el asistente de este workspace.

${local.assistant_persona}
SOUL
      fi

      # Telegram: el token del parámetro va a ~/.hermes/.env ("config set" con
      # clave en MAYÚSCULAS escribe ahí). Sin lista de IDs, Hermes usa
      # emparejamiento: el desconocido recibe un código para aprobar.
      if [ -n "$${TELEGRAM_BOT_TOKEN:-}" ]; then
        hermes config set TELEGRAM_BOT_TOKEN "$TELEGRAM_BOT_TOKEN" >/dev/null 2>&1 || true
        if [ -n "$${TELEGRAM_ALLOWED_USERS:-}" ]; then
          hermes config set TELEGRAM_ALLOWED_USERS "$TELEGRAM_ALLOWED_USERS" >/dev/null 2>&1 || true
        else
          sed -i '/^TELEGRAM_ALLOWED_USERS=/d' "$HOME/.hermes/.env" 2>/dev/null || true
        fi
      else
        sed -i '/^TELEGRAM_BOT_TOKEN=/d; /^TELEGRAM_ALLOWED_USERS=/d' "$HOME/.hermes/.env" 2>/dev/null || true
      fi

      # El dashboard de Hermes rechaza cualquier cabecera Host que no sea
      # exactamente la de bind (defensa anti DNS-rebinding, sin lista de hosts
      # de confianza configurable a dia de hoy: issues #74664/#34390/#10567 en
      # NousResearch/hermes-agent) y sus WebSockets (/api/ws, /api/events,
      # /api/pty) exigen ademas un Origin de localhost/127.0.0.1. Bindear a
      # 0.0.0.0 tampoco sirve: exige entonces OAuth/OIDC completo. En vez de
      # eso, loopback-proxy (Node, ya viene en la imagen; antes era un nginx
      # instalado con apt en cada arranque) reescribe Host y Origin antes de
      # reenviar a 127.0.0.1:9119, dejando el dashboard en loopback (sin
      # login). El token de sesion embebido en la pagina
      # (window.__HERMES_SESSION_TOKEN__) viaja como ?token= en el WebSocket
      # y no se ve afectado por la reescritura.
      cat > "$HOME/.local/bin/loopback-proxy" <<'JS'
${local.loopback_proxy_script}
JS
      chmod 0755 "$HOME/.local/bin/loopback-proxy"

      # Persistir configuración para invocaciones manuales posteriores
      mkdir -p "$HOME/.local/state/hermes"
      touch "$HOME/.local/state/hermes/hermes-dashboard.log"
      cat > "$HOME/.local/bin/start-hermes-dashboard" <<'HERMESSTART'
#!/usr/bin/env bash
# Arranca dashboard (:9119) y proxy de la app de Coder (:19119) bajo un bucle
# de supervisión: si alguno muere, vuelve a arrancar solo.
set -euo pipefail
STATE_DIR="$HOME/.local/state/hermes"
LOG_FILE="$STATE_DIR/hermes-dashboard.log"
PROXY_LOG="$STATE_DIR/ui-proxy.log"
# PIDs en /tmp: el contenedor se recrea en cada arranque y un PID guardado en
# el HOME persistente podría coincidir con otro proceso.
RUN_DIR="/tmp/hermes-run"
mkdir -p "$STATE_DIR" "$RUN_DIR"

alive() { [ -f "$1" ] && kill -0 "$(cat "$1")" 2>/dev/null; }

if ! alive "$RUN_DIR/ui-proxy.pid"; then
  nohup setsid bash -c 'while :; do loopback-proxy 19119 9119; echo "loopback-proxy salió ($?); reinicio en 3s"; sleep 3; done' >> "$PROXY_LOG" 2>&1 < /dev/null &
  echo $! > "$RUN_DIR/ui-proxy.pid"
fi

# Gateway de mensajería (Telegram...): "hermes dashboard" no lo arranca. Solo
# si hay token. El botón "restart" del dashboard sale con rc=75 y el bucle lo
# vuelve a levantar.
if grep -q '^TELEGRAM_BOT_TOKEN=.' "$HOME/.hermes/.env" 2>/dev/null && ! alive "$RUN_DIR/gateway.pid"; then
  nohup setsid bash -c 'while :; do hermes gateway run --replace --external-supervisor; echo "hermes gateway salió ($?); reinicio en 5s"; sleep 5; done' >> "$STATE_DIR/hermes-gateway.log" 2>&1 < /dev/null &
  echo $! > "$RUN_DIR/gateway.pid"
fi

if ! alive "$RUN_DIR/dashboard.pid"; then
  nohup setsid bash -c 'while :; do hermes dashboard --no-open; echo "hermes dashboard salió ($?); reinicio en 5s"; sleep 5; done' >> "$LOG_FILE" 2>&1 < /dev/null &
  echo $! > "$RUN_DIR/dashboard.pid"
fi

for _ in $(seq 1 90); do
  if curl -fsS --max-time 1 "http://127.0.0.1:19119/" >/dev/null 2>&1; then
    exit 0
  fi
  sleep 1
done

echo "Hermes dashboard no respondió en :19119 tras 90s. Revisa $LOG_FILE y $PROXY_LOG" >&2
exit 1
HERMESSTART
      chmod +x "$HOME/.local/bin/start-hermes-dashboard"

      cat > "$HOME/.local/bin/stop-hermes-dashboard" <<'HERMESSTOP'
#!/usr/bin/env bash
for name in dashboard ui-proxy gateway; do
  pid_file="/tmp/hermes-run/$name.pid"
  if [ -f "$pid_file" ]; then
    kill -- "-$(cat "$pid_file")" 2>/dev/null || true
    rm -f "$pid_file"
  fi
done
echo "Hermes dashboard parado."
HERMESSTOP
      chmod +x "$HOME/.local/bin/stop-hermes-dashboard"

      echo ">> Arrancando Hermes dashboard..."
      if ! "$HOME/.local/bin/start-hermes-dashboard"; then
        echo "WARN: no se pudo arrancar el dashboard de Hermes. Revisa ~/.local/state/hermes/hermes-dashboard.log" >&2
      fi
    fi
  EOT

  env = {
    GIT_AUTHOR_NAME                = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
    GIT_AUTHOR_EMAIL               = data.coder_workspace_owner.me.email
    GIT_COMMITTER_NAME             = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
    GIT_COMMITTER_EMAIL            = data.coder_workspace_owner.me.email
    HOME                           = "/home/coder"
    OCABRA_ENDPOINT_BASE_URL       = local.ocabra_endpoint_base_url
    OCABRA_KEY                     = local.ocabra_key
    AUTO_PROVISION_OCABRA_API_KEY  = tostring(local.auto_provision_ocabra_key)
    CODER_USER_EMAIL               = data.coder_workspace_owner.me.email
    CODER_WORKSPACE_NAME           = data.coder_workspace.me.name
    HERMES_WORKDIR                 = local.hermes_workdir_resolved
    HERMES_DEFAULT_MODEL           = local.hermes_default_model
    TELEGRAM_BOT_TOKEN             = trimspace(data.coder_parameter.telegram_bot_token.value)
    TELEGRAM_ALLOWED_USERS         = replace(trimspace(data.coder_parameter.telegram_allowed_users.value), " ", "")
    # Solo con "Usar mi propia clave"; en modo auto va vacío y se autoprovisiona.
    OCABRA_API_KEY                 = local.openai_api_key
  }
}

resource "coder_app" "hermes_dashboard" {
  count        = data.coder_workspace.me.start_count
  agent_id     = coder_agent.main.id
  slug         = "hermes-dashboard"
  display_name = "Hermes Dashboard"
  icon         = "/icon/terminal.svg"
  url          = "http://localhost:19119/"
  subdomain    = true
  open_in      = "tab"

  healthcheck {
    url       = "http://localhost:19119/"
    interval  = 5
    threshold = 60
  }
}

resource "docker_volume" "home_volume" {
  name = "coder-${data.coder_workspace.me.id}-home"

  lifecycle {
    ignore_changes = all
  }

  labels {
    label = "coder.owner"
    value = data.coder_workspace_owner.me.name
  }
  labels {
    label = "coder.owner_id"
    value = data.coder_workspace_owner.me.id
  }
  labels {
    label = "coder.workspace_id"
    value = data.coder_workspace.me.id
  }
  labels {
    label = "coder.workspace_name_at_creation"
    value = data.coder_workspace.me.name
  }
}

resource "docker_container" "workspace" {
  # count (no must_run: must_run=false en este provider significa "no
  # forzar que siga corriendo", NO "pararlo"). Con count el contenedor se
  # destruye de verdad al parar y se recrea al arrancar; los volumes ya
  # tienen ignore_changes=all para sobrevivir a eso.
  count   = data.coder_workspace.me.start_count
  image   = local.workspace_image
  restart = "unless-stopped"

  name     = "coder-${data.coder_workspace_owner.me.name}-${lower(data.coder_workspace.me.name)}"
  hostname = data.coder_workspace.me.name

  user = "coder"

  entrypoint = [
    "sh",
    "-c",
    <<-EOT
      set -e
      ${replace(coder_agent.main.init_script, "/localhost|127\\.0\\.0\\.1/", "host.docker.internal")}
    EOT
  ]

  env = [
    "CODER_AGENT_TOKEN=${coder_agent.main.token}",
    "TZ=Europe/Madrid"
  ]

  shm_size = 2 * 1024 * 1024 * 1024

  volumes {
    container_path = "/home/coder"
    volume_name    = docker_volume.home_volume.name
  }

  host {
    host = "host.docker.internal"
    ip   = "host-gateway"
  }

  labels {
    label = "coder.owner"
    value = data.coder_workspace_owner.me.name
  }
  labels {
    label = "coder.owner_id"
    value = data.coder_workspace_owner.me.id
  }
  labels {
    label = "coder.workspace_id"
    value = data.coder_workspace.me.id
  }
  labels {
    label = "coder.workspace_name"
    value = data.coder_workspace.me.name
  }
  labels {
    label = "com.centurylinklabs.watchtower.enable"
    value = "true"
  }
  labels {
    label = "com.centurylinklabs.watchtower.scope"
    value = "coder-workspaces"
  }
}
