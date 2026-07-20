terraform {
  required_providers {
    coder = {
      source = "coder/coder"
    }
    docker = {
      source = "kreuzwerker/docker"
    }
    null = {
      source = "hashicorp/null"
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

variable "default_repo_url" {
  default     = ""
  description = "Repositorio Git por defecto (ej. $TF_VAR_default_repo_url)."
  type        = string
}
data "coder_parameter" "enable_gpu" {
  name         = "01_enable_gpu"
  display_name = "[Compute] GPU"
  description  = "Activa --gpus all en el contenedor."
  type         = "bool"
  default      = false
  mutable      = true
}

data "coder_parameter" "enable_dri" {
  name         = "01_enable_dri"
  display_name = "[Compute] DRI (/dev/dri)"
  description  = "Mapea /dev/dri para aceleracion grafica (Intel/AMD o NVIDIA via EGL/GL)."
  type         = "bool"
  default      = true
  mutable      = true
}

data "coder_parameter" "git_repo_url" {
  name         = "03_git_repo_url"
  display_name = "[Code] Repositorio Git (opcional)"
  description  = "URL de Git para clonar en ~/Projects/<repo> en el primer arranque"
  type         = "string"
  default      = var.default_repo_url
  mutable      = true
}

data "coder_parameter" "persist_home_storage" {
  name         = "02_01_persist_home_storage"
  display_name = "[Storage] Persistir home en el host"
  description  = "Monta /home/coder en TF_VAR_users_storage/<usuario>/<workspace>. Si no lo activas, /home/coder se guarda en un volumen Docker; si el workspace esta apagado y se limpia Docker en el host, ese volumen puede desaparecer."
  type         = "bool"
  default      = false
  mutable      = true
}

data "coder_parameter" "persist_projects_storage" {
  name         = "02_02_persist_projects_storage"
  display_name = "[Storage] Persistir solo ~/Projects"
  description  = "Monta /home/coder/Projects en TF_VAR_users_storage/<usuario>/<workspace>/Projects."
  type         = "bool"
  default      = false
  mutable      = true
}

data "coder_parameter" "autoprovision_ocabra_key" {
  name         = "04_autoprovision_ocabra_key"
  display_name = "[AI/Ocabra] Provisionar API key Ocabra automáticamente"
  description  = "Genera y precarga una API key Ocabra. La API de Ocabra es privada en los servidores de Ocabra."
  type         = "bool"
  default      = true
  mutable      = true
}

data "coder_parameter" "autoprovision_freeapi_key" {
  name         = "04_autoprovision_freeapi_key"
  display_name = "[AI/FreeAPI] Provisionar API key automáticamente"
  description  = "Generar automaticamente una key con acceso a recursos gratis externos que pueden no ser privados."
  type         = "bool"
  default      = true
  mutable      = true
}

data "coder_parameter" "claude_token" {
  name         = "04_claude_token"
  display_name = "[AI/Claude] Token"
  description  = "Token de Claude (oauth). Si se rellena se usa Claude y se omite el módulo OpenCode. Obténlo con `claude setup-token`."
  type         = "string"
  default      = ""
  mutable      = true
}

locals {
  username             = data.coder_workspace_owner.me.name
  workspace_image      = "codercom/enterprise-base:ubuntu"
  enable_gpu           = data.coder_parameter.enable_gpu.value
  enable_dri           = data.coder_parameter.enable_dri.value
  persist_home_storage           = data.coder_parameter.persist_home_storage.value
  persist_projects_storage       = data.coder_parameter.persist_projects_storage.value
  host_mount_path                = ""
  host_mount_uid                 = "1000"
  workspace_storage_root         = trimspace(var.users_storage)
  workspace_storage_home         = local.workspace_storage_root != "" ? "${local.workspace_storage_root}/${local.username}/${lower(data.coder_workspace.me.name)}" : ""
  workspace_storage_projects     = local.workspace_storage_root != "" ? "${local.workspace_storage_root}/${local.username}/${lower(data.coder_workspace.me.name)}/Projects" : ""
  home_mount_host_path           = local.persist_home_storage && local.workspace_storage_root != "" ? local.workspace_storage_home : ""
  projects_mount_host_path       = local.persist_projects_storage && local.workspace_storage_root != "" ? local.workspace_storage_projects : ""
  ocabra_endpoint_base_url      = trimspace(var.ocabra_endpoint_base_url)
  ocabra_key               = trimspace(var.ocabra_key)
  freeapi_base_url               = trimspace(var.freeapi_base_url)
  freeapi_key_endpoint           = trimspace(var.freeapi_key_endpoint)
  openai_base_url         = ""
  openai_api_key          = ""
  auto_provision_ocabra_key  = data.coder_parameter.autoprovision_ocabra_key.value
  auto_provision_freeapi_key = data.coder_parameter.autoprovision_freeapi_key.value
  claude_token            = trimspace(data.coder_parameter.claude_token.value)
  install_claude          = local.claude_token != ""
  continue_default_config = file("${path.module}/continue-config.yaml")
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
    if [ ! -f ~/.opencode/opencode.json ]; then
      cat > ~/.opencode/opencode.json <<'JSONCFG'
{}
JSONCFG
    fi
    ln -sf ~/.opencode/opencode.json ~/.opencode/config.json || true
    ln -sf ~/.opencode/opencode.json ~/.config/opencode/opencode.json || true

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

    # Aplicar providers de OpenCode (custom + freeapi) en opencode.json
    if [ -n "$${OPENCODE_PROVIDER_URL:-$${OCABRA_ENDPOINT_BASE_URL:-}}" ] || [ -n "$${OCABRA_KEY:-}" ] || [ -n "$${FREEAPI_BASE_URL:-}" ] || [ -n "$${FREEAPI_KEY_ENDPOINT:-}" ] || [ -n "$${OPENCODE_API_KEY:-}" ] || [ -n "$${FREEAPI_API_KEY:-}" ]; then
      mkdir -p /home/coder/.opencode
      if [ ! -f /home/coder/.opencode/opencode.json ]; then
        printf '{}' > /home/coder/.opencode/opencode.json
      fi
      OPENCODE_PROVIDER_URL="$${OPENCODE_PROVIDER_URL:-$${OCABRA_ENDPOINT_BASE_URL:-}}" \
      OPENCODE_API_KEY="$${OPENCODE_API_KEY:-}" \
      FREEAPI_BASE_URL="$${FREEAPI_BASE_URL:-}" \
      FREEAPI_API_KEY="$${FREEAPI_API_KEY:-}" \
      python3 - <<'PY'
import json, os, urllib.request
path="/home/coder/.opencode/opencode.json"
try:
    with open(path,"r",encoding="utf-8") as f:
        data=json.load(f)
except Exception:
    data={}
data["disabled_providers"]=["openai","google"]
provider=data.setdefault("provider",{})
base=(os.environ.get("OPENCODE_PROVIDER_URL") or "").strip().rstrip("/")
key=(os.environ.get("OPENCODE_API_KEY") or "").strip()
if key and base:
    provider["litellm"]={
        "npm":"@ai-sdk/openai-compatible",
        "name":"Ocabra",
        "options":{"baseURL":base,"apiKey":key},
        "models":{
            "devstral-small-2:24b":{"name":"Devstral Small 2 24b"},
            "qwen3.6:latest": {"name": "Qwen3.6"},
            "gemma4:26b": {"name": "Gemma 4 26b"},
            "qwen3-coder:30b":{"name":"Qwen3 Coder 30b"},
            "qwen3.5:27b":{"name":"Qwen3.5 27b"},
            "qwen3:32b":{"name":"Qwen3 32b"},
            "qwen3:14b":{"name":"Qwen3 14b"},
            "qwen3:8b":{"name":"Qwen3 8b"},
            "qwen3-embedding:8b": {"name": "Qwen3 Embedding 8b"}
        }
    }
free_base=(os.environ.get("FREEAPI_BASE_URL") or "").strip().rstrip("/")
free_key=(os.environ.get("FREEAPI_API_KEY") or "").strip()
def norm_model_id(raw):
    if not isinstance(raw, str):
        return ""
    s=raw.strip()
    if not s:
        return ""
    if "//" in s:
        s=s.split("//",1)[1]
    if "/" in s:
        s=s.rsplit("/",1)[-1]
    return s
if free_base:
    mids=[]
    for p in ("/v1/models","/models"):
        try:
            headers={"Accept":"application/json"}
            if free_key:
                headers["Authorization"]=f"Bearer {free_key}"
            req=urllib.request.Request(f"{free_base}{p}",headers=headers)
            with urllib.request.urlopen(req,timeout=10) as resp:
                payload=json.loads(resp.read().decode("utf-8","replace"))
            items=payload.get("data", payload if isinstance(payload,list) else [])
            for item in items:
                if isinstance(item,dict):
                    mid=norm_model_id(item.get("id"))
                    if mid.endswith("-ha"):
                        mids.append(mid)
            if mids:
                break
        except Exception:
            continue
    provider["freeapi"]={
        "npm":"@ai-sdk/openai-compatible",
        "name":"FreeAPI",
        "options":{"baseURL":free_base,"apiKey":free_key},
        "models":{mid:{"name":mid} for mid in sorted(set(mids))}
    }
with open(path,"w",encoding="utf-8") as f:
    json.dump(data,f,indent=2,ensure_ascii=False)
PY
      ln -sf /home/coder/.opencode/opencode.json /home/coder/.opencode/config.json || true
      ln -sf /home/coder/.opencode/opencode.json /home/coder/.config/opencode/opencode.json || true
      chown -R "$USER:$USER" /home/coder/.opencode || true
    fi

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

    # GitHub CLI (instalar si falta)
    if ! command -v gh >/dev/null 2>&1; then
      echo ">> Installing GitHub CLI (gh)..."
      sudo install -m 0755 -d /etc/apt/keyrings
      curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo gpg --dearmor -o /etc/apt/keyrings/githubcli-archive-keyring.gpg
      sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
      echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
      sudo apt-get update -y
      sudo DEBIAN_FRONTEND=noninteractive apt-get install -y gh
    fi

    # Codex y Claude CLI (asegurar instalación en Minimal)
    if ! command -v codex >/dev/null 2>&1 || ! command -v claude >/dev/null 2>&1; then
      echo ">> Installing Codex CLI and Claude CLI..."
      sudo install -m 0755 -d /etc/apt/keyrings
      if [ ! -f /etc/apt/keyrings/nodesource.gpg ]; then
        curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg
      fi
      if [ ! -f /etc/apt/sources.list.d/nodesource.list ]; then
        echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_22.x nodistro main" \
          | sudo tee /etc/apt/sources.list.d/nodesource.list > /dev/null
      fi
      sudo apt-get update -y
      sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends nodejs
      sudo npm install -g --omit=dev --no-update-notifier --no-fund @openai/codex @anthropic-ai/claude-code
      sudo npm cache clean --force || true
      hash -r || true
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

  EOT

  env = {
    GIT_AUTHOR_NAME       = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
    GIT_AUTHOR_EMAIL      = data.coder_workspace_owner.me.email
    GIT_COMMITTER_NAME    = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
    GIT_COMMITTER_EMAIL   = data.coder_workspace_owner.me.email
    HOME                  = "/home/coder"
    OPENCODE_PROVIDER_URL     = local.openai_base_url
    OPENCODE_API_KEY          = local.openai_api_key
    OCABRA_ENDPOINT_BASE_URL = local.ocabra_endpoint_base_url
    OCABRA_KEY          = local.ocabra_key
    FREEAPI_BASE_URL          = local.freeapi_base_url
    FREEAPI_KEY_ENDPOINT      = local.freeapi_key_endpoint
    OCABRA_BASE_URL              = local.openai_base_url
    OCABRA_API_KEY               = local.openai_api_key
    AUTO_PROVISION_OCABRA_API_KEY = tostring(local.auto_provision_ocabra_key)
    AUTO_PROVISION_FREEAPI_API_KEY = tostring(local.auto_provision_freeapi_key)
    INSTALL_CLAUDE        = tostring(local.install_claude)
    CODER_USER_EMAIL      = data.coder_workspace_owner.me.email
    CODER_WORKSPACE_NAME       = data.coder_workspace.me.name
  }
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
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/git-config/coder"
  version  = "~> 1.0"
  agent_id = coder_agent.main.id
}

module "git-clone" {
  count    = data.coder_parameter.git_repo_url.value != "" ? data.coder_workspace.me.start_count : 0
  source   = "registry.coder.com/coder/git-clone/coder"
  version  = "~> 1.2"
  agent_id = coder_agent.main.id
  url      = data.coder_parameter.git_repo_url.value
  base_dir = "~/Projects"
}

module "opencode" {
  count        = local.install_claude ? 0 : 1
  source       = "registry.coder.com/coder-labs/opencode/coder"
  version      = "~> 0.1"
  agent_id     = coder_agent.main.id
  workdir      = "/home/coder/"
  report_tasks = false
  cli_app      = true
}

# UI web nativa de OpenCode, además de la interfaz de terminal del módulo.
resource "coder_script" "opencode_web" {
  count              = local.install_claude ? 0 : 1
  agent_id           = coder_agent.main.id
  display_name       = "Start OpenCode Web"
  icon               = "/icon/opencode.svg"
  run_on_start       = true
  start_blocks_login = false
  script             = <<-EOT
    #!/usr/bin/env bash
    set -euo pipefail
    port=4096
    health_url="http://127.0.0.1:$port/global/health"
    log_dir="$HOME/.opencode"
    log_file="$log_dir/opencode-web.log"
    export PATH="$HOME/.opencode/bin:$HOME/.local/bin:$PATH"
    for _ in $(seq 1 120); do
      if command -v opencode >/dev/null 2>&1; then break; fi
      sleep 1
    done
    opencode_bin="$(command -v opencode || true)"
    if [ -z "$opencode_bin" ]; then
      echo "OpenCode no se instaló en dos minutos; consulta ~/.opencode-module" >&2
      exit 1
    fi
    if curl --fail --silent --max-time 2 "$health_url" >/dev/null; then exit 0; fi
    mkdir -p "$log_dir"
    cd /home/coder
    nohup "$opencode_bin" web --hostname 127.0.0.1 --port "$port" >>"$log_file" 2>&1 &
    for _ in $(seq 1 30); do
      if curl --fail --silent --max-time 2 "$health_url" >/dev/null; then exit 0; fi
      sleep 1
    done
    echo "OpenCode Web no respondió en $health_url; consulta $log_file" >&2
    exit 1
  EOT
  depends_on = [module.opencode]
}

resource "coder_app" "opencode_web" {
  count        = local.install_claude ? 0 : 1
  agent_id     = coder_agent.main.id
  slug         = "opencode-web"
  display_name = "OpenCode Web"
  icon         = "/icon/opencode.svg"
  url          = "http://127.0.0.1:4096"
  share        = "owner"
  subdomain    = true
  open_in      = "tab"
  healthcheck {
    url       = "http://127.0.0.1:4096/global/health"
    interval  = 5
    threshold = 6
  }
  depends_on = [coder_script.opencode_web]
}

module "claude-code" {
  count                   = local.install_claude ? 1 : 0
  source                  = "registry.coder.com/coder/claude-code/coder"
  version                 = "~> 4.2"
  agent_id                = coder_agent.main.id
  workdir                 = "/home/coder/Projects"
  claude_code_oauth_token = local.claude_token
  subdomain               = false
  report_tasks            = true
  depends_on              = [module.opencode]
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
  image = local.workspace_image

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
      if [ ! -f /home/coder/.opencode/opencode.json ]; then
        printf '{}' > /home/coder/.opencode/opencode.json
      fi
      ln -sf /home/coder/.opencode/opencode.json /home/coder/.opencode/config.json || true
      ln -sf /home/coder/.opencode/opencode.json /home/coder/.config/opencode/opencode.json || true
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
