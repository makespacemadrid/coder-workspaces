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
    null = {
      source  = "hashicorp/null"
      version = "~> 3.3.0"
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

variable "freeapi_base_url" {
  default     = ""
  description = "Base URL OpenAI-compatible para FreeAPI (ej. $TF_VAR_freeapi_base_url)."
  type        = string
}

variable "freeapi_key_endpoint" {
  default     = ""
  description = "Endpoint para solicitar keys FreeAPI (autoprovision)."
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

data "coder_parameter" "autoprovision_freeapi_key" {
  name         = "04_autoprovision_freeapi_key"
  display_name = "[AI/OpenClaw] Provisionar API key FreeAPI automáticamente"
  description  = "Genera y precarga una API key FreeAPI."
  type         = "bool"
  default      = true
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
  description  = "Modelo por defecto de OpenClaw. 'auto' elige el modelo de mayor capacidad descubierto en Ocabra/FreeAPI; también admite provider/model o vacío."
  type         = "string"
  default      = "auto"
  mutable      = true
}

data "coder_parameter" "docker_auto_prune" {
  name         = "03_docker_auto_prune"
  display_name = "[Maintenance] Limpieza automática de Docker"
  description  = "Limpia semanalmente la caché de compilación sin uso durante 7 días y las imágenes sin contenedores asociadas de más de 30 días. No elimina volúmenes ni contenedores."
  type         = "bool"
  default      = true
  mutable      = true
}

locals {
  username                     = data.coder_workspace_owner.me.name
  workspace_image              = "ghcr.io/makespacemadrid/coder-mks-developer:latest"
  home_mount_host_path         = ""
  host_mount_path              = ""
  host_mount_uid               = "1000"
  projects_mount_host_path     = ""
  ocabra_endpoint_base_url     = trimspace(var.ocabra_endpoint_base_url)
  ocabra_key                   = trimspace(var.ocabra_key)
  freeapi_base_url             = trimspace(var.freeapi_base_url)
  freeapi_key_endpoint         = trimspace(var.freeapi_key_endpoint)
  openai_base_url              = local.ocabra_endpoint_base_url
  ocabra_key_mode               = data.coder_parameter.ocabra_key_mode.value
  ocabra_key_value               = trimspace(data.coder_parameter.ocabra_key_value.value)
  openai_api_key               = local.ocabra_key_mode == "manual" ? local.ocabra_key_value : ""
  auto_provision_ocabra_key    = local.ocabra_key_mode == "auto"
  auto_provision_freeapi_key   = data.coder_parameter.autoprovision_freeapi_key.value
  openclaw_autostart           = data.coder_parameter.openclaw_autostart.value
  openclaw_port                = 3333
  openclaw_gateway_token       = random_password.openclaw_gateway_token.result
  openclaw_workdir             = trimspace(data.coder_parameter.openclaw_workdir.value)
  openclaw_workdir_resolved    = local.openclaw_workdir != "" ? local.openclaw_workdir : "/home/coder/Projects"
  openclaw_default_model       = trimspace(data.coder_parameter.openclaw_default_model.value)
  coder_access_host            = split("/", data.coder_workspace.me.access_url)[2]
  openclaw_ui_gateway_ws_url   = "wss://${local.coder_access_host}/@${data.coder_workspace_owner.me.name}/${data.coder_workspace.me.name}.main/apps/openclaw-ui/?token=${urlencode(local.openclaw_gateway_token)}"
  openclaw_ui_origin_subdomain = "https://openclaw-ui--${lower(data.coder_workspace.me.name)}--${lower(data.coder_workspace_owner.me.name)}.${local.coder_access_host}"
  openclaw_ui_origin_coder     = "https://${local.coder_access_host}"
  llm_model_sync_script        = file("${path.module}/sync_llm_models.py")
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
    freeapi_auto_flag="$${AUTO_PROVISION_FREEAPI_API_KEY:-true}"
    if printf '%s' "$freeapi_auto_flag" | grep -Eq '^(1|true|TRUE|yes|on)$'; then
      FREEAPI_BASE_URL="$${FREEAPI_BASE_URL:-}"
      export FREEAPI_BASE_URL
      freeapi_payload=""
      if [ -z "$${FREEAPI_API_KEY:-}" ]; then
        FREEAPI_ENDPOINT="$${FREEAPI_KEY_ENDPOINT:-}"
        if [ -z "$FREEAPI_ENDPOINT" ]; then
          echo "FREEAPI_KEY_ENDPOINT no configurado; omitiendo autoprovision de key FreeAPI" >&2
        else
          freeapi_alias="freeapi-$(tr -dc 0-9 </dev/urandom 2>/dev/null | head -c 8 | sed 's/^$/00000000/')"
          freeapi_payload=$(printf '{"email":"%s","alias":"%s"}' "$${CODER_USER_EMAIL:-}" "$freeapi_alias")
          freeapi_resp=$(curl -fsSL -X POST "$FREEAPI_ENDPOINT" -H "Content-Type: application/json" -d "$freeapi_payload" 2>/dev/null || true)
          freeapi_key=$(printf '%s' "$freeapi_resp" | python3 -c 'import sys,json;x=json.load(sys.stdin);d=x if isinstance(x,dict) else {};dd=d.get("data") if isinstance(d.get("data"),dict) else {};print(d.get("key") or d.get("api_key") or d.get("apiKey") or dd.get("key") or dd.get("api_key") or dd.get("apiKey") or "")' 2>/dev/null || true)
          if [ -n "$freeapi_key" ]; then
            FREEAPI_API_KEY="$freeapi_key"
            export FREEAPI_API_KEY
          fi
        fi
      fi
    fi

    # Descubridor de modelos vivos (Ocabra/FreeAPI) que usa OpenClaw.
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
    if [ -n "$${FREEAPI_BASE_URL:-}" ]; then
      if ! grep -q "FREEAPI_BASE_URL=" ~/.bashrc 2>/dev/null; then
        echo "export FREEAPI_BASE_URL=\"$FREEAPI_BASE_URL\"" >> ~/.bashrc
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
    if [ -n "$${FREEAPI_API_KEY:-}" ]; then
      export FREEAPI_API_KEY
      if ! grep -q "FREEAPI_API_KEY=" ~/.bashrc 2>/dev/null; then
        echo "export FREEAPI_API_KEY=\"$FREEAPI_API_KEY\"" >> ~/.bashrc
      fi
      mkdir -p "$HOME/.openclaw"
      touch "$HOME/.openclaw/.env"
      chmod 600 "$HOME/.openclaw/.env"
      grep -v '^FREEAPI_API_KEY=' "$HOME/.openclaw/.env" > "$HOME/.openclaw/.env.tmp" || true
      printf 'FREEAPI_API_KEY=%s\n' "$FREEAPI_API_KEY" >> "$HOME/.openclaw/.env.tmp"
      if [ -n "$${FREEAPI_BASE_URL:-}" ]; then
        grep -v '^FREEAPI_BASE_URL=' "$HOME/.openclaw/.env.tmp" > "$HOME/.openclaw/.env.tmp2" || true
        printf 'FREEAPI_BASE_URL=%s\n' "$FREEAPI_BASE_URL" >> "$HOME/.openclaw/.env.tmp2"
        mv "$HOME/.openclaw/.env.tmp2" "$HOME/.openclaw/.env.tmp"
      fi
      mv "$HOME/.openclaw/.env.tmp" "$HOME/.openclaw/.env"
    fi

    # Docker Engine: instalar si falta y arrancar dockerd (DinD)
    if ! command -v dockerd >/dev/null 2>&1; then
      echo ">> Installing Docker (docker.io)..."
      sudo apt-get update -y
      sudo DEBIAN_FRONTEND=noninteractive apt-get install -y docker.io
    fi

    # Cgroup v2: delegar controladores para Docker in Docker (evita modo threaded)
    if [ -f /sys/fs/cgroup/cgroup.controllers ]; then
      echo ">> Enabling cgroup v2 delegation for DinD..."
      sudo mkdir -p /sys/fs/cgroup/init
      if [ ! -w /sys/fs/cgroup/init/cgroup.procs ] || [ ! -w /sys/fs/cgroup/cgroup.subtree_control ]; then
        echo ">> cgroup v2 not writable; skipping delegation (likely already handled by host)"
      else
        for _ in $(seq 1 20); do
          sudo xargs -rn1 < /sys/fs/cgroup/cgroup.procs > /sys/fs/cgroup/init/cgroup.procs 2>/dev/null || true
          if sudo sh -c 'sed -e "s/ / +/g" -e "s/^/+/" < /sys/fs/cgroup/cgroup.controllers > /sys/fs/cgroup/cgroup.subtree_control'; then
            break
          fi
          sleep 0.1
        done
      fi
    fi

    if ! pgrep dockerd >/dev/null 2>&1; then
      echo ">> Starting dockerd (DinD)..."
      sudo dockerd --host=unix:///var/run/docker.sock --storage-driver=overlay2 >/tmp/dockerd.log 2>&1 &
      for i in $(seq 1 30); do
        if sudo docker info >/dev/null 2>&1; then
          echo ">> dockerd ready"
          break
        fi
        sleep 1
      done
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

    # Evitar caídas por EMFILE al usar watchers (skills/workspace/config).
    sudo sysctl -w fs.inotify.max_user_watches=524288 >/dev/null 2>&1 || true
    sudo sysctl -w fs.inotify.max_user_instances=1024 >/dev/null 2>&1 || true
    sudo sysctl -w fs.inotify.max_queued_events=32768 >/dev/null 2>&1 || true

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
        git clone --depth=1 https://github.com/Homebrew/brew "$BREW_PREFIX/Homebrew"
      fi
      mkdir -p "$BREW_PREFIX/bin"
      ln -sf ../Homebrew/bin/brew "$BREW_BIN"
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
    if [ "$${OPENCLAW_AUTOSTART:-false}" = "true" ] && ! command -v openclaw >/dev/null 2>&1; then
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
      # el entorno de proceso no trae OPENAI/FREEAPI_* en este punto.
      if [ -f "$HOME/.openclaw/.env" ]; then
        set -a
        . "$HOME/.openclaw/.env"
        set +a
      fi
      openclaw config set gateway.mode local >/dev/null 2>&1 || true
      openclaw config set gateway.port "$${OPENCLAW_PORT:-3333}" >/dev/null 2>&1 || true
      openclaw config set gateway.auth.mode token >/dev/null 2>&1 || true
      openclaw config set gateway.auth.token "$${OPENCLAW_GATEWAY_TOKEN:-}" >/dev/null 2>&1 || true
      # Coder abre la app por subdominio y también por host principal (path mode).
      # OpenClaw exige orígenes completos aquí; '*' no evita "origin not allowed".
      openclaw config set gateway.controlUi.allowedOrigins '["${local.openclaw_ui_origin_subdomain}","${local.openclaw_ui_origin_coder}"]' >/dev/null 2>&1 || true
      openclaw config set gateway.controlUi.dangerouslyAllowHostHeaderOriginFallback true >/dev/null 2>&1 || true
      # El gateway solo recibe trafico vía el tunel del agente de Coder, que lo
      # reenvia a 127.0.0.1 dentro del propio contenedor; no hay wildcard
      # valido para trustedProxies (lo rechaza con "proxy_attribution_required").
      openclaw config set gateway.trustedProxies '["127.0.0.1","::1"]' >/dev/null 2>&1 || true
      if [ -n "$${OPENAI_API_KEY:-}" ] || [ -n "$${FREEAPI_API_KEY:-}" ]; then
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
      if [ -n "$${FREEAPI_API_KEY:-}" ]; then
        python3 - <<'PY'
import json, os
path = os.path.expanduser("~/.openclaw/agents/main/agent/auth-profiles.json")
with open(path, "r", encoding="utf-8") as f:
    data = json.load(f)
data.setdefault("profiles", {})
data.setdefault("lastGood", {})
data["profiles"]["freeapi:manual"] = {
    "type": "api_key",
    "provider": "freeapi",
    "key": os.environ.get("FREEAPI_API_KEY", ""),
}
data["lastGood"]["freeapi"] = "freeapi:manual"
with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2)
PY
      fi
      # OpenClaw consume el catálogo vivo descubierto por sync-llm-models.
      for provider_id in ocabra freeapi; do
        case "$provider_id" in
          ocabra) provider_base="$${OPENAI_BASE_URL:-}" ;;
          freeapi) provider_base="$${FREEAPI_BASE_URL:-}" ;;
        esac
        [ -n "$provider_base" ] || continue
        provider_json=$(/home/coder/.local/bin/sync-llm-models --openclaw-provider "$provider_id" 2>/dev/null || echo "{}")
        has_models=$(PROVIDER_JSON="$provider_json" python3 -c 'import json,os; data=json.loads(os.environ.get("PROVIDER_JSON", "{}")); print("1" if data.get("models") else "0")' 2>/dev/null || echo 0)
        if [ "$has_models" = "1" ]; then
          openclaw config set "models.providers.$provider_id" "$provider_json" >/dev/null 2>&1 || true
        fi
      done

      ocabra_provider_cfg_json=$(openclaw config get models.providers.ocabra --json 2>/dev/null || echo "{}")
      freeapi_provider_cfg_json=$(openclaw config get models.providers.freeapi --json 2>/dev/null || echo "{}")
      allowed_models_json=$(OCABRA_PROVIDER_CFG_JSON="$ocabra_provider_cfg_json" FREEAPI_PROVIDER_CFG_JSON="$freeapi_provider_cfg_json" python3 - <<'PY'
import json, os
allowed = {}
for provider_id, variable in (("ocabra", "OCABRA_PROVIDER_CFG_JSON"), ("freeapi", "FREEAPI_PROVIDER_CFG_JSON")):
    try:
        config = json.loads(os.environ.get(variable, "{}"))
    except Exception:
        config = {}
    for model in config.get("models", []):
        if isinstance(model, dict) and isinstance(model.get("id"), str):
            allowed[f"{provider_id}/{model['id']}"] = {}
print(json.dumps(allowed, separators=(",", ":")))
PY
)
      if [ "$allowed_models_json" != "{}" ]; then
        openclaw config set agents.defaults.models "$allowed_models_json" >/dev/null 2>&1 || true
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
      openclaw config set --json agents.list "$merged_agents_list_json" >/dev/null 2>&1 || true
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
            openclaw models set "$target_model" >/dev/null 2>&1 || true
          else
            echo "WARN: modelo por defecto '$target_model' omitido: provider '$target_provider' no configurado." >&2
          fi
        fi
      fi

      # Migra auth-profiles.json (legacy) al almacén SQLite y retira claves de
      # config retiradas; sin esto, "openclaw onboard"/el Control UI piden
      # AUTH_PROFILE_MIGRATION_REQUIRED. Debe correr antes de arrancar el
      # gateway (si ya está vivo, el doctor no puede tomar el lock de estado).
      openclaw doctor --fix >/dev/null 2>&1 || true
    fi

    # Persistir configuración de OpenClaw para invocaciones manuales posteriores
    mkdir -p "$HOME/.local/state/openclaw"
    cat > "$HOME/.local/state/openclaw/runtime.env" <<EOF
