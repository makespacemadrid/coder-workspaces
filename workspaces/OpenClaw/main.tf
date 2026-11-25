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

# --- Formulario -------------------------------------------------------------
# Parámetros dinámicos de Coder: cada integración es un interruptor y sus
# campos solo aparecen si está activado; lo poco habitual va bajo "Opciones
# avanzadas". Los "name" se conservan para no perder valores ya guardados.

data "coder_parameter" "openclaw_default_model" {
  name         = "05_openclaw_default_model"
  display_name = "Modelo por defecto"
  description  = "`auto` usa `recomendado-sota` de Ocabra. También admite `proveedor/modelo`."
  icon         = "/emojis/1f916.png"
  type         = "string"
  default      = "auto"
  mutable      = true
  order        = 10
  styling      = jsonencode({ placeholder = "auto" })
}

data "coder_parameter" "openclaw_public_gateway" {
  name         = "06_openclaw_public_gateway"
  display_name = "Acceso desde el móvil"
  description  = "Publica el gateway en Internet para la app móvil (QR en la app *Conectar móvil*). Protegido por token y emparejamiento."
  icon         = "/emojis/1f4f1.png"
  type         = "bool"
  form_type    = "switch"
  default      = false
  mutable      = true
  order        = 20
}

data "coder_parameter" "telegram" {
  name         = "07_telegram_enabled"
  display_name = "Telegram"
  description  = "Conecta OpenClaw a un bot de Telegram."
  icon         = "/emojis/1f4ac.png"
  type         = "bool"
  form_type    = "switch"
  default      = false
  mutable      = true
  order        = 30
}

data "coder_parameter" "telegram_bot_token" {
  count        = data.coder_parameter.telegram.value ? 1 : 0
  name         = "07_telegram_bot_token"
  display_name = "Token del bot"
  description  = "Token de @BotFather."
  type         = "string"
  default      = ""
  mutable      = true
  order        = 31
  styling      = jsonencode({ mask_input = true, placeholder = "123456789:AA..." })
}

data "coder_parameter" "telegram_allowed_users" {
  count        = data.coder_parameter.telegram.value ? 1 : 0
  name         = "08_telegram_allowed_users"
  display_name = "IDs de usuario permitidos"
  description  = "IDs numéricos separados por comas (te los da @userinfobot). Vacío: cada usuario nuevo recibe un código para aprobarlo."
  type         = "string"
  default      = ""
  mutable      = true
  order        = 32
  styling      = jsonencode({ placeholder = "12345678, 87654321" })
}

data "coder_parameter" "syncthing" {
  name         = "09_syncthing"
  display_name = "Syncthing"
  description  = "Sincroniza carpetas (p. ej. vaults de Obsidian o Logseq) con tus dispositivos. Añade la app *Syncthing* para configurarlo."
  icon         = "/emojis/1f504.png"
  type         = "bool"
  form_type    = "switch"
  default      = false
  mutable      = true
  order        = 40
}

data "coder_parameter" "joplin" {
  name         = "10_joplin"
  display_name = "Joplin"
  description  = "Conecta OpenClaw a tus notas de Joplin. Después ejecuta `openclaw-joplin-setup` en una terminal para guardar la contraseña."
  icon         = "/emojis/1f4d3.png"
  type         = "bool"
  form_type    = "switch"
  default      = false
  mutable      = true
  order        = 50
}

data "coder_parameter" "joplin_server_url" {
  count        = data.coder_parameter.joplin.value ? 1 : 0
  name         = "11_joplin_server_url"
  display_name = "Servidor de Joplin"
  description  = "URL de tu Joplin Server."
  type         = "string"
  default      = ""
  mutable      = true
  order        = 51
  styling      = jsonencode({ placeholder = "https://joplin.ejemplo.org" })
}

data "coder_parameter" "joplin_email" {
  count        = data.coder_parameter.joplin.value ? 1 : 0
  name         = "12_joplin_email"
  display_name = "Usuario de Joplin"
  description  = "Email de tu cuenta en Joplin Server. La contraseña no va aquí."
  type         = "string"
  default      = ""
  mutable      = true
  order        = 52
  styling      = jsonencode({ placeholder = "tu@email" })
}

data "coder_parameter" "advanced" {
  name         = "90_advanced"
  display_name = "Opciones avanzadas"
  description  = "Directorio de trabajo, autoarranque y clave de Ocabra."
  icon         = "/emojis/2699-fe0f.png"
  type         = "bool"
  form_type    = "switch"
  default      = false
  mutable      = true
  order        = 90
}

data "coder_parameter" "openclaw_workdir" {
  count        = data.coder_parameter.advanced.value ? 1 : 0
  name         = "05_openclaw_workdir"
  display_name = "Directorio de trabajo"
  description  = "Directorio desde el que se ejecuta OpenClaw."
  icon         = "/emojis/1f4c2.png"
  type         = "string"
  default      = "/home/coder"
  mutable      = true
  order        = 91
}

data "coder_parameter" "openclaw_autostart" {
  count        = data.coder_parameter.advanced.value ? 1 : 0
  name         = "05_openclaw_autostart"
  display_name = "Arrancar OpenClaw al iniciar"
  description  = "Si lo desactivas, arráncalo a mano con `start-openclaw`."
  type         = "bool"
  form_type    = "switch"
  default      = true
  mutable      = true
  order        = 92
}

