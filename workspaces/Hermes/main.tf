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
  display_name = "[AI/Hermes] Provisionar API key FreeAPI automáticamente"
  description  = "Genera y precarga una API key FreeAPI."
  type         = "bool"
  default      = true
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
  description  = "Modelo por defecto de Hermes. 'auto' elige el modelo de mayor capacidad descubierto en Ocabra/FreeAPI; también admite provider/model."
  type         = "string"
  default      = "auto"
  mutable      = true
}

locals {
  username                   = data.coder_workspace_owner.me.name
  workspace_image            = "ghcr.io/makespacemadrid/coder-mks-developer:latest"
  ocabra_endpoint_base_url   = trimspace(var.ocabra_endpoint_base_url)
  ocabra_key                 = trimspace(var.ocabra_key)
  freeapi_base_url           = trimspace(var.freeapi_base_url)
  freeapi_key_endpoint       = trimspace(var.freeapi_key_endpoint)
  openai_base_url            = local.ocabra_endpoint_base_url
  ocabra_key_mode            = data.coder_parameter.ocabra_key_mode.value
  ocabra_key_value           = trimspace(data.coder_parameter.ocabra_key_value.value)
  openai_api_key             = local.ocabra_key_mode == "manual" ? local.ocabra_key_value : ""
  auto_provision_ocabra_key  = local.ocabra_key_mode == "auto"
  auto_provision_freeapi_key = data.coder_parameter.autoprovision_freeapi_key.value
  hermes_workdir              = trimspace(data.coder_parameter.hermes_workdir.value)
  hermes_workdir_resolved     = local.hermes_workdir != "" ? local.hermes_workdir : "/home/coder/Projects"
  hermes_default_model        = trimspace(data.coder_parameter.hermes_default_model.value)
  llm_model_sync_script       = file("${path.module}/sync_llm_models.py")
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

    # Autoprovisionar clave Ocabra para Hermes si está habilitado
    auto_flag="$${AUTO_PROVISION_OCABRA_API_KEY:-true}"
    if printf '%s' "$auto_flag" | grep -Eq '^(1|true|TRUE|yes|on)$'; then
      OCABRA_BASE_URL="$${OCABRA_BASE_URL:-$${OCABRA_ENDPOINT_BASE_URL:-}}"
      case "$OCABRA_BASE_URL" in */v1) ;; *) [ -n "$OCABRA_BASE_URL" ] && OCABRA_BASE_URL="$${OCABRA_BASE_URL%/}/v1" ;; esac
      export OCABRA_BASE_URL
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

    # Autoprovisionar clave FreeAPI para Hermes si está habilitado
    freeapi_auto_flag="$${AUTO_PROVISION_FREEAPI_API_KEY:-true}"
    if printf '%s' "$freeapi_auto_flag" | grep -Eq '^(1|true|TRUE|yes|on)$'; then
      FREEAPI_BASE_URL="$${FREEAPI_BASE_URL:-}"
      export FREEAPI_BASE_URL
      if [ -z "$${FREEAPI_API_KEY:-}" ]; then
        if [ -z "$${FREEAPI_KEY_ENDPOINT:-}" ]; then
          echo "FREEAPI_KEY_ENDPOINT no configurado; omitiendo autoprovision de key FreeAPI" >&2
        else
          freeapi_alias="freeapi-$(tr -dc 0-9 </dev/urandom 2>/dev/null | head -c 8 | sed 's/^$/00000000/')"
          freeapi_payload=$(printf '{"email":"%s","alias":"%s"}' "$${CODER_USER_EMAIL:-}" "$freeapi_alias")
          freeapi_resp=$(curl -fsSL -X POST "$${FREEAPI_KEY_ENDPOINT:-}" -H "Content-Type: application/json" -d "$freeapi_payload" 2>/dev/null || true)
          freeapi_key=$(printf '%s' "$freeapi_resp" | python3 -c 'import sys,json;x=json.load(sys.stdin);d=x if isinstance(x,dict) else {};dd=d.get("data") if isinstance(d.get("data"),dict) else {};print(d.get("key") or d.get("api_key") or d.get("apiKey") or dd.get("key") or dd.get("api_key") or dd.get("apiKey") or "")' 2>/dev/null || true)
          if [ -n "$freeapi_key" ]; then
            FREEAPI_API_KEY="$freeapi_key"
            export FREEAPI_API_KEY
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
      if [ -n "$${FREEAPI_API_KEY:-}" ]; then
        grep -v '^FREEAPI_API_KEY=' "$HOME/.hermes/.env" > "$HOME/.hermes/.env.tmp" 2>/dev/null || true
        printf 'FREEAPI_API_KEY=%s\n' "$FREEAPI_API_KEY" >> "$HOME/.hermes/.env.tmp"
        mv "$HOME/.hermes/.env.tmp" "$HOME/.hermes/.env"
        hermes config set providers.freeapi.type openai >/dev/null 2>&1 || true
        hermes config set providers.freeapi.base_url "$${FREEAPI_BASE_URL:-}" >/dev/null 2>&1 || true
        hermes config set providers.freeapi.key_env FREEAPI_API_KEY >/dev/null 2>&1 || true
      fi

      # Instala el mismo descubridor de modelos vivos que usan Developer/OpenClaw
      # para elegir "el mejor modelo disponible" sin mantener un roster estático.
      mkdir -p "$HOME/.local/bin"
      cat > "$HOME/.local/bin/sync-llm-models" <<'PY'