OPENCLAW_PORT="$${OPENCLAW_PORT:-3333}"
OPENCLAW_GATEWAY_TOKEN="$${OPENCLAW_GATEWAY_TOKEN:-}"
OPENCLAW_WORKDIR="$${OPENCLAW_WORKDIR:-$HOME/Projects}"
OPENCLAW_DEFAULT_MODEL="$${OPENCLAW_DEFAULT_MODEL:-auto}"
EOF
    chmod 600 "$HOME/.local/state/openclaw/runtime.env"

    # Script de OpenClaw (siempre disponible)
    mkdir -p "$HOME/.local/state/openclaw"
    touch "$HOME/.local/state/openclaw/openclaw.log"
    cat > "$HOME/.local/bin/start-openclaw" <<'OPENCLAWSTART'
#!/usr/bin/env bash
set -euo pipefail
STATE_DIR="$HOME/.local/state/openclaw"
ENV_FILE="$STATE_DIR/runtime.env"
LOG_FILE="$STATE_DIR/openclaw.log"
PID_FILE="$STATE_DIR/openclaw.pid"
mkdir -p "$STATE_DIR"

if [ -f "$ENV_FILE" ]; then
  # Cargar token/puerto/workdir persistidos por el startup script del agente.
  set -a
  . "$ENV_FILE"
  set +a
