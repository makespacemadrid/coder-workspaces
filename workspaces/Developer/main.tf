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
  }
}

variable "docker_socket" {
  default     = "unix:///var/run/docker.sock"
  description = "(Opcional) Docker socket URI (usa unix:// prefix)"
  type        = string
}

variable "users_storage" {
  default     = ""
  description = "Ruta base para storage de usuarios (ej. $TF_VAR_users_storage)."
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
  description = "Endpoint para solicitar API keys de FreeAPI."
  type        = string
}

data "coder_parameter" "graphics_acceleration" {
  # Sin nivel DRI intermedio: confirmado en vivo que no da aceleración NVIDIA
  # real sin --gpus all (Mesa cae a LLVMpipe/software igualmente).
  name         = "01_graphics_acceleration"
  display_name = "[Compute] Aceleración gráfica"
  description  = "Software: todo por CPU (Mesa LLVMpipe), sin GPU. GPU NVIDIA: pasa la GPU completa al contenedor (--gpus all), habilita NVENC/CUDA."
  type         = "string"
  default      = "software"
  order        = 10
  mutable      = true
  option {
    name  = "Software (CPU)"
    value = "software"
  }
  option {
    name  = "GPU NVIDIA (NVENC/CUDA)"
    value = "gpu"
  }
}

data "coder_parameter" "storage_mode" {
  name         = "20_storage_mode"
  display_name = "[Storage] Persistencia"
  description  = "Ninguna: todo en volumen Docker (se puede perder si se limpia Docker en el host estando el workspace apagado). Home completo: monta /home/coder en el host. Solo Projects: monta solo /home/coder/Projects en el host."
  type         = "string"
  default      = "none"
  order        = 20
  mutable      = true
  option {
    name  = "Ninguna (volumen Docker)"
    value = "none"
  }
  option {
    name  = "Home completo en el host"
    value = "home"
  }
  option {
    name  = "Solo ~/Projects en el host"
    value = "projects_only"
  }
}

data "coder_parameter" "expose_ports" {
  name         = "30_expose_ports"
  display_name = "[Network] Exponer puertos del host"
  description  = "Mapea un rango de puertos del host hacia el workspace. Elige un rango alto y raro para evitar colisiones."
  type         = "bool"
  default      = false
  order        = 30
  mutable      = true
}

data "coder_parameter" "port_range_start" {
  name         = "31_port_range_start"
  display_name = "[Network] Puerto inicial a exponer"
  description  = "Puerto inicial del rango publicado cuando expones puertos."
  type         = "number"
  default      = 15000
  order        = 31
  mutable      = true
}

data "coder_parameter" "port_range_end" {
  name         = "32_port_range_end"
  display_name = "[Network] Puerto final a exponer"
  description  = "Puerto final (incluido) del rango publicado cuando expones puertos."
  type         = "number"
  default      = 15050
  order        = 32
  mutable      = true
}

data "coder_parameter" "docker_auto_prune" {
  name         = "90_docker_auto_prune"
  display_name = "[Maintenance] Limpieza automática de Docker"
  description  = "Limpia semanalmente la caché de compilación sin uso durante 7 días y las imágenes sin contenedores asociadas de más de 30 días. No elimina volúmenes ni contenedores."
  type         = "bool"
  default      = true
  order        = 90
  mutable      = true
}

data "coder_parameter" "ocabra_key_mode" {
  name         = "60_ocabra_key_mode"
  display_name = "[AI] Clave Ocabra"
  description  = "Auto-aprovisionar una API key Ocabra nueva, o usar una que ya tengas."
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
  name         = "62_autoprovision_freeapi_key"
  display_name = "[AI] Provisionar API key FreeAPI automáticamente"
  description  = "Generar automaticamente una key con acceso a recursos gratis externos que pueden no ser privados."
  type         = "bool"
  default      = true
  order        = 62
  mutable      = true
}

