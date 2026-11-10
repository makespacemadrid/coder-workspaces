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

data "coder_parameter" "openclaw_autostart" {
  name         = "05_openclaw_autostart"
  display_name = "[OpenClaw] Auto-iniciar servicio"
  description  = "Intenta arrancar OpenClaw al iniciar el workspace (sin fallar si no esta instalado)."
  type         = "bool"
  default      = true
  mutable      = true
}

data "coder_parameter" "openclaw_workdir" {
  name         = "05_openclaw_workdir"
  display_name = "[OpenClaw] Directorio de trabajo"
  description  = "Directorio desde el que se ejecuta OpenClaw."
  type         = "string"
  default      = "/home/coder/Projects"
  mutable      = true
}

data "coder_parameter" "openclaw_default_model" {
  name         = "05_openclaw_default_model"
  display_name = "[OpenClaw] Modelo por defecto"
  description  = "Modelo por defecto de OpenClaw. 'auto' usa recomendado-sota de Ocabra (o, si no existe, el de mayor capacidad descubierto); también admite provider/model o vacío."
  type         = "string"
  default      = "auto"
  mutable      = true
}

data "coder_parameter" "openclaw_public_gateway" {
  name         = "06_openclaw_public_gateway"
  display_name = "[OpenClaw] Acceso desde el móvil"
  description  = "Publica el gateway en Internet (app de Coder pública) para conectar la app móvil de OpenClaw con el QR de 'Conectar móvil'. Queda protegido por su token y el emparejamiento de dispositivos. Desactivado: solo accesible a través de Coder."
  type         = "bool"
  default      = false
  mutable      = true
}

data "coder_parameter" "telegram_bot_token" {
  name         = "07_telegram_bot_token"
  display_name = "[Telegram] Token del bot (opcional)"
  description  = "Token de @BotFather. Si lo rellenas, OpenClaw queda conectado a ese bot de Telegram. Se guarda en ~/.openclaw/.env (permisos 600)."
  type         = "string"
  default      = ""
  mutable      = true
}

data "coder_parameter" "telegram_allowed_users" {
  name         = "08_telegram_allowed_users"
  display_name = "[Telegram] IDs de usuario permitidos"
  description  = "IDs numéricos de Telegram separados por comas (los da @userinfobot). Vacío: quien escriba al bot recibe un código y lo apruebas con 'openclaw pairing approve telegram <CODIGO>' (el primero aprobado queda como owner)."
  type         = "string"
  default      = ""
  mutable      = true
}

locals {
  username                     = data.coder_workspace_owner.me.name
  workspace_image              = "ghcr.io/makespacemadrid/coder-mks-developer-cli:latest"
  home_mount_host_path         = ""
  host_mount_path              = ""
  host_mount_uid               = "1000"
  projects_mount_host_path     = ""
  ocabra_endpoint_base_url     = trimspace(var.ocabra_endpoint_base_url)
  ocabra_key                   = trimspace(var.ocabra_key)
  # Vacío a propósito (igual que Developer): el startup_script deriva la URL
  # OpenAI-compatible de OCABRA_ENDPOINT_BASE_URL añadiendo /v1. Si se pasaba
  # la URL tal cual, ese paso se saltaba y el chat iba a <host>/chat/completions
  # (404), aunque el descubrimiento de modelos sí funcionaba.
  openai_base_url              = ""
  ocabra_key_mode               = data.coder_parameter.ocabra_key_mode.value
  ocabra_key_value               = trimspace(data.coder_parameter.ocabra_key_value.value)
  openai_api_key               = local.ocabra_key_mode == "manual" ? local.ocabra_key_value : ""
  auto_provision_ocabra_key    = local.ocabra_key_mode == "auto"
  openclaw_autostart           = data.coder_parameter.openclaw_autostart.value
  openclaw_port                = 3333
  # Puerto del proxy loopback que publica la app de Coder (ver loopback_proxy.mjs).
  openclaw_ui_port             = 13333
  # Subpath de la Control UI (gateway.controlUi.basePath); ver startup_script.
  openclaw_ui_base_path        = "/openclaw"
  # Página "Conectar móvil" (QR de emparejamiento, pair_page.mjs).
  openclaw_pair_page_port      = 13334
  # URL del gateway que va en el QR para la app móvil:
  # - con "[OpenClaw] Acceso desde el móvil": app pública de Coder (oculta)
  #   "openclaw-gateway" que apunta al gateway;
  # - sin él: puerto compartido de Coder (<puerto>--<agente>--<ws>--<owner>),
  #   por si el usuario lo pone en "Public" a mano desde el panel Ports.
  coder_access_host            = split("/", data.coder_workspace.me.access_url)[2]
  openclaw_public_gateway      = data.coder_parameter.openclaw_public_gateway.value
  openclaw_public_ws_url = (local.openclaw_public_gateway
    ? "wss://openclaw-gateway--${lower(data.coder_workspace.me.name)}--${lower(data.coder_workspace_owner.me.name)}.${local.coder_access_host}"
    : "wss://${local.openclaw_port}--main--${lower(data.coder_workspace.me.name)}--${lower(data.coder_workspace_owner.me.name)}.${local.coder_access_host}"
  )
  pair_page_script             = file("${path.module}/pair_page.mjs")
  openclaw_gateway_token       = random_password.openclaw_gateway_token.result
  openclaw_workdir             = trimspace(data.coder_parameter.openclaw_workdir.value)
  openclaw_workdir_resolved    = local.openclaw_workdir != "" ? local.openclaw_workdir : "/home/coder/Projects"
  openclaw_default_model       = trimspace(data.coder_parameter.openclaw_default_model.value)
  llm_model_sync_script        = file("${path.module}/sync_llm_models.py")
  loopback_proxy_script        = file("${path.module}/loopback_proxy.mjs")
  assistant_persona            = file("${path.module}/assistant_persona.md")
}