fi

OPENCLAW_PORT="$${OPENCLAW_PORT:-3333}"
OPENCLAW_WORKDIR="$${OPENCLAW_WORKDIR:-$HOME/Projects}"

if [ -z "$${OPENCLAW_GATEWAY_TOKEN:-}" ]; then
  echo "OPENCLAW_GATEWAY_TOKEN no definido. Rebuild/start del workspace para regenerar la configuración." >&2
  exit 1
fi

if curl -fsS --max-time 1 "http://127.0.0.1:$OPENCLAW_PORT/" >/dev/null 2>&1; then
  echo "OpenClaw ya está escuchando en :$OPENCLAW_PORT"
  exit 0
fi

cd "$OPENCLAW_WORKDIR" 2>/dev/null || cd "$HOME/Projects"
ulimit -n 65536 >/dev/null 2>&1 || true
sudo sysctl -w fs.inotify.max_user_watches=524288 >/dev/null 2>&1 || true
sudo sysctl -w fs.inotify.max_user_instances=1024 >/dev/null 2>&1 || true
sudo sysctl -w fs.inotify.max_queued_events=32768 >/dev/null 2>&1 || true
nohup openclaw gateway run --allow-unconfigured --port "$OPENCLAW_PORT" --auth token --token "$OPENCLAW_GATEWAY_TOKEN" >> "$LOG_FILE" 2>&1 &
echo $! > "$PID_FILE"