locals {
  username                   = data.coder_workspace_owner.me.name
  workspace_image            = "ghcr.io/makespacemadrid/coder-mks-developer-cli:latest"
  port_range                 = data.coder_parameter.expose_ports.value ? range(data.coder_parameter.port_range_start.value, data.coder_parameter.port_range_end.value + 1) : []
  graphics_acceleration      = data.coder_parameter.graphics_acceleration.value
  enable_gpu                 = local.graphics_acceleration == "gpu"
  enable_dri                 = local.graphics_acceleration == "gpu"
  storage_mode               = data.coder_parameter.storage_mode.value
  persist_home_storage       = local.storage_mode == "home"
  persist_projects_storage   = local.storage_mode == "projects_only"
  host_mount_path            = ""
  host_mount_uid             = "1000"
  workspace_storage_root     = trimspace(var.users_storage)
  workspace_storage_home     = local.workspace_storage_root != "" ? "${local.workspace_storage_root}/${local.username}/${lower(data.coder_workspace.me.name)}" : ""
  workspace_storage_projects = local.workspace_storage_root != "" ? "${local.workspace_storage_root}/${local.username}/${lower(data.coder_workspace.me.name)}/Projects" : ""
  home_mount_host_path       = local.persist_home_storage && local.workspace_storage_root != "" ? local.workspace_storage_home : ""
  projects_mount_host_path   = local.persist_projects_storage && local.workspace_storage_root != "" ? local.workspace_storage_projects : ""
  ocabra_endpoint_base_url   = trimspace(var.ocabra_endpoint_base_url)
  ocabra_key                 = trimspace(var.ocabra_key)
  freeapi_base_url           = trimspace(var.freeapi_base_url)
  freeapi_key_endpoint       = trimspace(var.freeapi_key_endpoint)
  ocabra_key_mode            = data.coder_parameter.ocabra_key_mode.value
  ocabra_key_value           = trimspace(data.coder_parameter.ocabra_key_value.value)
  openai_base_url            = ""
  openai_api_key             = local.ocabra_key_mode == "manual" ? local.ocabra_key_value : ""
  auto_provision_ocabra_key  = local.ocabra_key_mode == "auto"
  auto_provision_freeapi_key = data.coder_parameter.autoprovision_freeapi_key.value
  install_claude             = false
  continue_default_config    = file("${path.module}/continue-config.yaml")
  llm_model_sync_script      = file("${path.module}/sync_llm_models.py")
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

  startup_script = <<-EOT
    set -e

    # Asegurar /home/coder como HOME efectivo incluso si se ejecuta como root
    sudo mkdir -p /home/coder
    sudo chown "$USER:$USER" /home/coder || true

    if [ "${tostring(local.enable_dri)}" = "true" ]; then
      # Alinear grupos para /dev/dri (rendering GPU) sin tocar permisos del host
      for dev in /dev/dri/renderD128 /dev/dri/card0; do
        if [ -e "$dev" ]; then
          dev_gid=$(stat -c '%g' "$dev" 2>/dev/null || echo "")
          if [ -n "$dev_gid" ]; then
            dev_group=$(getent group "$dev_gid" | cut -d: -f1)
            if [ -z "$dev_group" ]; then
              dev_group="hostgpu_$dev_gid"
              if ! getent group "$dev_group" >/dev/null; then
                sudo groupadd -g "$dev_gid" "$dev_group" || true
              fi
            fi
            sudo usermod -aG "$dev_group" "$USER" || true
          fi
          if command -v setfacl >/dev/null 2>&1; then
            sudo setfacl -m "u:$USER:rw" "$dev" 2>/dev/null || true
          fi
        fi
      done
    fi

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

    # Solo configurar OpenCode si NO se está usando Claude Code
    if [ "${tostring(local.install_claude)}" = "false" ]; then
      # Symlink de opencode cuando se instale bajo /root
      if [ -d /root/.opencode ] && [ ! -e /home/coder/.opencode ]; then
        sudo ln -s /root/.opencode /home/coder/.opencode || true
      fi
      # Añadir OpenCode CLI al PATH
      if ! grep -q "/.opencode/bin" /home/coder/.profile 2>/dev/null; then
        echo 'export PATH="$HOME/.opencode/bin:$HOME/.local/bin:$PATH"' >> /home/coder/.profile
      fi
    else
      # Si usamos Claude Code, solo añadir .local/bin al PATH
      if ! grep -q "/.local/bin" /home/coder/.profile 2>/dev/null; then
        echo 'export PATH="$HOME/.local/bin:$PATH"' >> /home/coder/.profile
      fi
    fi

    mkdir -p ~/Projects
    python3 - <<'PY'
import json
import os

paths = [
    os.path.expanduser("~/Projects/.vscode/settings.json"),
    os.path.expanduser("~/.vscode-server/data/Machine/settings.json"),
]
for path in paths:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    data = {}
    if os.path.exists(path):
        try:
            with open(path) as f:
                data = json.load(f)
        except Exception:
            data = {}
    data["terminal.integrated.cwd"] = "/home/coder/Projects"
    with open(path, "w") as f:
        json.dump(data, f, indent=2)
PY
    mkdir -p ~/.opencode ~/.config/opencode
    if [ ! -f ~/.config/opencode/opencode.json ]; then
      if [ -f ~/.opencode/opencode.json ]; then
        cp ~/.opencode/opencode.json ~/.config/opencode/opencode.json
      else
        cat > ~/.config/opencode/opencode.json <<'JSONCFG'
{}
JSONCFG
      fi
    fi
    ln -sf ~/.config/opencode/opencode.json ~/.opencode/opencode.json || true
    ln -sf ~/.config/opencode/opencode.json ~/.opencode/config.json || true

    # chunkTimeout=false + timeout largo: evita que OpenCode corte respuestas
    # largas de los modelos locales/lentos. No pisa si el usuario ya lo cambió.
    python3 - <<'PY'
import json, os
path = os.path.expanduser("~/.config/opencode/opencode.json")
data = {}
if os.path.exists(path):
    try:
        with open(path) as f:
            data = json.load(f)
    except Exception:
        data = {}
settings = data.setdefault("settings", {})
settings.setdefault("chunkTimeout", False)
settings.setdefault("timeout", 2100000)
with open(path, "w") as f:
    json.dump(data, f, indent=2)
PY

    # Asegurar permisos de pipx para el usuario actual
    sudo mkdir -p /opt/pipx /opt/pipx/bin
    sudo chown -R "$USER:$USER" /opt/pipx || true

    # Inicializar /etc/skel la primera vez
    if [ ! -f ~/.init_done ]; then
      cp -rT /etc/skel ~ || true
      touch ~/.init_done
    fi

    # Autoprovisionar clave OpenCode Ocabra si está habilitado
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
            mkdir -p /home/coder/.opencode
            printf "%s" "$key" > /home/coder/.opencode/.latest_ocabra_key || true
            printf "%s" "$payload" > /home/coder/.opencode/.latest_ocabra_request || true
          fi
        fi
      fi
      if [ -n "$${OPENCODE_API_KEY:-}" ]; then
        export OPENCODE_API_KEY
        OCABRA_API_KEY="$${OCABRA_API_KEY:-$OPENCODE_API_KEY}"
        export OCABRA_API_KEY
        mkdir -p /home/coder/.opencode
        if [ -n "$payload" ] && [ -n "$${OPENCODE_API_KEY:-}" ]; then
          printf "%s" "$${OPENCODE_API_KEY:-}" > /home/coder/.opencode/.latest_ocabra_key || true
          printf "%s" "$payload" > /home/coder/.opencode/.latest_ocabra_request || true
        fi
      fi
    fi

    # Autoprovisionar clave FreeAPI si está habilitado y hay endpoint/base URL
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
            mkdir -p /home/coder/.opencode
            printf "%s" "$freeapi_key" > /home/coder/.opencode/.latest_freeapi_key || true
            printf "%s" "$freeapi_payload" > /home/coder/.opencode/.latest_freeapi_request || true
          fi
        fi
      fi
    fi

    # Sincronizar catálogos vivos sin reemplazar la configuración del usuario.
    mkdir -p /home/coder/.local/bin /home/coder/.opencode /home/coder/.config/opencode /home/coder/.continue
    cat > /home/coder/.local/bin/sync-llm-models <<'PY'
${local.llm_model_sync_script}
PY
    chmod 0755 /home/coder/.local/bin/sync-llm-models
    /home/coder/.local/bin/sync-llm-models \
      --opencode /home/coder/.config/opencode/opencode.json \
      --continue-config /home/coder/.continue/config.yaml || \
      echo "WARN: no se pudo sincronizar el catálogo de modelos; se conserva la configuración anterior" >&2
    ln -sf /home/coder/.config/opencode/opencode.json /home/coder/.opencode/opencode.json || true
    ln -sf /home/coder/.config/opencode/opencode.json /home/coder/.opencode/config.json || true
    chown -R "$USER:$USER" /home/coder/.opencode /home/coder/.config/opencode /home/coder/.continue /home/coder/.local/bin || true

    # Propagar variables a nuevas shells interactivas
    if [ -n "$${OPENCODE_PROVIDER_URL:-}" ]; then
      OCABRA_BASE_URL="$${OCABRA_BASE_URL:-$OPENCODE_PROVIDER_URL}"
      export OCABRA_BASE_URL
      if ! grep -q "OCABRA_BASE_URL=" ~/.bashrc 2>/dev/null; then
        echo "export OCABRA_BASE_URL=\"$OCABRA_BASE_URL\"" >> ~/.bashrc
      fi
      if ! grep -q "OPENCODE_PROVIDER_URL=" ~/.bashrc 2>/dev/null; then
        echo "export OPENCODE_PROVIDER_URL=\"$OPENCODE_PROVIDER_URL\"" >> ~/.bashrc
      fi
    fi
    if [ -n "$${OPENCODE_API_KEY:-}" ]; then
      OCABRA_API_KEY="$${OCABRA_API_KEY:-$OPENCODE_API_KEY}"
      export OCABRA_API_KEY
      if ! grep -q "OCABRA_API_KEY=" ~/.bashrc 2>/dev/null; then
        echo "export OCABRA_API_KEY=\"$OCABRA_API_KEY\"" >> ~/.bashrc
      fi
      if ! grep -q "OPENCODE_API_KEY=" ~/.bashrc 2>/dev/null; then
        echo "export OPENCODE_API_KEY=\"$OPENCODE_API_KEY\"" >> ~/.bashrc
      fi
    fi
    if [ -n "$${FREEAPI_BASE_URL:-}" ]; then
      if ! grep -q "FREEAPI_BASE_URL=" ~/.bashrc 2>/dev/null; then
        echo "export FREEAPI_BASE_URL=\"$FREEAPI_BASE_URL\"" >> ~/.bashrc
      fi
    fi
    if [ -n "$${FREEAPI_API_KEY:-}" ]; then
      if ! grep -q "FREEAPI_API_KEY=" ~/.bashrc 2>/dev/null; then
        echo "export FREEAPI_API_KEY=\"$FREEAPI_API_KEY\"" >> ~/.bashrc
      fi
    fi

    # Configuración de Continue solo cuando la key OpenAI se autoprovisiona
    if printf '%s' "$${AUTO_PROVISION_OCABRA_API_KEY:-false}" | grep -Eq '^(1|true|TRUE|yes|on)$' \
      && [ -n "$${OCABRA_API_KEY:-}" ] && [ -n "$${OCABRA_BASE_URL:-}" ]; then
      if [ ! -f ~/.continue/config.yaml ]; then
        mkdir -p ~/.continue
        cat > ~/.continue/config.yaml <<'CONTINUECFG'
${local.continue_default_config}
CONTINUECFG
        sed -i "s|OCABRA_BASE_PLACEHOLDER|$${OCABRA_BASE_URL}|g" ~/.continue/config.yaml
        sed -i "s|OCABRA_API_KEY_PLACEHOLDER|$${OCABRA_API_KEY}|g" ~/.continue/config.yaml
      fi
    fi

    # gh, Node24+CLIs IA y Docker Engine ya vienen horneados en la imagen
    # (DevTools-Base) — sin fallbacks de instalación en runtime.

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
    INSTALL_CLAUDE                 = tostring(local.install_claude)
    CODER_USER_EMAIL               = data.coder_workspace_owner.me.email
    CODER_WORKSPACE_NAME           = data.coder_workspace.me.name
  }

  metadata {
    display_name = "CPU Usage"
    key          = "0_cpu_usage"
    script       = "coder stat cpu"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "RAM Usage"
    key          = "1_ram_usage"
    script       = "coder stat mem"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "Home Disk"
    key          = "3_home_disk"
    script       = "coder stat disk --path $${HOME}"
    interval     = 60
    timeout      = 1
  }

  metadata {
    display_name = "CPU Usage (Host)"
    key          = "4_cpu_usage_host"
    script       = "coder stat cpu --host"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "Memory Usage (Host)"
    key          = "5_mem_usage_host"
    script       = "coder stat mem --host"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "Load Average (Host)"
    key          = "6_load_host"
    script       = <<EOT
      echo "`cat /proc/loadavg | awk '{ print $1 }'` `nproc`" | \
      awk '{ printf "%0.2f", $1/$2 }'
    EOT
    interval     = 60
    timeout      = 1
  }

  metadata {
    display_name = "Swap Usage (Host)"
    key          = "7_swap_host"
    script       = <<EOT
      free -b | awk '/^Swap/ { printf("%.1f/%.1f", $3/1024/1024/1024, $2/1024/1024/1024) }'
    EOT
    interval     = 10
    timeout      = 1
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

# Script de preparación de pipx (debe ejecutarse antes de jupyterlab)
resource "coder_script" "setup_pipx" {
  agent_id           = coder_agent.main.id
  display_name       = "Setup pipx environment"
  icon               = "/icon/folder.svg"
  script             = <<-EOT
    #!/bin/bash
    set -e
    # Asegurar que /opt/pipx existe con permisos correctos
    sudo mkdir -p /opt/pipx /opt/pipx/bin
    sudo chown -R coder:coder /opt/pipx || true
    echo "✓ pipx environment ready"
  EOT
  run_on_start       = true
  start_blocks_login = false
}

# Script para crear venv y kernel por defecto de JupyterLab
resource "coder_script" "setup_jupyter_kernel" {
  agent_id           = coder_agent.main.id
  display_name       = "Setup Jupyter kernel"
  icon               = "/icon/folder.svg"
  script             = <<-EOT
    #!/bin/bash
    set -e

    VENV_DIR="$HOME/.venvs/jupyter"
    KERNEL_NAME="coder-py"
    DISPLAY_NAME="Python (coder)"

    if [ ! -d "$VENV_DIR" ]; then
      python3 -m venv "$VENV_DIR"
    fi

    "$VENV_DIR/bin/python" -m pip install --upgrade pip
    "$VENV_DIR/bin/python" -m pip install --upgrade ipykernel
    "$VENV_DIR/bin/python" -m ipykernel install --user --name "$KERNEL_NAME" --display-name "$DISPLAY_NAME"

    python3 - <<'PY'
from pathlib import Path

config = Path.home() / ".jupyter" / "jupyter_server_config.py"
config.parent.mkdir(parents=True, exist_ok=True)

block = """# >>> coder-managed-kernel
try:
    c
except NameError:
    c = get_config()

c.MappingKernelManager.default_kernel_name = "coder-py"
try:
    c.MultiKernelManager.default_kernel_name = "coder-py"
except Exception:
    pass
# <<< coder-managed-kernel
"""

text = config.read_text() if config.exists() else ""
start = text.find("# >>> coder-managed-kernel")
end = text.find("# <<< coder-managed-kernel")

if start != -1 and end != -1 and end > start:
    end += len("# <<< coder-managed-kernel")
    new = text[:start] + block + text[end:]
else:
    new = text.rstrip()
    if new:
        new += "\n\n"
    new += block + "\n"

config.write_text(new)
PY

    echo "✓ Jupyter kernel '$KERNEL_NAME' ready"
  EOT
  run_on_start       = true
  start_blocks_login = false
}

module "jupyterlab" {
  count      = data.coder_workspace.me.start_count
  source     = "registry.coder.com/coder/jupyterlab/coder"
  version    = "~> 1.2"
  agent_id   = coder_agent.main.id
  depends_on = [coder_script.setup_pipx, coder_script.setup_jupyter_kernel]
}

module "code-server" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/code-server/coder"
  version  = "~> 1.1"
  agent_id = coder_agent.main.id
  folder   = "/home/coder/Projects"
  order    = 1
}