resource "random_password" "openclaw_gateway_token" {
  length  = 48
  special = false
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

    # Configurar PATH para .local/bin (siempre útil)
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

    mkdir -p ~/Projects

    # Asegurar permisos de pipx para el usuario actual
    sudo mkdir -p /opt/pipx /opt/pipx/bin
    sudo chown -R "$USER:$USER" /opt/pipx || true

    # Inicializar /etc/skel la primera vez
    if [ ! -f ~/.init_done ]; then
      cp -rT /etc/skel ~ || true
      touch ~/.init_done
    fi

    # Autoprovisionar clave Ocabra para OpenClaw si está habilitado
    auto_flag="$${AUTO_PROVISION_OCABRA_API_KEY:-true}"
    if [ -z "$${OPENCODE_PROVIDER_URL:-}" ] && [ -n "$${OCABRA_ENDPOINT_BASE_URL:-}" ]; then
      OCABRA_OPENAI_BASE_URL="$${OCABRA_ENDPOINT_BASE_URL%/}"
      case "$OCABRA_OPENAI_BASE_URL" in */v1) ;; *) OCABRA_OPENAI_BASE_URL="$OCABRA_OPENAI_BASE_URL/v1" ;; esac
      OPENCODE_PROVIDER_URL="$OCABRA_OPENAI_BASE_URL"
      export OPENCODE_PROVIDER_URL
    fi
    if printf '%s' "$auto_flag" | grep -Eq '^(1|true|TRUE|yes|on)$'; then
      OCABRA_BASE_URL="$${OCABRA_BASE_URL:-$OPENCODE_PROVIDER_URL}"
      export OCABRA_BASE_URL
      payload=""
      if [ -z "$${OPENCODE_API_KEY:-}" ]; then
        KEY_ENDPOINT="$${OCABRA_ENDPOINT_BASE_URL%/}/ocabra/auth/keys"
        if [ -z "$${OCABRA_KEY:-}" ] || [ -z "$${OCABRA_ENDPOINT_BASE_URL:-}" ]; then
          echo "OCABRA_KEY no configurado; omitiendo autoprovision de key" >&2
        else
          workspace_slug="$(printf '%s' "$${CODER_WORKSPACE_NAME:-workspace}" | tr -cs '[:alnum:]._-' '-')"; email_slug="$(printf '%s' "$${CODER_USER_EMAIL:-unknown}" | tr -cs '[:alnum:]._-' '-')"; alias="coder-$${workspace_slug}-$${email_slug}-$(tr -dc 0-9 </dev/urandom 2>/dev/null | head -c 8 | sed 's/^$/00000000/')"
          payload=$(printf '{"name":"%s","expires_in_days":30}' "$alias")
          resp=$(curl -fsSL -X POST "$KEY_ENDPOINT" -H "Authorization: Bearer $${OCABRA_KEY:-}" -H "Content-Type: application/json" -d "$payload" 2>/dev/null || true)
          key=$(printf '%s' "$resp" | python3 -c 'import sys,json;x=json.load(sys.stdin);d=x if isinstance(x,dict) else {};dd=d.get("data") if isinstance(d.get("data"),dict) else {};print(d.get("key") or d.get("api_key") or d.get("apiKey") or dd.get("key") or dd.get("api_key") or dd.get("apiKey") or "")' 2>/dev/null || true)
          if [ -n "$key" ]; then
            OPENCODE_API_KEY="$key"
            export OPENCODE_API_KEY
            OCABRA_API_KEY="$key"
            export OCABRA_API_KEY
          fi
        fi
      fi
      if [ -n "$${OPENCODE_API_KEY:-}" ]; then
        export OPENCODE_API_KEY
        OCABRA_API_KEY="$${OCABRA_API_KEY:-$OPENCODE_API_KEY}"
        export OCABRA_API_KEY
      fi
    fi
    # Descubridor de modelos vivos (Ocabra) que usa OpenClaw.
    mkdir -p /home/coder/.local/bin
    cat > /home/coder/.local/bin/sync-llm-models <<'PY'