for _ in $(seq 1 90); do
  if curl -fsS --max-time 1 "http://127.0.0.1:$OPENCLAW_PORT/" >/dev/null 2>&1; then
    exit 0
  fi
  sleep 1
done

echo "OpenClaw no respondió en :$OPENCLAW_PORT tras 90s. Revisa $LOG_FILE" >&2
exit 1
OPENCLAWSTART
    chmod +x "$HOME/.local/bin/start-openclaw"

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
    FREEAPI_BASE_URL               = local.freeapi_base_url
    FREEAPI_KEY_ENDPOINT           = local.freeapi_key_endpoint
    OCABRA_BASE_URL                = local.openai_base_url
    OCABRA_API_KEY                 = local.openai_api_key
    AUTO_PROVISION_OCABRA_API_KEY  = tostring(local.auto_provision_ocabra_key)
    AUTO_PROVISION_FREEAPI_API_KEY = tostring(local.auto_provision_freeapi_key)
    CODER_USER_EMAIL               = data.coder_workspace_owner.me.email
    CODER_WORKSPACE_NAME           = data.coder_workspace.me.name
    OPENCLAW_AUTOSTART             = tostring(local.openclaw_autostart)
    OPENCLAW_PORT                  = tostring(local.openclaw_port)
    OPENCLAW_GATEWAY_TOKEN         = local.openclaw_gateway_token
    OPENCLAW_WORKDIR               = local.openclaw_workdir_resolved
    OPENCLAW_DEFAULT_MODEL         = local.openclaw_default_model
  }
}