module "git-config" {
  count                  = data.coder_workspace.me.start_count
  source                 = "registry.coder.com/coder/git-config/coder"
  version                = "~> 1.0"
  agent_id               = coder_agent.main.id
  allow_username_change  = false
}

module "opencode" {
  count        = local.install_claude ? 0 : 1
  source       = "registry.coder.com/coder-labs/opencode/coder"
  version      = "~> 0.1"
  agent_id     = coder_agent.main.id
  workdir      = "/home/coder/"
  report_tasks = false
  # cli_app=true duplicaba un tercer botón "OpenCode CLI" junto al "OpenCode"
  # (chat AgentAPI del propio módulo) y nuestro "OpenCode Web" — confirmado en
  # un workspace de prueba real (3 apps opencode). false deja solo los 2 útiles.
  cli_app      = false
  # El instalador "latest" del módulo (curl https://opencode.ai/install) solo
  # sirve OpenCode 1; OpenCode 2 vive en una URL separada. Si esto fuera
  # pre_install_script, install_opencode() igualmente reinstalaría v1 encima
  # (su propio "command -v opencode" corre en un proceso nuevo que no hereda
  # el PATH que exportamos aquí). Como post_install_script, corremos DESPUÉS
  # de esa v1 y la sobreescribimos con v2 en la misma ruta.
  post_install_script = <<-EOT
    #!/usr/bin/env bash
    set -euo pipefail
    export PATH="$HOME/.opencode/bin:$PATH"
    major=0
    if command -v opencode >/dev/null 2>&1; then
      major="$(opencode --version 2>/dev/null | grep -oE '[0-9]+' | head -1)"
    fi
    if [ "$${major:-0}" -lt 2 ] 2>/dev/null; then
      curl -fsSL https://opencode.ai/v2/install | bash
    fi
  EOT
}