${local.llm_model_sync_script}
PY
    chmod 0755 /home/coder/.local/bin/sync-llm-models

    # Propagar variables a nuevas shells interactivas
    if [ -n "$${OPENCODE_PROVIDER_URL:-}" ]; then
      OCABRA_BASE_URL="$${OCABRA_BASE_URL:-$OPENCODE_PROVIDER_URL}"
      export OCABRA_BASE_URL
      OPENAI_BASE_URL="$OPENCODE_PROVIDER_URL"
      export OPENAI_BASE_URL
      if ! grep -q "OCABRA_BASE_URL=" ~/.bashrc 2>/dev/null; then
        echo "export OCABRA_BASE_URL=\"$OCABRA_BASE_URL\"" >> ~/.bashrc
      fi
      if ! grep -q "OPENAI_BASE_URL=" ~/.bashrc 2>/dev/null; then
        echo "export OPENAI_BASE_URL=\"$OPENAI_BASE_URL\"" >> ~/.bashrc
      fi
    fi
    if [ -n "$${OPENCODE_API_KEY:-}" ]; then
      OCABRA_API_KEY="$${OCABRA_API_KEY:-$OPENCODE_API_KEY}"
      export OCABRA_API_KEY
      OPENAI_API_KEY="$${OPENAI_API_KEY:-$OPENCODE_API_KEY}"
      export OPENAI_API_KEY
      if ! grep -q "OCABRA_API_KEY=" ~/.bashrc 2>/dev/null; then
        echo "export OCABRA_API_KEY=\"$OCABRA_API_KEY\"" >> ~/.bashrc
      fi
      if ! grep -q "OPENAI_API_KEY=" ~/.bashrc 2>/dev/null; then
        echo "export OPENAI_API_KEY=\"$OPENAI_API_KEY\"" >> ~/.bashrc
      fi
      # OpenClaw loads ~/.openclaw/.env automatically; persist the provisioned key there.
      mkdir -p "$HOME/.openclaw"
      touch "$HOME/.openclaw/.env"
      chmod 600 "$HOME/.openclaw/.env"
      grep -v '^OPENAI_API_KEY=' "$HOME/.openclaw/.env" > "$HOME/.openclaw/.env.tmp" || true
      printf 'OPENAI_API_KEY=%s\n' "$OPENAI_API_KEY" >> "$HOME/.openclaw/.env.tmp"
      if [ -n "$${OPENAI_BASE_URL:-}" ]; then
        grep -v '^OPENAI_BASE_URL=' "$HOME/.openclaw/.env.tmp" > "$HOME/.openclaw/.env.tmp2" || true
        printf 'OPENAI_BASE_URL=%s\n' "$OPENAI_BASE_URL" >> "$HOME/.openclaw/.env.tmp2"
        mv "$HOME/.openclaw/.env.tmp2" "$HOME/.openclaw/.env.tmp"
      fi
      mv "$HOME/.openclaw/.env.tmp" "$HOME/.openclaw/.env"
    fi
    # OpenClaw requiere Node >= 24.22.1 (o >= 26.12.1)
    ensure_node24=false
    if ! command -v node >/dev/null 2>&1; then
      ensure_node24=true
    else
      node_ver=$(node -p 'process.versions.node' 2>/dev/null || echo "0.0.0")
      min_node_ver="24.22.1"
      if [ "$(printf '%s\n%s\n' "$min_node_ver" "$node_ver" | sort -V | head -n1)" != "$min_node_ver" ]; then
        ensure_node24=true
      fi
    fi
    if [ "$ensure_node24" = "true" ]; then
      echo ">> Installing/upgrading Node.js 24.x (required by OpenClaw)..."
      sudo apt-get update -y
      sudo DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates curl gnupg
      curl -fsSL https://deb.nodesource.com/setup_24.x | sudo -E bash -
      sudo DEBIAN_FRONTEND=noninteractive apt-get install -y nodejs
      hash -r || true
      node -v || true
    fi

    # Límites de inotify (EMFILE en watchers de OpenClaw): no son por
    # contenedor y sin privileged no se pueden cambiar desde aquí; los fija el
    # host (/etc/sysctl.d). Solo avisamos si están bajos.
    if [ "$(cat /proc/sys/fs/inotify/max_user_instances 2>/dev/null || echo 0)" -lt 1024 ]; then
      echo "WARN: fs.inotify.max_user_instances bajo en el host; OpenClaw puede dar EMFILE." >&2
    fi

    # Homebrew en HOME persistente para skills/plugins opcionales de OpenClaw.
    BREW_PREFIX="$HOME/.linuxbrew"
    BREW_BIN="$BREW_PREFIX/bin/brew"
    if [ ! -x "$BREW_BIN" ]; then
      echo ">> Installing Homebrew in $BREW_PREFIX (persistent)..."
      sudo DEBIAN_FRONTEND=noninteractive apt-get update -y || true
      sudo DEBIAN_FRONTEND=noninteractive apt-get install -y build-essential procps curl file git || true
      mkdir -p "$BREW_PREFIX"
      if [ ! -d "$BREW_PREFIX/Homebrew/.git" ]; then
        rm -rf "$BREW_PREFIX/Homebrew"
        # Best-effort: Homebrew es opcional; un fallo de red no debe tumbar el arranque.
        git clone --depth=1 https://github.com/Homebrew/brew "$BREW_PREFIX/Homebrew" || echo "WARN: no se pudo clonar Homebrew; se reintentará en el próximo arranque." >&2
      fi
      if [ -x "$BREW_PREFIX/Homebrew/bin/brew" ]; then
        mkdir -p "$BREW_PREFIX/bin"
        ln -sf ../Homebrew/bin/brew "$BREW_BIN"
      fi
    fi
    if [ -x "$BREW_BIN" ]; then
      eval "$("$BREW_BIN" shellenv)"
      export HOMEBREW_NO_AUTO_UPDATE=1
      if ! grep -q "HOMEBREW_NO_AUTO_UPDATE" /home/coder/.profile 2>/dev/null; then
        echo 'export HOMEBREW_NO_AUTO_UPDATE=1' >> /home/coder/.profile
      fi
      if ! grep -q "HOMEBREW_NO_AUTO_UPDATE" /home/coder/.bashrc 2>/dev/null; then
        echo 'export HOMEBREW_NO_AUTO_UPDATE=1' >> /home/coder/.bashrc
      fi
      if ! grep -q '\.linuxbrew/bin/brew shellenv' /home/coder/.profile 2>/dev/null; then
        echo 'eval "$($HOME/.linuxbrew/bin/brew shellenv)"' >> /home/coder/.profile
      fi
      if ! grep -q '\.linuxbrew/bin/brew shellenv' /home/coder/.bashrc 2>/dev/null; then
        echo 'eval "$($HOME/.linuxbrew/bin/brew shellenv)"' >> /home/coder/.bashrc
      fi
    fi

    # OpenClaw: instalación oficial no interactiva (si hace falta)
    export PATH="$HOME/.npm-global/bin:$HOME/.local/bin:$PATH"
    if ! grep -q "/.npm-global/bin" /home/coder/.profile 2>/dev/null; then
      echo 'export PATH="$HOME/.npm-global/bin:$HOME/.local/bin:$PATH"' >> /home/coder/.profile
    fi
    if ! grep -q "/.npm-global/bin" /home/coder/.bashrc 2>/dev/null; then
      echo 'export PATH="$HOME/.npm-global/bin:$HOME/.local/bin:$PATH"' >> /home/coder/.bashrc
    fi
    if ! command -v openclaw >/dev/null 2>&1; then
      echo ">> Installing OpenClaw (official installer)..."
      if ! OPENCLAW_NO_PROMPT=1 OPENCLAW_NO_ONBOARD=1 curl -fsSL https://openclaw.ai/install.sh | bash -s -- --no-prompt --no-onboard; then
        echo "WARN: instalación de OpenClaw falló. Revisa red/permisos y relanza el workspace." >&2
      fi
      export PATH="$HOME/.npm-global/bin:$HOME/.local/bin:$PATH"
    fi
    # No actualizar OpenClaw automáticamente en startup:
    # puede tardar mucho y bloquear el arranque del gateway/app.
    # Si necesitas actualizar, hazlo manualmente con:
    #   openclaw update --yes --no-restart

    if command -v openclaw >/dev/null 2>&1; then
      # Recuperar variables persistidas para asegurar providers incluso si
      # el entorno de proceso no trae OPENAI_* en este punto.
      if [ -f "$HOME/.openclaw/.env" ]; then
        set -a
        . "$HOME/.openclaw/.env"
        set +a
      fi
      # Errores de configuración del arranque, para diagnóstico.
      OC_CFG_LOG="$HOME/.local/state/openclaw/startup-config.log"
      mkdir -p "$(dirname "$OC_CFG_LOG")"; : > "$OC_CFG_LOG"
      # Migrar/limpiar la config antes de tocarla: con claves retiradas o
      # perfiles legacy pendientes, "openclaw config set" puede negarse.
      openclaw doctor --fix >/dev/null 2>>"$OC_CFG_LOG" || true
      openclaw config set gateway.mode local >/dev/null 2>>"$OC_CFG_LOG" || true
      openclaw config set gateway.port "$${OPENCLAW_PORT:-3333}" >/dev/null 2>>"$OC_CFG_LOG" || true
      openclaw config set gateway.auth.mode token >/dev/null 2>>"$OC_CFG_LOG" || true
      openclaw config set gateway.auth.token "$${OPENCLAW_GATEWAY_TOKEN:-}" >/dev/null 2>>"$OC_CFG_LOG" || true
      # La app de Coder no habla con el gateway directamente sino con
      # loopback-proxy (ver más abajo), que le presenta el tráfico como una
      # conexión local: Host/Origin de 127.0.0.1 y sin X-Forwarded-*. Así el
      # gateway auto-aprueba el pairing del navegador (sigue exigiendo el
      # token) y no hace falta allowedOrigins, trustedProxies ni el fallback
      # de Host. Se retiran los ajustes que ponían versiones anteriores del
      # template: con ellos el gateway trataba el tráfico como remoto y pedía
      # "openclaw devices approve" a cada navegador nuevo.
      openclaw config unset gateway.controlUi.allowedOrigins >/dev/null 2>>"$OC_CFG_LOG" || true
      openclaw config unset gateway.controlUi.dangerouslyAllowHostHeaderOriginFallback >/dev/null 2>>"$OC_CFG_LOG" || true
      # Acceso desde el móvil: el gateway (:3333) se publica tal cual como
      # puerto compartido de Coder. Ese tráfico llega por el agente de Coder a
      # 127.0.0.1 con X-Forwarded-For; trustedProxies hace que el gateway lo
      # atribuya al cliente real y lo trate como remoto (emparejamiento por QR
      # o aprobación). La UI del navegador no se ve afectada: loopback-proxy
      # quita esas cabeceras y sigue siendo una conexión local.
      openclaw config set gateway.trustedProxies '["127.0.0.1","::1"]' >/dev/null 2>>"$OC_CFG_LOG" || true
      # URL que meten los QR/códigos de emparejamiento (Devices → Pair device).
      openclaw config set plugins.entries.device-pair.config.publicUrl "$${OPENCLAW_PUBLIC_WS_URL:-}" >/dev/null 2>>"$OC_CFG_LOG" || true
      # La UI abre su WebSocket en <basePath>. Con basePath "/" iría a la raíz,
      # y Coder responde 307 a cualquier petición a "/" de una app cuya URL
      # lleva query (?token=...) para añadirla: el WebSocket nunca se abre y la
      # UI muestra "Gateway ocupado, reintentando…". Con un subpath no pasa.
      openclaw config set gateway.controlUi.basePath "$${OPENCLAW_UI_BASE_PATH:-/openclaw}" >/dev/null 2>>"$OC_CFG_LOG" || true
      if [ -n "$${OPENAI_API_KEY:-}" ]; then
        mkdir -p "$HOME/.openclaw/agents/main/agent"
        cat > "$HOME/.openclaw/agents/main/agent/auth-profiles.json" <<AUTHPROFILES
{
  "version": 1,
  "profiles": {},
  "lastGood": {}
}
AUTHPROFILES
      fi
      if [ -n "$${OPENAI_API_KEY:-}" ]; then
        cat > "$HOME/.openclaw/agents/main/agent/auth-profiles.json" <<AUTHPROFILES
{
  "version": 1,
  "profiles": {
    "ocabra:manual": {
      "type": "api_key",
      "provider": "ocabra",
      "key": "$OPENAI_API_KEY"
    }
  },
  "lastGood": {
    "ocabra": "ocabra:manual"
  }
}
AUTHPROFILES
      fi
      # OpenClaw consume el catálogo vivo descubierto por sync-llm-models.
      provider_base="$${OPENAI_BASE_URL:-}"
      if [ -n "$provider_base" ]; then
        provider_json=$(/home/coder/.local/bin/sync-llm-models --openclaw-provider ocabra 2>/dev/null || echo "{}")
        has_models=$(PROVIDER_JSON="$provider_json" python3 -c 'import json,os; data=json.loads(os.environ.get("PROVIDER_JSON", "{}")); print("1" if data.get("models") else "0")' 2>/dev/null || echo 0)
        if [ "$has_models" = "1" ]; then
          openclaw config set "models.providers.ocabra" "$provider_json" >/dev/null 2>>"$OC_CFG_LOG" || true
        fi
      fi

      ocabra_provider_cfg_json=$(openclaw config get models.providers.ocabra --json 2>/dev/null || echo "{}")
      allowed_models_json=$(OCABRA_PROVIDER_CFG_JSON="$ocabra_provider_cfg_json" python3 - <<'PY'
import json, os
allowed = {}
try:
    config = json.loads(os.environ.get("OCABRA_PROVIDER_CFG_JSON", "{}"))
except Exception:
    config = {}
for model in config.get("models", []):
    if isinstance(model, dict) and isinstance(model.get("id"), str):
        allowed[f"ocabra/{model['id']}"] = {}
print(json.dumps(allowed, separators=(",", ":")))
PY
)
      if [ "$allowed_models_json" != "{}" ]; then
        openclaw config set agents.defaults.models "$allowed_models_json" >/dev/null 2>>"$OC_CFG_LOG" || true
      fi
      # La UI de agentes solo habilita Save al editar una entrada existente en
      # agents.list. Garantizar "main" evita selector activo pero Save deshabilitado.
      current_agents_list_json=$(openclaw config get agents.list --json 2>/dev/null || echo "[]")
      merged_agents_list_json=$(CURRENT_AGENTS_LIST_JSON="$current_agents_list_json" python3 - <<'PY'
import json, os
raw = os.environ.get("CURRENT_AGENTS_LIST_JSON", "[]")
try:
    data = json.loads(raw)
except Exception:
    data = []
if not isinstance(data, list):
    data = []
if not any(isinstance(item, dict) and item.get("id") == "main" for item in data):
    data.append({"id": "main"})
print(json.dumps(data, separators=(",", ":")))
PY
)
      openclaw config set --json agents.list "$merged_agents_list_json" >/dev/null 2>>"$OC_CFG_LOG" || true
      if [ -n "$${OPENCLAW_DEFAULT_MODEL:-}" ]; then
        target_model="$OPENCLAW_DEFAULT_MODEL"
        if [ "$target_model" = "auto" ]; then
          target_model=$(/home/coder/.local/bin/sync-llm-models --best-model 2>/dev/null || true)
        fi
        if [ -n "$target_model" ]; then
          if ! printf '%s' "$target_model" | grep -q '/'; then
            target_model="ocabra/$target_model"
          fi
          target_provider="$${target_model%%/*}"
          if openclaw config get "models.providers.$target_provider" >/dev/null 2>&1; then
            openclaw models set "$target_model" >/dev/null 2>>"$OC_CFG_LOG" || echo "WARN: 'openclaw models set $target_model' falló; la UI pedirá elegir modelo (Model Setup)." >&2
          else
            echo "WARN: modelo por defecto '$target_model' omitido: provider '$target_provider' no configurado." >&2
          fi
        fi
      fi

      # Migra auth-profiles.json (legacy) al almacén SQLite y retira claves de
      # config retiradas; sin esto, "openclaw onboard"/el Control UI piden
      # AUTH_PROFILE_MIGRATION_REQUIRED. Debe correr antes de arrancar el
      # gateway (si ya está vivo, el doctor no puede tomar el lock de estado).
      openclaw doctor --fix >/dev/null 2>>"$OC_CFG_LOG" || true

      # La UI manda a "Model Setup" (firstRun) mientras el agente no tenga
      # modelo primario; avisar en el log si no quedó fijado.
      if [ -z "$(openclaw config get agents.defaults.model.primary 2>/dev/null | tail -1)" ]; then
        echo "WARN: OpenClaw sin modelo primario; la Control UI abrirá Model Setup." >&2
      fi

      # --- Preconfiguración MakeSpace (idempotente; se reaplica en cada arranque) ---
      # Zona horaria del agente e idioma de la Control UI.
      openclaw config set agents.defaults.userTimezone Europe/Madrid >/dev/null 2>>"$OC_CFG_LOG" || true
      openclaw config set ui.prefs.locale es >/dev/null 2>>"$OC_CFG_LOG" || true

      OC_URL="$${OPENAI_BASE_URL:-}"
      if [ -n "$${OPENAI_API_KEY:-}" ] && [ -n "$OC_URL" ]; then
        # Voz con Ocabra. "$${OPENAI_API_KEY}" va literal: OpenClaw lo resuelve
        # desde ~/.openclaw/.env al usarlo. Talk en modo stt-tts porque Ocabra
        # no tiene realtime (si no, intentaría el realtime de OpenAI).
        openclaw config set tts '{"auto":"off","provider":"openai","providers":{"openai":{"baseUrl":"'"$OC_URL"'","apiKey":"$${OPENAI_API_KEY}","model":"recomendado-tts","speakerVoice":"alloy","responseFormat":"mp3"}}}' >/dev/null 2>>"$OC_CFG_LOG" || true
        openclaw config set talk '{"provider":"openai","speechLocale":"es-ES","realtime":{"mode":"stt-tts"}}' >/dev/null 2>>"$OC_CFG_LOG" || true
        # Transcripción del audio entrante (notas de voz de Telegram, etc.).
        openclaw config set tools.media.audio '{"enabled":true,"language":"es"}' >/dev/null 2>>"$OC_CFG_LOG" || true
        openclaw config set tools.media.models '[{"provider":"openai","model":"recomendado-stt","baseUrl":"'"$OC_URL"'","capabilities":["audio"]}]' >/dev/null 2>>"$OC_CFG_LOG" || true
        # Memoria con embeddings de Ocabra ("openai-compatible": las embeddings
        # no usan el auth-profile del proveedor ocabra). Sin rerank: OpenClaw no
        # tiene reranker configurable.
        openclaw config set memory.search '{"enabled":true,"provider":"openai-compatible","model":"recomendado-embedding","remote":{"baseUrl":"'"$OC_URL"'","apiKey":"$${OPENAI_API_KEY}"}}' >/dev/null 2>>"$OC_CFG_LOG" || true
        # Reindexar solo si cambia el modelo/endpoint de embeddings (necesita el
        # gateway parado, que en el arranque aún no corre).
        mem_marker="$HOME/.local/state/openclaw/memory-embeddings"
        mem_want="recomendado-embedding@$OC_URL"
        if [ "$(cat "$mem_marker" 2>/dev/null)" != "$mem_want" ]; then
          mkdir -p "$(dirname "$mem_marker")"
          if timeout 300 openclaw memory index --force --agent main >/dev/null 2>&1; then
            printf '%s\n' "$mem_want" > "$mem_marker"
          else
            echo "WARN: reindexado de memoria de OpenClaw falló; se reintentará en el próximo arranque." >&2
          fi
        fi
      fi

      # Contexto MakeSpace para el agente: sección gestionada al final de
      # AGENTS.md (entre marcadores, se reemplaza en cada arranque). No toca el
      # resto del fichero ni SOUL.md/IDENTITY.md, que son del usuario.
      openclaw setup --baseline >/dev/null 2>&1 || true
      oc_agents_md="$HOME/.openclaw/workspace/AGENTS.md"
      if [ -f "$oc_agents_md" ]; then
        OC_PERSONA=$(cat <<'PERSONA'
${local.assistant_persona}
PERSONA
)
        OC_PERSONA="$OC_PERSONA" python3 - "$oc_agents_md" <<'PY'