${local.llm_model_sync_script}
PY
      chmod 0755 "$HOME/.local/bin/sync-llm-models"

      target_model="$${HERMES_DEFAULT_MODEL:-auto}"
      if [ "$target_model" = "auto" ]; then
        target_model=$("$HOME/.local/bin/sync-llm-models" --best-model 2>/dev/null || true)
      fi
      if [ -n "$target_model" ]; then
        if ! printf '%s' "$target_model" | grep -q '/'; then
          target_model="ocabra/$target_model"
        fi
        target_provider="$${target_model%%/*}"
        target_model_id="$${target_model#*/}"
        if hermes config get "providers.$target_provider" >/dev/null 2>&1; then
          hermes config set "providers.$target_provider.models.$target_model_id.name" "$target_model_id" >/dev/null 2>&1 || true
          hermes config set model "$target_model" >/dev/null 2>&1 || true
        else
          echo "WARN: modelo por defecto '$target_model' omitido: provider '$target_provider' no configurado." >&2
        fi
      fi

      hermes config set terminal.cwd "$${HERMES_WORKDIR:-$HOME/Projects}" >/dev/null 2>&1 || true

      # Persistir configuración para invocaciones manuales posteriores
      mkdir -p "$HOME/.local/state/hermes"
      touch "$HOME/.local/state/hermes/hermes-dashboard.log"
      cat > "$HOME/.local/bin/start-hermes-dashboard" <<'HERMESSTART'
#!/usr/bin/env bash
set -euo pipefail
STATE_DIR="$HOME/.local/state/hermes"
LOG_FILE="$STATE_DIR/hermes-dashboard.log"
PID_FILE="$STATE_DIR/hermes-dashboard.pid"
mkdir -p "$STATE_DIR"

if curl -fsS --max-time 1 "http://127.0.0.1:9119/" >/dev/null 2>&1; then
  echo "Hermes dashboard ya está escuchando en :9119"
  exit 0
fi

nohup hermes dashboard --no-open >> "$LOG_FILE" 2>&1 &
echo $! > "$PID_FILE"

for _ in $(seq 1 60); do
  if curl -fsS --max-time 1 "http://127.0.0.1:9119/" >/dev/null 2>&1; then
    exit 0
  fi
  sleep 1
done