resource "docker_volume" "home_volume" {
  count = local.home_mount_host_path == "" ? 1 : 0
  name  = "coder-${data.coder_workspace.me.id}-home"

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

resource "null_resource" "ensure_host_paths" {
  count = (local.home_mount_host_path != "" || local.projects_mount_host_path != "" || local.host_mount_path != "") ? 1 : 0
  triggers = {
    home     = local.home_mount_host_path
    projects = local.projects_mount_host_path
    host     = local.host_mount_path
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e
      if [ -n "${self.triggers.home}" ]; then mkdir -p "${self.triggers.home}"; fi
      if [ -n "${self.triggers.projects}" ]; then mkdir -p "${self.triggers.projects}"; fi
      if [ -n "${self.triggers.host}" ]; then mkdir -p "${self.triggers.host}"; fi
    EOT
  }
}

resource "docker_container" "workspace" {
  depends_on = [null_resource.ensure_host_paths]
  image      = local.workspace_image
  restart    = "unless-stopped"

  name     = "coder-${data.coder_workspace_owner.me.name}-${lower(data.coder_workspace.me.name)}"
  hostname = data.coder_workspace.me.name

  user = local.host_mount_path != "" ? local.host_mount_uid : "coder"

  privileged = true

  entrypoint = [
    "sh",
    "-c",
    <<-EOT
      set -e
      mkdir -p /home/coder/.opencode /home/coder/.config/opencode
      if [ ! -f /home/coder/.config/opencode/opencode.json ]; then
        if [ -f /home/coder/.opencode/opencode.json ]; then
          cp /home/coder/.opencode/opencode.json /home/coder/.config/opencode/opencode.json
        else
          printf '{}' > /home/coder/.config/opencode/opencode.json
        fi
      fi
      ln -sf /home/coder/.config/opencode/opencode.json /home/coder/.opencode/opencode.json || true
      ln -sf /home/coder/.config/opencode/opencode.json /home/coder/.opencode/config.json || true
      ${replace(coder_agent.main.init_script, "/localhost|127\\.0\\.0\\.1/", "host.docker.internal")}
    EOT
  ]

  env = [
    "CODER_AGENT_TOKEN=${coder_agent.main.token}",
    "TZ=Europe/Madrid",
    "NVIDIA_VISIBLE_DEVICES=${local.enable_gpu ? "all" : ""}",
    "NVIDIA_DRIVER_CAPABILITIES=compute,utility,graphics,video"
  ]
  gpus = local.enable_gpu ? "all" : null
  dynamic "devices" {
    for_each = local.enable_dri ? ["/dev/dri"] : []
    content {
      host_path      = devices.value
      container_path = devices.value
      permissions    = "rwm"
    }
  }

  # Solo mapea puertos si expose_ports = true
  dynamic "ports" {
    for_each = local.port_range
    content {
      internal = ports.value
      external = ports.value
      ip       = "0.0.0.0"
    }
  }

  shm_size = 2 * 1024 * 1024 * 1024

  dynamic "mounts" {
    for_each = local.home_mount_host_path != "" ? [local.home_mount_host_path] : []
    content {
      target = "/home/coder"
      type   = "bind"
      source = mounts.value
    }
  }

  dynamic "volumes" {
    for_each = local.home_mount_host_path == "" ? [docker_volume.home_volume[0].name] : []
    content {
      container_path = "/home/coder"
      volume_name    = volumes.value
    }
  }

  dynamic "mounts" {
    for_each = local.projects_mount_host_path != "" ? [local.projects_mount_host_path] : []
    content {
      target = "/home/coder/Projects"
      type   = "bind"
      source = mounts.value
    }
  }

  dynamic "mounts" {
    for_each = local.host_mount_path != "" ? [local.host_mount_path] : []
    content {
      target = "/home/coder/host"
      type   = "bind"
      source = mounts.value
    }
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