import os, re, sys, pathlib
p = pathlib.Path(sys.argv[1])
begin, end = "<!-- makespace:begin (gestionado por el template de Coder; se reescribe en cada arranque) -->", "<!-- makespace:end -->"
text = p.read_text(encoding="utf-8")
text = re.sub(r"\n*<!-- makespace:begin.*?<!-- makespace:end -->\n?", "\n", text, flags=re.S).rstrip("\n")
p.write_text(text + "\n\n" + begin + "\n" + os.environ["OC_PERSONA"].strip() + "\n" + end + "\n", encoding="utf-8")
PY
      fi

      # Telegram. Con IDs: solo esos usuarios (allowlist). Sin IDs: pairing
      # (el desconocido recibe un código; "openclaw pairing approve telegram
      # <CODE>"; el primero aprobado queda como owner). Grupos: solo con mención.
      touch "$HOME/.openclaw/.env"; chmod 600 "$HOME/.openclaw/.env"
      grep -v '^TELEGRAM_BOT_TOKEN=' "$HOME/.openclaw/.env" > "$HOME/.openclaw/.env.tmp" || true
      if [ -n "$${TELEGRAM_BOT_TOKEN:-}" ]; then
        printf 'TELEGRAM_BOT_TOKEN=%s\n' "$TELEGRAM_BOT_TOKEN" >> "$HOME/.openclaw/.env.tmp"
        tg_json=$(TG_IDS="$${TELEGRAM_ALLOWED_USERS:-}" python3 - <<'PY'
import json, os
ids = [i for i in os.environ.get("TG_IDS", "").split(",") if i.strip()]
cfg = {"enabled": True, "botToken": "$${TELEGRAM_BOT_TOKEN}", "groupPolicy": "allowlist", "groups": {"*": {"requireMention": True}}}
cfg.update({"dmPolicy": "allowlist", "allowFrom": ids} if ids else {"dmPolicy": "pairing"})
print(json.dumps(cfg))
PY
)
        openclaw config set channels.telegram "$tg_json" >/dev/null 2>&1 || echo "WARN: no se pudo configurar Telegram en OpenClaw." >&2
      else
        openclaw config set channels.telegram.enabled false >/dev/null 2>>"$OC_CFG_LOG" || true
      fi
      mv "$HOME/.openclaw/.env.tmp" "$HOME/.openclaw/.env"; chmod 600 "$HOME/.openclaw/.env"
    fi

    # Persistir configuración de OpenClaw para invocaciones manuales posteriores
    mkdir -p "$HOME/.local/state/openclaw"
    cat > "$HOME/.local/state/openclaw/runtime.env" <<EOF