echo "Hermes dashboard no respondió en :9119 tras 60s. Revisa $LOG_FILE" >&2
exit 1
HERMESSTART
      chmod +x "$HOME/.local/bin/start-hermes-dashboard"

      echo ">> Arrancando Hermes dashboard..."
      if ! "$HOME/.local/bin/start-hermes-dashboard"; then
        echo "WARN: no se pudo arrancar el dashboard de Hermes. Revisa ~/.local/state/hermes/hermes-dashboard.log" >&2
      fi

      # El dashboard de Hermes rechaza cualquier cabecera Host que no sea
      # exactamente la de bind (defensa anti DNS-rebinding, sin lista de hosts
      # de confianza configurable a dia de hoy: issues #74664/#34390/#10567 en
      # NousResearch/hermes-agent) y el WebSocket del chat (/api/ws) exige
      # ademas un Origin de localhost/127.0.0.1 (CORSMiddleware hardcodeado).
      # Bindear a 0.0.0.0 tampoco sirve: exige entonces OAuth/OIDC completo.
      # En vez de eso, un nginx local reescribe Host y Origin antes de
      # reenviar a 127.0.0.1:9119, dejando el dashboard en loopback (sin
      # login) y resolviendo ambas cabeceras para el trafico que llega vía
      # el tunel del agente de Coder. El token de sesion embebido en la
      # pagina (window.__HERMES_SESSION_TOKEN__) viaja como ?token= en el
      # WebSocket y no se ve afectado por la reescritura.
      if ! command -v nginx >/dev/null 2>&1; then
        sudo apt-get update -y >/dev/null 2>&1 || true
        sudo DEBIAN_FRONTEND=noninteractive apt-get install -y nginx-light >/dev/null 2>&1 || true
      fi
      if command -v nginx >/dev/null 2>&1; then
        sudo mkdir -p /etc/nginx/hermes-shim
        sudo tee /etc/nginx/hermes-shim/nginx.conf >/dev/null <<'NGINXCONF'
worker_processes 1;
pid /tmp/hermes-shim-nginx.pid;
error_log /tmp/hermes-shim-nginx-error.log warn;
events { worker_connections 64; }
http {
  map $http_upgrade $connection_upgrade {
    default upgrade;
    ""      close;
  }
  server {
    listen 127.0.0.1:19119;
    location / {
      proxy_pass http://127.0.0.1:9119;
      proxy_set_header Host 127.0.0.1:9119;
      proxy_set_header Origin "http://127.0.0.1:9119";
      proxy_http_version 1.1;
      proxy_set_header Upgrade $http_upgrade;
      proxy_set_header Connection $connection_upgrade;
      proxy_read_timeout 3600s;
    }
  }
}
NGINXCONF
        if sudo nginx -c /etc/nginx/hermes-shim/nginx.conf -t >/dev/null 2>&1; then
          sudo nginx -c /etc/nginx/hermes-shim/nginx.conf -s reload 2>/dev/null || sudo nginx -c /etc/nginx/hermes-shim/nginx.conf
        fi
      else
        echo "WARN: no se pudo instalar nginx; el dashboard de Hermes podría rechazar la cabecera Host del proxy de Coder." >&2
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
    FREEAPI_BASE_URL               = local.freeapi_base_url
    FREEAPI_KEY_ENDPOINT           = local.freeapi_key_endpoint
    AUTO_PROVISION_OCABRA_API_KEY  = tostring(local.auto_provision_ocabra_key)
    AUTO_PROVISION_FREEAPI_API_KEY = tostring(local.auto_provision_freeapi_key)
    CODER_USER_EMAIL               = data.coder_workspace_owner.me.email
    CODER_WORKSPACE_NAME           = data.coder_workspace.me.name
    HERMES_WORKDIR                 = local.hermes_workdir_resolved
    HERMES_DEFAULT_MODEL           = local.hermes_default_model
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
    threshold = 12
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