data "coder_parameter" "ocabra_key_mode" {
  count        = data.coder_parameter.advanced.value ? 1 : 0
  name         = "60_ocabra_key_mode"
  display_name = "Clave de Ocabra"
  description  = "Por defecto se genera una clave nueva (30 días) en cada arranque."
  icon         = "/emojis/1f511.png"
  type         = "string"
  form_type    = "radio"
  default      = "auto"
  mutable      = true
  order        = 93
  option {
    name  = "Generar automáticamente"
    value = "auto"
  }
  option {
    name  = "Usar mi propia clave"
    value = "manual"
  }
}

data "coder_parameter" "ocabra_key_value" {
  count        = (data.coder_parameter.advanced.value && try(data.coder_parameter.ocabra_key_mode[0].value, "auto") == "manual") ? 1 : 0
  name         = "61_ocabra_key_value"
  display_name = "Tu clave de Ocabra"
  type         = "string"
  default      = ""
  mutable      = true
  order        = 94
  styling      = jsonencode({ mask_input = true, placeholder = "sk-..." })
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
  ocabra_key_mode              = try(data.coder_parameter.ocabra_key_mode[0].value, "auto")
  ocabra_key_value             = trimspace(try(data.coder_parameter.ocabra_key_value[0].value, ""))
  openai_api_key               = local.ocabra_key_mode == "manual" ? local.ocabra_key_value : ""
  auto_provision_ocabra_key    = local.ocabra_key_mode == "auto"
  openclaw_autostart           = try(data.coder_parameter.openclaw_autostart[0].value, "true")
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
  openclaw_workdir             = trimspace(try(data.coder_parameter.openclaw_workdir[0].value, ""))
  openclaw_workdir_resolved    = local.openclaw_workdir != "" ? local.openclaw_workdir : "/home/coder"
  openclaw_default_model       = trimspace(data.coder_parameter.openclaw_default_model.value)
  llm_model_sync_script        = file("${path.module}/sync_llm_models.py")
  loopback_proxy_script        = file("${path.module}/loopback_proxy.mjs")
  assistant_persona            = file("${path.module}/assistant_persona.md")
  config_patch_script          = file("${path.module}/config_patch.py")
  # Integraciones opcionales (scripts en integrations/).
  syncthing_enabled            = data.coder_parameter.syncthing.value
  syncthing_ui_port            = 18384
  joplin_enabled               = data.coder_parameter.joplin.value
  joplin_server_url            = trimspace(try(data.coder_parameter.joplin_server_url[0].value, ""))
  joplin_email                 = trimspace(try(data.coder_parameter.joplin_email[0].value, ""))
  syncthing_start_script       = file("${path.module}/integrations/syncthing-start.sh")
  syncthing_stop_script        = file("${path.module}/integrations/syncthing-stop.sh")
  syncthing_check_script       = file("${path.module}/integrations/syncthing-check-folder.sh")
  joplin_run_script            = file("${path.module}/integrations/joplin-run.sh")
  joplin_mcp_script            = file("${path.module}/integrations/joplin-mcp.sh")
  joplin_setup_script          = file("${path.module}/integrations/joplin-setup.sh")
  setup_page_script            = file("${path.module}/integrations/setup_page.mjs")
  setup_status_script          = file("${path.module}/integrations/setup-status.sh")
  setup_page_port              = 13335
  # La app "Completar configuración" solo tiene sentido con integraciones que
  # piden un paso manual (Joplin). Syncthing se configura en su propia app.
  setup_page_enabled           = local.joplin_enabled
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

  # Estado en vivo en la página del workspace: pasos manuales pendientes
  # (p. ej. la contraseña de Joplin) o "Completa".
  metadata {
    display_name = "Configuración"
    key          = "openclaw_setup"
    script       = "\"$HOME/.local/bin/openclaw-setup-status\" 2>/dev/null || echo '⏳ Preparando…'"
    interval     = 30
    timeout      = 5
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

    # Estado de la configuración (metadata del agente y app "Completar configuración").
    cat > "$HOME/.local/bin/openclaw-setup-status" <<'SETUPSTATUS'
${local.setup_status_script}
SETUPSTATUS
    chmod 755 "$HOME/.local/bin/openclaw-setup-status"

    # Codex: su sandbox (bubblewrap) necesita crear user namespaces, que Docker
    # no permite en un contenedor sin privilegios ("bwrap: No permissions to
    # create a new namespace"), y entonces no puede escribir nada. El
    # aislamiento es el propio contenedor, como para el agente de OpenClaw:
    # sandbox_mode = "danger-full-access", manteniendo las confirmaciones. Solo
    # si el usuario no eligió otro modo; la clave va arriba del TOML.
    python3 -I - "$HOME/.codex/config.toml" <<'CODEXCFG' || true
import sys, tomllib, pathlib
p = pathlib.Path(sys.argv[1])
text = p.read_text(encoding="utf-8") if p.exists() else ""
try:
    data = tomllib.loads(text)
except tomllib.TOMLDecodeError as exc:
    print(f"WARN: ~/.codex/config.toml no es TOML válido; no se toca ({exc})", file=sys.stderr); sys.exit(0)
if "sandbox_mode" in data:
    sys.exit(0)  # el usuario ya eligió un modo: respetarlo
header = ("# Gestionado por el template de Coder: en este contenedor sin privilegios el\n"
          "# sandbox de Codex (bubblewrap) no puede crear namespaces; el aislamiento es\n"
          "# el propio contenedor. Las confirmaciones (approval_policy) se mantienen.\n"
          'sandbox_mode = "danger-full-access"\n\n')
new = header + text
tomllib.loads(new)
p.parent.mkdir(parents=True, exist_ok=True)
p.write_text(new, encoding="utf-8")
CODEXCFG

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

    # OpenCode contra Ocabra (mismo esquema que Developer): catálogo vivo y
    # modelo por defecto el mismo que OpenClaw; no pisa el resto de su config.
    mkdir -p "$HOME/.config/opencode" "$HOME/.opencode"
    OPENCODE_DEFAULT_MODEL="$${OPENCLAW_DEFAULT_MODEL:-auto}" /home/coder/.local/bin/sync-llm-models \
      --opencode "$HOME/.config/opencode/opencode.json" >/dev/null 2>&1 \
      || echo "WARN: no se pudo configurar OpenCode contra Ocabra." >&2
    ln -sf "$HOME/.config/opencode/opencode.json" "$HOME/.opencode/opencode.json" || true

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
      OC_STATE="$HOME/.local/state/openclaw"
      OC_CFG_LOG="$OC_STATE/startup-config.log"
      mkdir -p "$OC_STATE"; : > "$OC_CFG_LOG"

      # Token de Telegram en ~/.openclaw/.env (la config solo lo referencia).
      touch "$HOME/.openclaw/.env"; chmod 600 "$HOME/.openclaw/.env"
      grep -v '^TELEGRAM_BOT_TOKEN=' "$HOME/.openclaw/.env" > "$HOME/.openclaw/.env.tmp" || true
      if [ -n "$${TELEGRAM_BOT_TOKEN:-}" ]; then
        printf 'TELEGRAM_BOT_TOKEN=%s\n' "$TELEGRAM_BOT_TOKEN" >> "$HOME/.openclaw/.env.tmp"
      fi
      mv "$HOME/.openclaw/.env.tmp" "$HOME/.openclaw/.env"; chmod 600 "$HOME/.openclaw/.env"
      # Recuperar variables persistidas (OPENAI_*, TELEGRAM_*).
      set -a
      . "$HOME/.openclaw/.env"
      set +a

      # La clave de Ocabra (nueva en cada arranque, o la del usuario) va solo en
      # ~/.openclaw/.env y el proveedor "ocabra" la lee de ahí (apiKey como
      # referencia al entorno, ver config_patch.py). Antes se escribía un perfil
      # de credenciales que "doctor --fix" tenía que migrar en cada arranque
      # (~40 s). El doctor solo corre ahora si cambia la versión de OpenClaw.
      version_stamp="$OC_STATE/doctor-version"
      oc_version=$(openclaw --version 2>/dev/null | head -1)
      if [ "$(cat "$version_stamp" 2>/dev/null)" != "$oc_version" ]; then
        if openclaw doctor --fix >/dev/null 2>>"$OC_CFG_LOG"; then
          printf '%s\n' "$oc_version" > "$version_stamp"
        else
          echo "WARN: openclaw doctor --fix falló; ver $OC_CFG_LOG" >&2
        fi
      fi
      # Una vez: retirar el perfil antiguo "ocabra:manual" (clave caducada de
      # versiones anteriores de la plantilla) y sus copias .migrated-*.
      auth_dir="$HOME/.openclaw/agents/main/agent"
      if [ ! -f "$OC_STATE/legacy-auth-removed" ]; then
        openclaw models auth logout ocabra:manual --yes >/dev/null 2>&1 || true
        rm -f "$auth_dir/auth-profiles.json" "$OC_STATE/auth-key.sha256"
        touch "$OC_STATE/legacy-auth-removed"
      fi
      find "$auth_dir" -maxdepth 1 -name 'auth-profiles.json.migrated-*' -delete 2>/dev/null || true

      # Catálogo vivo de Ocabra y modelo por defecto.
      provider_json="{}"
      if [ -n "$${OPENAI_BASE_URL:-}" ]; then
        provider_json=$("$HOME/.local/bin/sync-llm-models" --openclaw-provider ocabra 2>>"$OC_CFG_LOG" || echo "{}")
      fi
      target_model="$${OPENCLAW_DEFAULT_MODEL:-}"
      if [ "$target_model" = "auto" ]; then
        target_model=$("$HOME/.local/bin/sync-llm-models" --best-model 2>/dev/null || true)
      fi
      if [ -n "$target_model" ] && ! printf '%s' "$target_model" | grep -q '/'; then
        target_model="ocabra/$target_model"
      fi

      # Toda la configuración en una sola escritura validada (config_patch.py):
      # ~40 "openclaw config set" tardaban ~2 s cada uno en cada arranque.
      cat > "$HOME/.local/bin/openclaw-config-patch" <<'CFGPATCH'
${local.config_patch_script}
CFGPATCH
      chmod 755 "$HOME/.local/bin/openclaw-config-patch"
      patch_file="$OC_STATE/config-patch.json"
      ( umask 077
        PROVIDER_JSON="$provider_json" TARGET_MODEL="$target_model" \
          python3 "$HOME/.local/bin/openclaw-config-patch" > "$patch_file" 2>>"$OC_CFG_LOG" )
      if openclaw config patch --file "$patch_file" >/dev/null 2>>"$OC_CFG_LOG"; then
        rm -f "$patch_file"
      else
        echo "WARN: no se pudo aplicar la configuración de OpenClaw; ver $OC_CFG_LOG (parche en $patch_file)." >&2
      fi

      # La UI manda a "Model Setup" mientras no haya modelo primario.
      if ! python3 -c 'import json, os, sys; d = json.load(open(os.path.expanduser("~/.openclaw/openclaw.json"))); sys.exit(0 if ((d.get("agents") or {}).get("defaults") or {}).get("model", {}).get("primary") else 1)' 2>/dev/null; then
        echo "WARN: OpenClaw sin modelo primario; la Control UI abrirá Model Setup." >&2
      fi

      # Reindexar la memoria solo si cambia el modelo/endpoint de embeddings
      # (necesita el gateway parado, que en el arranque aún no corre).
      if [ -n "$${OPENAI_API_KEY:-}" ] && [ -n "$${OPENAI_BASE_URL:-}" ]; then
        mem_marker="$OC_STATE/memory-embeddings"
        mem_want="recomendado-embedding@$OPENAI_BASE_URL"
        if [ "$(cat "$mem_marker" 2>/dev/null)" != "$mem_want" ]; then
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
      [ -f "$HOME/.openclaw/workspace/AGENTS.md" ] || openclaw setup --baseline >/dev/null 2>&1 || true
      oc_agents_md="$HOME/.openclaw/workspace/AGENTS.md"
      if [ -f "$oc_agents_md" ]; then
        OC_PERSONA=$(cat <<'PERSONA'
${local.assistant_persona}

## Herramientas de este workspace
- Python: `pip install` en el sistema está bloqueado (PEP 668). Para scripts con dependencias usa `uv run --with <paquete> python script.py` (o `pipx` para herramientas).
- Imágenes: ImageMagick (`convert`, `identify`, `magick`) y Pillow (`from PIL import Image`). Las imágenes generadas quedan en `~/.openclaw/media/`.
- OpenCode (`opencode`), configurado con los modelos de Ocabra, para tareas de programación largas.
- rclone (Dropbox, Google Drive…) y Git con LFS, instalados pero sin cuentas configuradas.
- Lo instalado con `apt` se pierde al reiniciar el workspace: instala en `~/.local` o usa `uv`/`pipx`/`npm` de usuario.
PERSONA
)
        if [ "$${SYNCTHING_ENABLED:-false}" = "true" ]; then
          OC_PERSONA="$OC_PERSONA
- Syncthing activo: carpetas sincronizadas con los dispositivos del usuario (se configuran en la app *Syncthing*). \`check-folder-sync <carpeta>\` comprueba una. No uses otro sincronizador sobre la misma carpeta."
        fi
        if [ "$${JOPLIN_ENABLED:-false}" = "true" ]; then
          OC_PERSONA="$OC_PERSONA
- Joplin conectado por MCP (notas del usuario). Para crear una nota en un cuaderno: \`joplin use \"<cuaderno>\"\` y luego \`mknote\`; \`parent_id\` exige el UUID, nunca el título."
        fi
        OC_PERSONA="$OC_PERSONA" python3 - "$oc_agents_md" <<'PY'
import os, re, sys, pathlib
p = pathlib.Path(sys.argv[1])
begin, end = "<!-- makespace:begin (gestionado por el template de Coder; se reescribe en cada arranque) -->", "<!-- makespace:end -->"
text = p.read_text(encoding="utf-8")
text = re.sub(r"\n*<!-- makespace:begin.*?<!-- makespace:end -->\n?", "\n", text, flags=re.S).rstrip("\n")
p.write_text(text + "\n\n" + begin + "\n" + os.environ["OC_PERSONA"].strip() + "\n" + end + "\n", encoding="utf-8")
PY
      fi

      # Ritual inicial (BOOTSTRAP.md solo existe en un workspace nuevo, y el
      # agente lo retira al terminar): añadir un paso de bienvenida MakeSpace.
      # USER.md no se rellena aquí a propósito: si deja de ser la plantilla,
      # OpenClaw da el workspace por configurado y se salta el ritual.
      oc_bootstrap="$HOME/.openclaw/workspace/BOOTSTRAP.md"
      if [ -f "$oc_bootstrap" ] && ! grep -q "makespace:bootstrap" "$oc_bootstrap"; then
        ws_integ="los modelos de Ocabra (chat, imágenes, voz)"
        ws_todo=""
        [ "$${OPENCLAW_PUBLIC_GATEWAY:-false}" = "true" ] && ws_integ="$ws_integ, acceso desde el móvil (app *Conectar móvil* en Coder)"
        [ -n "$${TELEGRAM_BOT_TOKEN:-}" ] && ws_integ="$ws_integ, un bot de Telegram"
        [ "$${SYNCTHING_ENABLED:-false}" = "true" ] && ws_integ="$ws_integ, Syncthing" && ws_todo="$ws_todo Para enlazar Syncthing con sus equipos, que abra la app *Syncthing* del workspace en Coder (ahí está el ID de este dispositivo)."
        [ "$${JOPLIN_ENABLED:-false}" = "true" ] && ws_integ="$ws_integ, sus notas de Joplin" && ws_todo="$ws_todo Si Joplin aún no está sincronizado, que abra la app *Completar configuración* del workspace en Coder."
        cat >> "$oc_bootstrap" <<BOOTEXTRA

<!-- makespace:bootstrap -->
## 5. Bienvenida MakeSpace

Después de guardar tu identidad, en el mismo tono breve:

- Quien te usa se llama **$${GIT_AUTHOR_NAME:-}** en Coder. Pregúntale cómo quiere que le llames y, en una frase, para qué piensa usarte. Guárdalo en \`USER.md\` como directivas, con el formato y la fecha que indica ese fichero.
- Cuéntale en dos o tres líneas qué tiene este workspace: $ws_integ.$ws_todo
- Propón un ejemplo concreto de algo útil que puedes hacer aquí (generar o editar una imagen, resumir una nota de voz, organizar sus notas…), sin hacer un tour largo.

El paso de recomendaciones de apps del onboarding no aplica en este workspace: sáltalo.
BOOTEXTRA
      fi
    fi

    # Persistir configuración de OpenClaw para invocaciones manuales posteriores
    mkdir -p "$HOME/.local/state/openclaw"
    cat > "$HOME/.local/state/openclaw/runtime.env" <<EOF
OPENCLAW_PORT="$${OPENCLAW_PORT:-3333}"
OPENCLAW_UI_PORT="$${OPENCLAW_UI_PORT:-13333}"
OPENCLAW_UI_BASE_PATH="$${OPENCLAW_UI_BASE_PATH:-/openclaw}"
OPENCLAW_PAIR_PAGE_PORT="$${OPENCLAW_PAIR_PAGE_PORT:-13334}"
OPENCLAW_GATEWAY_TOKEN="$${OPENCLAW_GATEWAY_TOKEN:-}"
OPENCLAW_WORKDIR="$${OPENCLAW_WORKDIR:-$HOME}"
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
OPENCLAW_WORKDIR="$${OPENCLAW_WORKDIR:-$HOME}"
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
  cd "$OPENCLAW_WORKDIR" 2>/dev/null || cd "$HOME"
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
    OPENCLAW_PUBLIC_GATEWAY        = tostring(local.openclaw_public_gateway)
    TELEGRAM_BOT_TOKEN             = trimspace(try(data.coder_parameter.telegram_bot_token[0].value, ""))
    TELEGRAM_ALLOWED_USERS         = replace(trimspace(try(data.coder_parameter.telegram_allowed_users[0].value, "")), " ", "")
    SYNCTHING_ENABLED              = tostring(local.syncthing_enabled)
    SYNCTHING_UI_PORT              = tostring(local.syncthing_ui_port)
    JOPLIN_ENABLED                 = tostring(local.joplin_enabled)
    JOPLIN_SERVER_URL              = local.joplin_server_url
    JOPLIN_EMAIL                   = local.joplin_email
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

# --- Instalaciones en paralelo -------------------------------------------------
# Coder ejecuta estos scripts a la vez que el startup_script: Syncthing, Joplin
# y las herramientas no esperan a que OpenClaw se instale y configure.

resource "coder_script" "setup_page" {
  count              = local.setup_page_enabled ? 1 : 0
  agent_id           = coder_agent.main.id
  display_name       = "Completar configuración"
  icon               = "/emojis/1f9f0.png"
  run_on_start       = true
  start_blocks_login = false
  timeout            = 120
  script             = <<-EOT
    #!/usr/bin/env bash
    set -uo pipefail
    mkdir -p "$HOME/.local/bin" /tmp/openclaw-run
    cat > "$HOME/.local/bin/openclaw-setup-page" <<'SETUPPAGE'
${local.setup_page_script}
SETUPPAGE
    chmod 755 "$HOME/.local/bin/openclaw-setup-page"
    pid_file=/tmp/openclaw-run/setup-page.pid
    if ! { [ -f "$pid_file" ] && kill -0 "$(cat "$pid_file")" 2>/dev/null; }; then
      nohup setsid bash -c 'while :; do node "$HOME/.local/bin/openclaw-setup-page" "$1"; sleep 3; done' setup-page "${local.setup_page_port}" \
        >> "$HOME/.local/state/openclaw-setup-page.log" 2>&1 < /dev/null &
      echo $! > "$pid_file"
    fi
  EOT
}

# OpenCode 2 (CLI), configurado contra Ocabra en el startup_script
# (sync-llm-models --opencode), igual que en Developer. Va en ~/.opencode/bin.
resource "coder_script" "opencode" {
  agent_id           = coder_agent.main.id
  display_name       = "OpenCode"
  icon               = "/icon/opencode.svg"
  run_on_start       = true
  start_blocks_login = false
  timeout            = 900
  script             = <<-EOT
    #!/usr/bin/env bash
    set -uo pipefail
    export PATH="$HOME/.opencode/bin:$HOME/.local/bin:$PATH"
    for rc in "$HOME/.profile" "$HOME/.bashrc"; do
      grep -q '/.opencode/bin' "$rc" 2>/dev/null || echo 'export PATH="$HOME/.opencode/bin:$PATH"' >> "$rc"
    done
    major=0
    if command -v opencode >/dev/null 2>&1; then
      major="$(opencode --version 2>/dev/null | grep -oE '[0-9]+' | head -1)"
    fi
    if [ "$${major:-0}" -lt 2 ] 2>/dev/null; then
      curl -fsSL https://opencode.ai/v2/install | bash >/dev/null 2>&1 \
        || echo "WARN: no se pudo instalar OpenCode; se reintentará en el próximo arranque." >&2
    fi
    opencode --version 2>/dev/null | head -1
  EOT
}

resource "coder_script" "tools" {
  agent_id           = coder_agent.main.id
  display_name       = "Herramientas (rclone, Git LFS, Homebrew)"
  icon               = "/icon/folder.svg"
  run_on_start       = true
  start_blocks_login = false
  timeout            = 1800
  script             = <<-EOT
    #!/usr/bin/env bash
    set -uo pipefail
    export PATH="$HOME/.npm-global/bin:$HOME/.local/bin:$PATH"
    mkdir -p "$HOME/.local/bin"
    # --- Herramientas de sincronización (en el HOME persistente) ---
    # git y git-lfs vienen en la imagen: activar LFS para el usuario una vez.
    if command -v git-lfs >/dev/null 2>&1 && ! git config --global --get filter.lfs.process >/dev/null 2>&1; then
      git lfs install --skip-repo >/dev/null 2>&1 || true
    fi
    # rclone (Dropbox, Google Drive...): binario oficial en ~/.local/bin, una
    # vez; se actualiza con "rclone selfupdate". Configuración y tokens OAuth en
    # ~/.config/rclone (permisos 600), nunca en la plantilla.
    if ! command -v rclone >/dev/null 2>&1; then
      (
        set -e
        tmp=$(mktemp -d)
        trap 'rm -rf "$tmp"' EXIT
        ver=$(curl -fsSL https://downloads.rclone.org/version.txt | awk '{print $2}')
        zip="rclone-$ver-linux-amd64.zip"
        curl -fsSL -o "$tmp/$zip" "https://downloads.rclone.org/$ver/$zip"
        curl -fsSL -o "$tmp/SHA256SUMS" "https://downloads.rclone.org/$ver/SHA256SUMS"
        (cd "$tmp" && grep " $zip\$" SHA256SUMS | sha256sum -c - >/dev/null)
        python3 -c 'import sys, zipfile; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])' "$tmp/$zip" "$tmp"
        install -m 755 "$tmp/rclone-$ver-linux-amd64/rclone" "$HOME/.local/bin/rclone"
      ) || echo "WARN: no se pudo instalar rclone; se reintentará en el próximo arranque." >&2
    fi
    if command -v rclone >/dev/null 2>&1; then
      rclone config touch >/dev/null 2>&1 || true
      chmod 600 "$HOME/.config/rclone/rclone.conf" 2>/dev/null || true
    fi

    # ImageMagick y Pillow para el agente (recortar/convertir imágenes, p. ej.
    # el avatar del ritual inicial). Con apt solo si faltan: el contenedor se
    # recrea en cada arranque, pero va en paralelo (~12 s) y no retrasa nada.
    # Si algún día vienen en la imagen, esto no hace nada.
    if ! command -v convert >/dev/null 2>&1 || ! python3 -c 'import PIL' >/dev/null 2>&1; then
      { sudo apt-get update -qq && sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends imagemagick python3-pil; } >/dev/null 2>&1 \
        || echo "WARN: no se pudieron instalar ImageMagick/Pillow." >&2
    fi
    # Ubuntu trae ImageMagick 6 (convert, identify...); "magick" es la sintaxis
    # de la 7, que los agentes usan a menudo: traducirla.
    if ! command -v magick >/dev/null 2>&1 || [ -f "$HOME/.local/bin/magick" ]; then
      cat > "$HOME/.local/bin/magick" <<'MAGICK'
#!/bin/sh
# Compatibilidad "magick" (ImageMagick 7) sobre ImageMagick 6.
case "$1" in
  convert|identify|mogrify|composite|montage|compare|conjure|stream|animate|display|import)
    tool="$1"; shift; exec "$tool" "$@" ;;
  *) exec convert "$@" ;;
esac
MAGICK
      chmod 755 "$HOME/.local/bin/magick"
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
  EOT
}

resource "coder_script" "syncthing" {
  count              = local.syncthing_enabled ? 1 : 0
  agent_id           = coder_agent.main.id
  display_name       = "Syncthing"
  icon               = "/emojis/1f504.png"
  run_on_start       = true
  start_blocks_login = false
  timeout            = 900
  script             = <<-EOT
    #!/usr/bin/env bash
    set -uo pipefail
    export PATH="$HOME/.npm-global/bin:$HOME/.local/bin:$PATH"
    mkdir -p "$HOME/.local/bin"
    # Syncthing (parámetro "[Integraciones] Syncthing"): binario oficial en
    # ~/.local/bin, una vez; luego se actualiza solo. Config y base en
    # ~/.local/state/syncthing. Los scripts se instalan siempre (datos
    # conservados); solo se arranca con la opción activa.
    if ! command -v syncthing >/dev/null 2>&1; then
      (
        set -e
        tmp=$(mktemp -d)
        trap 'rm -rf "$tmp"' EXIT
        tag=$(curl -fsSL https://api.github.com/repos/syncthing/syncthing/releases/latest | python3 -c 'import json, sys; print(json.load(sys.stdin)["tag_name"])')
        tgz="syncthing-linux-amd64-$tag.tar.gz"
        curl -fsSL -o "$tmp/$tgz" "https://github.com/syncthing/syncthing/releases/download/$tag/$tgz"
        curl -fsSL -o "$tmp/sha256sum.txt.asc" "https://github.com/syncthing/syncthing/releases/download/$tag/sha256sum.txt.asc"
        (cd "$tmp" && grep " $tgz\$" sha256sum.txt.asc | sha256sum -c - >/dev/null)
        tar -xzf "$tmp/$tgz" -C "$tmp"
        install -m 755 "$tmp/syncthing-linux-amd64-$tag/syncthing" "$HOME/.local/bin/syncthing"
      ) || echo "WARN: no se pudo instalar Syncthing; se reintentará en el próximo arranque." >&2
    fi
    cat > "$HOME/.local/bin/start-syncthing" <<'SYNCSTART'
${local.syncthing_start_script}
SYNCSTART
    cat > "$HOME/.local/bin/stop-syncthing" <<'SYNCSTOP'
${local.syncthing_stop_script}
SYNCSTOP
    cat > "$HOME/.local/bin/check-folder-sync" <<'SYNCCHECK'
${local.syncthing_check_script}
SYNCCHECK
    chmod 755 "$HOME/.local/bin/start-syncthing" "$HOME/.local/bin/stop-syncthing" "$HOME/.local/bin/check-folder-sync"
    # Proxy de la GUI (copia propia: no depende del orden con el startup_script).
    mkdir -p "$HOME/.local/share/syncthing-svc"
    cat > "$HOME/.local/share/syncthing-svc/gui-proxy.mjs" <<'GUIPROXY'
${local.loopback_proxy_script}
GUIPROXY

    # Syncthing + proxy de su GUI para la app de Coder. La GUI solo escucha en
    # 127.0.0.1:8384 y rechaza Host ajenos; loopback-proxy los reescribe.
    if command -v syncthing >/dev/null 2>&1; then
      if "$HOME/.local/bin/start-syncthing"; then
        mkdir -p /tmp/syncthing-run
        gui_pid=/tmp/syncthing-run/gui-proxy.pid
        if ! { [ -f "$gui_pid" ] && kill -0 "$(cat "$gui_pid")" 2>/dev/null; }; then
          nohup setsid bash -c 'while :; do node "$HOME/.local/share/syncthing-svc/gui-proxy.mjs" "$1" 8384; sleep 3; done' syncthing-gui "$${SYNCTHING_UI_PORT:-18384}" \
            >> "$HOME/.local/state/syncthing/gui-proxy.log" 2>&1 < /dev/null &
          echo $! > "$gui_pid"
        fi
      else
        echo "WARN: Syncthing no arrancó; revisa ~/.local/state/syncthing/launcher.log" >&2
      fi
    fi
  EOT
}

resource "coder_script" "joplin" {
  count              = local.joplin_enabled ? 1 : 0
  agent_id           = coder_agent.main.id
  display_name       = "Joplin"
  icon               = "/emojis/1f4d3.png"
  run_on_start       = true
  start_blocks_login = false
  timeout            = 1800
  script             = <<-EOT
    #!/usr/bin/env bash
    set -uo pipefail
    export PATH="$HOME/.npm-global/bin:$HOME/.local/bin:$PATH"
    mkdir -p "$HOME/.local/bin"
    # Joplin (parámetro "[Integraciones] Joplin"): CLI y joplin-mcp con
    # versiones probadas; uv/uvx para el MCP. La contraseña no viene de Coder:
    # la guarda openclaw-joplin-setup en ~/.joplin-server-config (600).
    if true; then
      if ! command -v uvx >/dev/null 2>&1; then
        curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR="$HOME/.local/bin" UV_NO_MODIFY_PATH=1 sh >/dev/null 2>&1 \
          || echo "WARN: no se pudo instalar uv (necesario para el MCP de Joplin)." >&2
      fi
      if ! command -v joplin >/dev/null 2>&1; then
        # Prefijo explícito: este script corre en paralelo con el instalador de
        # OpenClaw, que es quien configura ~/.npm-global en ~/.npmrc.
        mkdir -p "$HOME/.npm-global"
        npm install -g --prefix "$HOME/.npm-global" joplin@3.7.1 --allow-scripts=keytar,sharp,sqlite3 >/dev/null 2>&1 \
          || echo "WARN: no se pudo instalar Joplin CLI; se reintentará en el próximo arranque." >&2
      fi
      install -d -m 700 "$HOME/.local/share/joplin-svc"
      cat > "$HOME/.local/share/joplin-svc/run.sh" <<'JOPLINRUN'
${local.joplin_run_script}
JOPLINRUN
      cat > "$HOME/.local/share/joplin-svc/mcp.sh" <<'JOPLINMCP'
${local.joplin_mcp_script}
JOPLINMCP
      cat > "$HOME/.local/bin/openclaw-joplin-setup" <<'JOPLINSETUP'
${local.joplin_setup_script}
JOPLINSETUP
      chmod 755 "$HOME/.local/share/joplin-svc/run.sh" "$HOME/.local/share/joplin-svc/mcp.sh" "$HOME/.local/bin/openclaw-joplin-setup"
      # Servidor y usuario de los parámetros de Coder: solo se aplican cuando
      # cambian respecto a la última vez, para no pisar lo que el usuario haya
      # cambiado desde la app "Completar configuración". La contraseña se
      # conserva siempre (nunca viene de Coder).
      jcfg="$HOME/.joplin-server-config"
      jstamp="$HOME/.local/state/openclaw/joplin-params.applied"
      jwant="$${JOPLIN_SERVER_URL:-}|$${JOPLIN_EMAIL:-}"
      if [ -n "$${JOPLIN_SERVER_URL:-}" ] && [ -n "$${JOPLIN_EMAIL:-}" ] && [ "$(cat "$jstamp" 2>/dev/null)" != "$jwant" ]; then
        jpw=$( { [ -f "$jcfg" ] && grep -m1 '^JOPLIN_PASSWORD=' "$jcfg" | cut -d= -f2-; } || true)
        ( umask 077; printf 'JOPLIN_SERVER_URL=%s\nJOPLIN_EMAIL=%s\nJOPLIN_PASSWORD=%s\n' "$JOPLIN_SERVER_URL" "$JOPLIN_EMAIL" "$jpw" > "$jcfg" )
        unset jpw
        mkdir -p "$(dirname "$jstamp")"; printf '%s\n' "$jwant" > "$jstamp"
        # Cuenta o servidor nuevos: hay que volver a sincronizar desde la app.
        rm -f "$HOME/.local/state/openclaw/joplin-setup.ok"
      fi
      if ! grep -q '^JOPLIN_PASSWORD=.' "$jcfg" 2>/dev/null; then
        echo "INFO: Joplin sin contraseña: complétalo en la app 'Completar configuración'." >&2
      fi
    fi
  EOT
}

# Pasos manuales tras crear el workspace (contraseña de Joplin).
# Las apps de Coder no pueden desaparecer solas al completarse: el estado en
# vivo está en el metadata "Configuración" del agente.
resource "coder_app" "setup" {
  count        = local.setup_page_enabled ? data.coder_workspace.me.start_count : 0
  agent_id     = coder_agent.main.id
  slug         = "setup"
  display_name = "Completar configuración"
  icon         = "/emojis/1f9f0.png"
  url          = "http://localhost:${local.setup_page_port}/"
  subdomain    = true
  order        = 0
  open_in      = "tab"
}

# Interfaz web de Syncthing, solo con la integración activa. Va por el proxy
# autenticado de Coder (sharing "owner"); Syncthing no lleva contraseña propia
# porque solo escucha en loopback.
resource "coder_app" "syncthing" {
  count        = local.syncthing_enabled ? data.coder_workspace.me.start_count : 0
  agent_id     = coder_agent.main.id
  slug         = "syncthing"
  display_name = "Syncthing"
  icon         = "/icon/folder.svg"
  url          = "http://localhost:${local.syncthing_ui_port}/"
  subdomain    = true
  order        = 3
  open_in      = "tab"

  healthcheck {
    url       = "http://localhost:${local.syncthing_ui_port}/rest/noauth/health"
    interval  = 10
    threshold = 30
  }
}

# Actualización automática de OpenClaw. Su auto-updater integrado necesita un
# gestor de servicios (systemd) y aquí el gateway corre en primer plano bajo
# nuestro bucle, así que solo avisaría. Este script comprueba si hay versión
# nueva y, si la hay, para el gateway, actualiza y lo vuelve a arrancar (corte
# de ~1 min). Al arrancar el workspace (tras un margen) y cada noche.
resource "coder_script" "openclaw_autoupdate" {
  agent_id           = coder_agent.main.id
  display_name       = "OpenClaw auto-update"
  icon               = "/icon/folder.svg"
  cron               = "0 15 4 * * *"
  run_on_start       = true
  start_blocks_login = false
  timeout            = 1800
  script             = <<-EOT
    #!/usr/bin/env bash
    set -uo pipefail
    export PATH="$HOME/.npm-global/bin:$HOME/.local/bin:$PATH"
    exec 9>"/tmp/openclaw-autoupdate.lock"
    flock -n 9 || exit 0
    # Al arrancar el workspace, dar tiempo a que termine el startup_script.
    for _ in $(seq 1 60); do [ -x "$HOME/.local/bin/start-openclaw" ] && break; sleep 10; done
    command -v openclaw >/dev/null 2>&1 || { echo "OpenClaw no está instalado; nada que actualizar."; exit 0; }
    available=$(timeout 120 openclaw update status --json 2>/dev/null | python3 -c 'import json, sys; d = json.load(sys.stdin); print("yes" if (d.get("availability") or {}).get("available") else "no")' 2>/dev/null || echo "?")
    if [ "$available" != "yes" ]; then
      echo "OpenClaw al día ($(openclaw --version 2>/dev/null | head -1))."
      exit 0
    fi
    echo ">> Hay versión nueva de OpenClaw: parando gateway y actualizando..."
    "$HOME/.local/bin/stop-openclaw" || true
    if timeout 900 openclaw update --yes --no-restart; then
      echo ">> Actualizado a: $(openclaw --version 2>/dev/null | head -1)"
    else
      echo "WARN: openclaw update falló; se vuelve a arrancar la versión instalada." >&2
    fi
    "$HOME/.local/bin/start-openclaw"
  EOT
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