OPENCLAW_PORT="$${OPENCLAW_PORT:-3333}"
OPENCLAW_UI_PORT="$${OPENCLAW_UI_PORT:-13333}"
OPENCLAW_UI_BASE_PATH="$${OPENCLAW_UI_BASE_PATH:-/openclaw}"
OPENCLAW_PAIR_PAGE_PORT="$${OPENCLAW_PAIR_PAGE_PORT:-13334}"
OPENCLAW_GATEWAY_TOKEN="$${OPENCLAW_GATEWAY_TOKEN:-}"
OPENCLAW_WORKDIR="$${OPENCLAW_WORKDIR:-$HOME/Projects}"
OPENCLAW_DEFAULT_MODEL="$${OPENCLAW_DEFAULT_MODEL:-auto}"
EOF
    chmod 600 "$HOME/.local/state/openclaw/runtime.env"

    # Proxy loopback para la app de Coder (hace que el gateway vea al
    # navegador como conexión local: pairing automático, sin allowedOrigins).
    cat > "$HOME/.local/bin/loopback-proxy" <<'JS'
${local.loopback_proxy_script}
JS
    chmod 0755 "$HOME/.local/bin/loopback-proxy"
    cat > "$HOME/.local/bin/openclaw-pair-page" <<'JS'
${local.pair_page_script}
JS
    chmod 0755 "$HOME/.local/bin/openclaw-pair-page"

    # Script de OpenClaw (siempre disponible). Lanza gateway y proxy bajo un
    # bucle de supervisión: si el proceso muere (o OpenClaw se reinicia a sí
    # mismo tras un cambio de config/actualización) vuelve a arrancar solo.
    touch "$HOME/.local/state/openclaw/openclaw.log"
    cat > "$HOME/.local/bin/start-openclaw" <<'OPENCLAWSTART'