# El cron solo corre con el workspace encendido. La ejecución al arrancar y el
# marcador persistente recuperan la limpieza semanal si estaba apagado.
resource "coder_script" "docker_auto_prune" {
  count              = data.coder_parameter.docker_auto_prune.value ? 1 : 0
  agent_id           = coder_agent.main.id
  display_name       = "Docker auto-prune"
  icon               = "/icon/docker.svg"
  cron               = "0 30 4 * * 0"
  run_on_start       = true
  start_blocks_login = false
  timeout            = 1800
  script             = <<-EOT
    #!/usr/bin/env bash
    set -euo pipefail

    state_dir="$HOME/.local/state/coder-maintenance"
    last_run_file="$state_dir/docker-prune.last"
    lock_file="$state_dir/docker-prune.lock"
    min_interval=$((7 * 24 * 60 * 60))
    now=$(date +%s)
    mkdir -p "$state_dir"

    exec 9>"$lock_file"
    if ! flock -n 9; then
      echo ">> Docker auto-prune: ya hay otra limpieza en curso; se omite."
      exit 0
    fi

    last_run=$(cat "$last_run_file" 2>/dev/null || echo 0)
    case "$last_run" in
      ''|*[!0-9]*) last_run=0 ;;
    esac
    if [ "$last_run" -gt 0 ] && [ "$now" -ge "$last_run" ] && [ $((now - last_run)) -lt "$min_interval" ]; then
      echo ">> Docker auto-prune: la última limpieza fue hace menos de 7 días; se omite."
      exit 0
    fi

    docker_ready=false
    for _ in $(seq 1 120); do
      if sudo docker info >/dev/null 2>&1; then
        docker_ready=true
        break
      fi
      sleep 1
    done
    if [ "$docker_ready" != "true" ]; then
      echo ">> Docker auto-prune: dockerd no está disponible después de 120 segundos." >&2
      exit 1
    fi

    echo ">> Uso de Docker antes de la limpieza:"
    sudo docker system df || true

    if sudo docker buildx version >/dev/null 2>&1; then
      sudo docker buildx prune --all --force --filter "until=168h"
    else
      sudo docker builder prune --all --force --filter "until=168h"
    fi
    sudo docker image prune --all --force --filter "until=720h"

    date +%s > "$last_run_file"
    echo ">> Uso de Docker después de la limpieza:"
    sudo docker system df || true
  EOT
}

resource "coder_app" "openclaw_ui" {
  count        = data.coder_workspace.me.start_count
  agent_id     = coder_agent.main.id
  slug         = "openclaw-ui"
  display_name = "OpenClaw UI"
  icon         = "/icon/folder.svg"
  url          = "http://localhost:${local.openclaw_port}/?token=${urlencode(local.openclaw_gateway_token)}&gatewayUrl=${urlencode(local.openclaw_ui_gateway_ws_url)}"
  subdomain    = false
  order        = 1
  open_in      = "tab"

  healthcheck {
    url       = "http://localhost:${local.openclaw_port}/"
    interval  = 5
    threshold = 6
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

resource "docker_volume" "docker_data" {
  name = "coder-${data.coder_workspace.me.id}-docker-data"

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
  image   = local.workspace_image
  restart = "unless-stopped"

  name     = "coder-${data.coder_workspace_owner.me.name}-${lower(data.coder_workspace.me.name)}"
  hostname = data.coder_workspace.me.name

  user = "coder"

  privileged = true

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

  volumes {
    container_path = "/var/lib/docker"
    volume_name    = docker_volume.docker_data.name
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