#!/usr/bin/env bash
set -euo pipefail
STATE_DIR="$HOME/.local/state/openclaw"
ENV_FILE="$STATE_DIR/runtime.env"
LOG_FILE="$STATE_DIR/openclaw.log"
PROXY_LOG="$STATE_DIR/ui-proxy.log"
# PIDs en /tmp: el contenedor se recrea en cada arranque y un PID guardado en
# el HOME persistente podría coincidir con otro proceso.
RUN_DIR="/tmp/openclaw-run"
mkdir -p "$STATE_DIR" "$RUN_DIR"

if [ -f "$ENV_FILE" ]; then
  # Cargar token/puertos/workdir persistidos por el startup script del agente.
  set -a
  . "$ENV_FILE"
  set +a
fi

OPENCLAW_PORT="$${OPENCLAW_PORT:-3333}"
OPENCLAW_UI_PORT="$${OPENCLAW_UI_PORT:-13333}"
OPENCLAW_WORKDIR="$${OPENCLAW_WORKDIR:-$HOME/Projects}"
OPENCLAW_UI_BASE_PATH="$${OPENCLAW_UI_BASE_PATH:-/openclaw}"
OPENCLAW_PAIR_PAGE_PORT="$${OPENCLAW_PAIR_PAGE_PORT:-13334}"
export OPENCLAW_PORT OPENCLAW_UI_PORT OPENCLAW_GATEWAY_TOKEN OPENCLAW_UI_BASE_PATH OPENCLAW_PAIR_PAGE_PORT

if [ -z "$${OPENCLAW_GATEWAY_TOKEN:-}" ]; then
  echo "OPENCLAW_GATEWAY_TOKEN no definido. Rebuild/start del workspace para regenerar la configuración." >&2
  exit 1
fi

alive() { [ -f "$1" ] && kill -0 "$(cat "$1")" 2>/dev/null; }

if ! alive "$RUN_DIR/ui-proxy.pid"; then
  nohup setsid bash -c 'while :; do loopback-proxy "$OPENCLAW_UI_PORT" "$OPENCLAW_PORT" "$OPENCLAW_UI_BASE_PATH/"; echo "loopback-proxy salió ($?); reinicio en 3s"; sleep 3; done' >> "$PROXY_LOG" 2>&1 < /dev/null &
  echo $! > "$RUN_DIR/ui-proxy.pid"
fi

# Página "Conectar móvil" (QR de emparejamiento).
if ! alive "$RUN_DIR/pair-page.pid"; then
  nohup setsid bash -c 'export PATH="$HOME/.npm-global/bin:$HOME/.local/bin:$PATH"; while :; do openclaw-pair-page "$OPENCLAW_PAIR_PAGE_PORT"; echo "openclaw-pair-page salió ($?); reinicio en 3s"; sleep 3; done' >> "$STATE_DIR/pair-page.log" 2>&1 < /dev/null &
  echo $! > "$RUN_DIR/pair-page.pid"
fi

if ! alive "$RUN_DIR/openclaw.pid"; then
  cd "$OPENCLAW_WORKDIR" 2>/dev/null || cd "$HOME/Projects"
  ulimit -n 65536 >/dev/null 2>&1 || true
  nohup setsid bash -c 'while :; do openclaw gateway run --allow-unconfigured --port "$OPENCLAW_PORT" --auth token --token "$OPENCLAW_GATEWAY_TOKEN"; echo "openclaw gateway salió ($?); reinicio en 5s"; sleep 5; done' >> "$LOG_FILE" 2>&1 < /dev/null &
  echo $! > "$RUN_DIR/openclaw.pid"
fi

for _ in $(seq 1 120); do
  if curl -fsS --max-time 1 "http://127.0.0.1:$OPENCLAW_UI_PORT$OPENCLAW_UI_BASE_PATH/" >/dev/null 2>&1; then
    exit 0
  fi
  sleep 1
done

echo "OpenClaw no respondió en :$OPENCLAW_UI_PORT tras 120s. Revisa $LOG_FILE y $PROXY_LOG" >&2
exit 1
OPENCLAWSTART
    chmod +x "$HOME/.local/bin/start-openclaw"

    # Parar gateway y proxy (p. ej. para lanzar OpenClaw a mano con otras opciones).
    cat > "$HOME/.local/bin/stop-openclaw" <<'OPENCLAWSTOP'
#!/usr/bin/env bash
for name in openclaw ui-proxy pair-page; do
  pid_file="/tmp/openclaw-run/$name.pid"
  if [ -f "$pid_file" ]; then
    kill -- "-$(cat "$pid_file")" 2>/dev/null || true
    rm -f "$pid_file"
  fi
done
echo "OpenClaw parado."
OPENCLAWSTOP
    chmod +x "$HOME/.local/bin/stop-openclaw"

    # OpenClaw opcional: arranque determinista antes de finalizar startup.
    if [ "$${OPENCLAW_AUTOSTART:-false}" = "true" ]; then
      echo ">> OpenClaw sigue instalándose/configurándose y puede tardar 2-3 minutos..."
      if ! "$HOME/.local/bin/start-openclaw"; then
        echo "WARN: no se pudo arrancar OpenClaw automáticamente. Revisa ~/.local/state/openclaw/openclaw.log" >&2
      fi
      if command -v openclaw >/dev/null 2>&1; then
        if openclaw health --timeout 3000 >/dev/null 2>&1; then
          echo ">> OpenClaw health OK"
        else
          echo "WARN: openclaw health no respondió tras arranque." >&2
        fi
      fi
    else
      echo "INFO: OpenClaw autostart deshabilitado (OPENCLAW_AUTOSTART=false)." >&2
    fi

  EOT

  env = {
    GIT_AUTHOR_NAME                = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
    GIT_AUTHOR_EMAIL               = data.coder_workspace_owner.me.email
    GIT_COMMITTER_NAME             = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
    GIT_COMMITTER_EMAIL            = data.coder_workspace_owner.me.email
    HOME                           = "/home/coder"
    OPENCODE_PROVIDER_URL          = local.openai_base_url
    OPENCODE_API_KEY               = local.openai_api_key
    OCABRA_ENDPOINT_BASE_URL       = local.ocabra_endpoint_base_url
    OCABRA_KEY                     = local.ocabra_key
    OCABRA_BASE_URL                = local.openai_base_url
    OCABRA_API_KEY                 = local.openai_api_key
    AUTO_PROVISION_OCABRA_API_KEY  = tostring(local.auto_provision_ocabra_key)
    CODER_USER_EMAIL               = data.coder_workspace_owner.me.email
    CODER_WORKSPACE_NAME           = data.coder_workspace.me.name
    OPENCLAW_AUTOSTART             = tostring(local.openclaw_autostart)
    OPENCLAW_PORT                  = tostring(local.openclaw_port)
    OPENCLAW_UI_PORT               = tostring(local.openclaw_ui_port)
    OPENCLAW_UI_BASE_PATH          = local.openclaw_ui_base_path
    OPENCLAW_PAIR_PAGE_PORT        = tostring(local.openclaw_pair_page_port)
    OPENCLAW_PUBLIC_WS_URL         = local.openclaw_public_ws_url
    TELEGRAM_BOT_TOKEN             = trimspace(data.coder_parameter.telegram_bot_token.value)
    TELEGRAM_ALLOWED_USERS         = replace(trimspace(data.coder_parameter.telegram_allowed_users.value), " ", "")
    OPENCLAW_GATEWAY_TOKEN         = local.openclaw_gateway_token
    OPENCLAW_WORKDIR               = local.openclaw_workdir_resolved
    OPENCLAW_DEFAULT_MODEL         = local.openclaw_default_model
  }
}

resource "coder_app" "openclaw_ui" {
  count        = data.coder_workspace.me.start_count
  agent_id     = coder_agent.main.id
  slug         = "openclaw-ui"
  display_name = "OpenClaw UI"
  icon         = "/icon/folder.svg"
  # Pasa por loopback-proxy, no directo al gateway (ver startup_script).
  # Subdominio: la Control UI carga sus assets con rutas absolutas (/assets/...),
  # que en modo ruta (/@owner/ws.main/apps/...) apuntarían al propio Coder.
  # La UI deriva la URL del WebSocket de la página, así que no hace falta
  # gatewayUrl; el token en la URL hace el login sin pegar nada a mano.
  # En la raíz, sin ruta: Coder antepone la ruta de esta URL a todas las
  # peticiones (con "/openclaw/" el gateway recibía /openclaw/openclaw/...).
  # loopback-proxy redirige "/" a "/openclaw/" conservando ?token=, y la UI
  # (basePath /openclaw) abre su WebSocket en /openclaw, fuera de "/", que
  # Coder redirige con 307 para añadir la query. Ver startup_script.
  url       = "http://localhost:${local.openclaw_ui_port}/?token=${urlencode(local.openclaw_gateway_token)}"
  subdomain = true
  order     = 1
  open_in   = "tab"

  healthcheck {
    url       = "http://localhost:${local.openclaw_ui_port}${local.openclaw_ui_base_path}/"
    interval  = 5
    threshold = 60
  }
}

# Página con el QR para vincular la app oficial de OpenClaw (iOS/Android).
# Avisa si el gateway aún no es accesible desde Internet.
resource "coder_app" "openclaw_mobile" {
  count        = data.coder_workspace.me.start_count
  agent_id     = coder_agent.main.id
  slug         = "openclaw-mobile"
  display_name = "Conectar móvil"
  icon         = "/emojis/1f4f1.png"
  url          = "http://localhost:${local.openclaw_pair_page_port}/"
  subdomain    = true
  order        = 2
  open_in      = "tab"
}

# Gateway publicado en Internet para la app móvil (checkbox "[OpenClaw] Acceso
# desde el móvil"). Oculta en el dashboard: no es para abrirla en el navegador,
# es la URL que va en el QR. Va directa al gateway, sin loopback-proxy: llega
# con X-Forwarded-For y, con gateway.trustedProxies en loopback, el gateway la
# trata como remota (token + emparejamiento de dispositivo).
resource "coder_app" "openclaw_gateway_public" {
  count        = local.openclaw_public_gateway ? data.coder_workspace.me.start_count : 0
  agent_id     = coder_agent.main.id
  slug         = "openclaw-gateway"
  display_name = "OpenClaw gateway (público)"
  url          = "http://localhost:${local.openclaw_port}"
  subdomain    = true
  share        = "public"
  hidden       = true
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

  # Sin privileged ni Docker in Docker: un contenedor privilegiado da root en
  # el host a quien tenga sudo dentro (aquí, el usuario y el propio agente).

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
