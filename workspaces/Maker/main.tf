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
  default     = ""
  description = "(Optional) Docker socket URI (no se usa por defecto)"
  type        = string
}

variable "users_storage" {
  default     = ""
  description = "Ruta base para storage de usuarios (ej. $TF_VAR_users_storage)."
  type        = string
}

variable "default_repo_url" {
  default     = ""
  description = "Repositorio Git por defecto (ej. $TF_VAR_default_repo_url)."
  type        = string
}

variable "opencode_default_base_url" {
  default     = ""
  description = "Base URL OpenAI-compatible por defecto (si no se define en parámetros)."
  type        = string
}

variable "mks_key_endpoint" {
  default     = ""
  description = "Endpoint para solicitar keys MakeSpace (autoprovision)."
  type        = string
}
# Parámetro para GPUs opcionales
data "coder_parameter" "enable_gpu" {
  name         = "01_enable_gpu"
  display_name = "[Compute] GPU"
  description  = "Expone GPUs al contenedor."
  type         = "bool"
  default      = true
  mutable      = true
}

data "coder_parameter" "git_repo_url" {
  name         = "03_git_repo_url"
  display_name = "[Code] Repositorio Git (opcional)"
  description  = "URL para clonar en ~/Projects/<repo> en el primer arranque."
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

data "coder_parameter" "host_mount_path" {
  name         = "02_03_host_mount_path"
  display_name = "[Storage] Montar ruta host en ~/host"
  description  = "Ruta del host que se monta en /home/coder/host dentro del workspace."
  type         = "string"
  default      = ""
  mutable      = true
}

data "coder_parameter" "host_mount_uid" {
  name         = "02_04_host_mount_uid"
  display_name = "[Storage] Especificar UID para montar la ruta host"
  description  = "UID para ejecutar el contenedor cuando montas ~/host. Por defecto 1000."
  type         = "string"
  default      = "1000"
  mutable      = true
}

data "coder_parameter" "opencode_provider_url" {
  name         = "04_opencode_provider_url"
  display_name = "[AI/OpenAI] Base URL (opcional)"
  description  = "Base URL compatible con OpenAI (ej. https://api.tu-proveedor.com/v1)."
  type         = "string"
  default      = ""
  mutable      = true
}

data "coder_parameter" "opencode_api_key" {
  name         = "04_opencode_api_key"
  display_name = "[AI/OpenAI] API key (opcional)"
  description  = "API key para el proveedor OpenAI compatible. Si la dejas vacía se generará una llave MakeSpace válida 30 días."
  type         = "string"
  default      = ""
  mutable      = true
}

data "coder_parameter" "autoprovision_mks_key" {
  name         = "04_autoprovision_mks_key"
  display_name = "[AI/OpenCode] Provisionar API key MakeSpace automáticamente"
  description  = "Genera y precarga una API key MakeSpace (30 días) cuando no aportas URL/API key."
  type         = "bool"
  default      = true
  mutable      = true
}

data "coder_parameter" "vscode_extensions" {
  name         = "06_vscode_extensions"
  display_name = "[Code] Extensiones VS Code (preinstalar)"
  description  = "Lista separada por comas de extensiones a preinstalar en VS Code/code-server."
  type         = "string"
  default      = join(", ", local.vscode_extensions_default)
  mutable      = true
}

locals {
  username             = data.coder_workspace_owner.me.name
  workspace_image      = "ghcr.io/makespacemadrid/coder-mks-design:latest"
  enable_gpu           = data.coder_parameter.enable_gpu.value
  persist_home_storage           = data.coder_parameter.persist_home_storage.value
  persist_projects_storage       = data.coder_parameter.persist_projects_storage.value
  host_mount_path                = trimspace(data.coder_parameter.host_mount_path.value)
  host_mount_uid                 = trimspace(data.coder_parameter.host_mount_uid.value)
  workspace_storage_root         = trimspace(var.users_storage)
  workspace_storage_home         = local.workspace_storage_root != "" ? "${local.workspace_storage_root}/${local.username}/${lower(data.coder_workspace.me.name)}" : ""
  workspace_storage_projects     = local.workspace_storage_root != "" ? "${local.workspace_storage_root}/${local.username}/${lower(data.coder_workspace.me.name)}/Projects" : ""
  home_mount_host_path           = local.persist_home_storage && local.workspace_storage_root != "" ? local.workspace_storage_home : ""
  projects_mount_host_path       = local.persist_projects_storage && local.workspace_storage_root != "" ? local.workspace_storage_projects : ""
  home_volume_resolved = "coder-${data.coder_workspace.me.id}-home"
  repo_url          = trimspace(data.coder_parameter.git_repo_url.value)
  repo_name         = local.repo_url != "" ? trimsuffix(basename(local.repo_url), ".git") : ""
  default_repo_path = local.repo_name != "" ? "/home/coder/Projects/${local.repo_name}" : "/home/coder/Projects"
  auto_provision_mks_key  = data.coder_parameter.autoprovision_mks_key.value
  opencode_default_base_url      = trimspace(var.opencode_default_base_url)
  mks_key_endpoint               = trimspace(var.mks_key_endpoint)
  continue_default_config = file("${path.module}/continue-config.yaml")
  vscode_extensions_default = [
    "coder.coder-remote",
    "openai.chatgpt",
    "Anthropic.claude-code",
    "Continue.continue"
  ]
  vscode_extensions_input = trimspace(data.coder_parameter.vscode_extensions.value)
  vscode_extensions = local.vscode_extensions_input != "" ? [
    for ext in split(",", local.vscode_extensions_input) : trimspace(ext)
    if trimspace(ext) != ""
  ] : local.vscode_extensions_default
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

    # Asegurar permisos de FUSE
    sudo usermod -aG fuse "$USER" || true
    if [ -e /dev/fuse ]; then
      sudo chown root:fuse /dev/fuse || true
      sudo chmod 666 /dev/fuse || true
    fi

    # Configurar PulseAudio para soporte de audio en KasmVNC
    sudo usermod -aG audio "$USER" || true
    mkdir -p ~/.config/pulse
    if [ ! -f ~/.config/pulse/client.conf ]; then
      cat > ~/.config/pulse/client.conf <<'PULSECFG'
autospawn = yes
daemon-binary = /usr/bin/pulseaudio
enable-shm = false
PULSECFG
    fi
    # Iniciar PulseAudio si no está corriendo
    if ! pgrep -u "$USER" pulseaudio >/dev/null 2>&1; then
      pulseaudio --start --exit-idle-time=-1 || true
    fi

    mkdir -p ~/Projects
    if [ -n "$${DEFAULT_REPO_PATH:-}" ]; then
      mkdir -p "$DEFAULT_REPO_PATH"
    fi
    vscode_bootstrap_marker="$HOME/.vscode_bootstrap_done"
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
    if [ ! -f "$HOME/Projects/.vscode/extensions.json" ]; then
      mkdir -p "$HOME/Projects/.vscode"
      cat > "$HOME/Projects/.vscode/extensions.json" <<'VSCODEEXT'
{
  "recommendations": [
${join(",\n", formatlist("    \"%s\"", local.vscode_extensions))}
  ]
}
VSCODEEXT
    fi
    if [ ! -f "$vscode_bootstrap_marker" ]; then
      vscode_extensions=(
${join("\n", formatlist("        \"%s\"", local.vscode_extensions))}
      )
      installed_any="false"
      if command -v code >/dev/null 2>&1; then
        for ext in "$${vscode_extensions[@]}"; do
          code --install-extension "$ext" --force >/dev/null 2>&1 || true
        done
        installed_any="true"
      fi
      if command -v code-server >/dev/null 2>&1; then
        for ext in "$${vscode_extensions[@]}"; do
          code-server --install-extension "$ext" --force >/dev/null 2>&1 || true
        done
        installed_any="true"
      fi
      if [ "$installed_any" = "true" ]; then
        touch "$vscode_bootstrap_marker"
      fi
    fi

    # KasmVNC busca startkde; en Plasma moderno es startplasma-x11
    if [ -x /usr/bin/startplasma-x11 ] && [ ! -x /usr/bin/startkde ]; then
      sudo ln -sf /usr/bin/startplasma-x11 /usr/bin/startkde
    fi

    # Inicializar /etc/skel la primera vez
    if [ ! -f ~/.init_done ]; then
      cp -rT /etc/skel ~ || true
      touch ~/.init_done
    fi

    # Refrescar accesos directos en el escritorio (si faltan)
    mkdir -p ~/Desktop
    for f in firefox.desktop blender.desktop freecad.desktop inkscape.desktop org.gimp.GIMP.desktop krita.desktop kicad.desktop openscad.desktop prusa-slicer.desktop librecad.desktop meshlab.desktop visicut.desktop geany.desktop appimagepool.desktop orcaslicer.desktop simulide.desktop; do
      src="/usr/share/applications/$f"
      if [ -f "$src" ] && [ ! -e "$HOME/Desktop/$f" ]; then
        ln -sf "$src" "$HOME/Desktop/$f"
      fi
    done
    chmod +x ~/Desktop/*.desktop 2>/dev/null || true

    # Autoprovisionar clave OpenCode MakeSpace si está habilitado
    auto_flag="$${AUTO_PROVISION_MKS_API_KEY:-true}"
    if [ -z "$${OPENCODE_PROVIDER_URL:-}" ] && [ -n "$${OPENCODE_DEFAULT_BASE_URL:-}" ]; then
      OPENCODE_PROVIDER_URL="$${OPENCODE_DEFAULT_BASE_URL}"
      export OPENCODE_PROVIDER_URL
    fi
    if printf '%s' "$auto_flag" | grep -Eq '^(1|true|TRUE|yes|on)$'; then
      MKS_BASE_URL="$${MKS_BASE_URL:-$OPENCODE_PROVIDER_URL}"
      export MKS_BASE_URL
      payload=""
      if [ -z "$${OPENCODE_API_KEY:-}" ]; then
        KEY_ENDPOINT="$${MKS_KEY_ENDPOINT:-}"
        if [ -z "$KEY_ENDPOINT" ]; then
          echo "MKS_KEY_ENDPOINT no configurado; omitiendo autoprovision de key" >&2
        else
        alias="coder-$(tr -dc 0-9 </dev/urandom 2>/dev/null | head -c 8 | sed 's/^$/00000000/')"
        payload=$(printf '{"email":"%s","alias":"%s"}' "$${CODER_USER_EMAIL:-}" "$alias")
        resp=$(curl -fsSL -X POST "$KEY_ENDPOINT" -H "Content-Type: application/json" -d "$payload" 2>/dev/null || true)
        key=$(printf '%s' "$resp" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("key",""))' 2>/dev/null || true)
        if [ -n "$key" ]; then
          OPENCODE_API_KEY="$key"
          export OPENCODE_API_KEY
          MKS_API_KEY="$key"
          export MKS_API_KEY
          mkdir -p /home/coder/.opencode
          printf "%s" "$key" > /home/coder/.opencode/.latest_mks_key || true
          printf "%s" "$payload" > /home/coder/.opencode/.latest_mks_request || true
        fi
        fi
      fi
      if [ -n "$${OPENCODE_API_KEY:-}" ]; then
        export OPENCODE_API_KEY
        MKS_API_KEY="$${MKS_API_KEY:-$OPENCODE_API_KEY}"
        export MKS_API_KEY
        mkdir -p /home/coder/.opencode
        if [ -n "$payload" ] && [ -n "$${OPENCODE_API_KEY:-}" ]; then
          printf "%s" "$${OPENCODE_API_KEY:-}" > /home/coder/.opencode/.latest_mks_key || true
          printf "%s" "$payload" > /home/coder/.opencode/.latest_mks_request || true
        fi
      fi
    fi

    # Propagar variables a nuevas shells interactivas
    if [ -n "$${OPENCODE_PROVIDER_URL:-}" ]; then
      MKS_BASE_URL="$${MKS_BASE_URL:-$OPENCODE_PROVIDER_URL}"
      export MKS_BASE_URL
      if ! grep -q "MKS_BASE_URL=" ~/.bashrc 2>/dev/null; then
        echo "export MKS_BASE_URL=\"$MKS_BASE_URL\"" >> ~/.bashrc
      fi
      if ! grep -q "OPENCODE_PROVIDER_URL=" ~/.bashrc 2>/dev/null; then
        echo "export OPENCODE_PROVIDER_URL=\"$OPENCODE_PROVIDER_URL\"" >> ~/.bashrc
      fi
    fi
    if [ -n "$${OPENCODE_API_KEY:-}" ]; then
      MKS_API_KEY="$${MKS_API_KEY:-$OPENCODE_API_KEY}"
      export MKS_API_KEY
      if ! grep -q "MKS_API_KEY=" ~/.bashrc 2>/dev/null; then
        echo "export MKS_API_KEY=\"$MKS_API_KEY\"" >> ~/.bashrc
      fi
      if ! grep -q "OPENCODE_API_KEY=" ~/.bashrc 2>/dev/null; then
        echo "export OPENCODE_API_KEY=\"$OPENCODE_API_KEY\"" >> ~/.bashrc
      fi
    fi

    # Configuración de Continue solo cuando se autoprovisiona la key OpenAI-compatible
    if printf '%s' "$${AUTO_PROVISION_MKS_API_KEY:-false}" | grep -Eq '^(1|true|TRUE|yes|on)$' \
      && [ -n "$${MKS_API_KEY:-}" ] && [ -n "$${MKS_BASE_URL:-}" ]; then
      if [ ! -f ~/.continue/config.yaml ]; then
        mkdir -p ~/.continue
        cat > ~/.continue/config.yaml <<'CONTINUECFG'
${local.continue_default_config}
CONTINUECFG
        sed -i "s|MKS_BASE_PLACEHOLDER|$${MKS_BASE_URL}|g" ~/.continue/config.yaml
        sed -i "s|MKS_API_KEY_PLACEHOLDER|$${MKS_API_KEY}|g" ~/.continue/config.yaml
      fi
    fi

    # Script para regenerar y aplicar nueva key de MakeSpace
    sudo tee /usr/local/bin/gen_mks_litellm_key >/dev/null <<'GENMKS'
#!/usr/bin/env bash
set -euo pipefail
KEY_ENDPOINT="$${MKS_KEY_ENDPOINT:-}"
PROVIDER="$${OPENCODE_PROVIDER_URL:-$${OPENCODE_DEFAULT_BASE_URL:-}}"
EMAIL="$${CODER_USER_EMAIL:-}"
alias="coder-$(tr -dc 0-9 </dev/urandom 2>/dev/null | head -c 8 | sed 's/^$/00000000/')"
if [ -z "$EMAIL" ]; then
  echo "Falta CODER_USER_EMAIL para solicitar la key" >&2
  exit 1
fi
if [ -z "$KEY_ENDPOINT" ]; then
  echo "Falta MKS_KEY_ENDPOINT para solicitar la key" >&2
  exit 1
fi
payload=$(printf '{"email":"%s","alias":"%s"}' "$EMAIL" "$alias")
resp=$(curl -fsSL -X POST "$KEY_ENDPOINT" -H "Content-Type: application/json" -d "$payload")
key=$(printf '%s' "$resp" | python3 - <<'PY'
import json,sys
try:
  print(json.load(sys.stdin).get("key",""))
except Exception:
  print("")
PY
)
if [ -z "$key" ]; then
  echo "No se obtuvo key de MakeSpace" >&2
  exit 1
fi
export OPENCODE_API_KEY="$key"
export OPENCODE_PROVIDER_URL="$PROVIDER"
mkdir -p /home/coder/.opencode
printf "%s" "$key" > /home/coder/.opencode/.latest_mks_key || true
printf "%s" "$payload" > /home/coder/.opencode/.latest_mks_request || true
python3 - <<'PY'
import json,os
path="/home/coder/.opencode/opencode.json"
data={}
if os.path.exists(path):
  try:
    with open(path) as f:
      data=json.load(f)
  except Exception:
    data={}
prov=data.setdefault("provider",{}).setdefault("custom",{}).setdefault("options",{})
prov["baseURL"]=os.environ.get("OPENCODE_PROVIDER_URL") or os.environ.get("OPENCODE_DEFAULT_BASE_URL","")
prov["apiKey"]=os.environ.get("OPENCODE_API_KEY","")
data.setdefault("default_provider","custom")
os.makedirs(os.path.dirname(path),exist_ok=True)
with open(path,"w") as f:
  json.dump(data,f,indent=2)
PY
ln -sf /home/coder/.opencode/opencode.json /home/coder/.opencode/config.json || true
echo "Nueva key guardada y aplicada"
GENMKS
    sudo chmod +x /usr/local/bin/gen_mks_litellm_key || true

    # Config inicial de OpenCode (opcional)
    if [ -n "$${OPENCODE_PROVIDER_URL:-}" ] && [ -n "$${OPENCODE_API_KEY:-}" ]; then
      mkdir -p /home/coder/.opencode
      cat > /home/coder/.opencode/opencode.json <<'JSONCFG'
{
  "$schema": "https://opencode.ai/config.json",
  "plugin": [
    "opencode-openai-codex-auth@4.0.2"
  ],
  "provider": {
    "openai": {
      "options": {
        "reasoningEffort": "medium",
        "reasoningSummary": "auto",
        "textVerbosity": "medium",
        "include": [
          "reasoning.encrypted_content"
        ],
        "store": false
      },
      "models": {
        "gpt-5.1-codex-low": {
          "name": "GPT 5.1 Codex Low (OAuth)",
          "limit": {
            "context": 272000,
            "output": 128000
          },
          "options": {
            "reasoningEffort": "low",
            "reasoningSummary": "auto",
            "textVerbosity": "medium",
            "include": [
              "reasoning.encrypted_content"
            ],
            "store": false
          }
        },
        "gpt-5.1-codex-medium": {
          "name": "GPT 5.1 Codex Medium (OAuth)",
          "limit": {
            "context": 272000,
            "output": 128000
          },
          "options": {
            "reasoningEffort": "medium",
            "reasoningSummary": "auto",
            "textVerbosity": "medium",
            "include": [
              "reasoning.encrypted_content"
            ],
            "store": false
          }
        },
        "gpt-5.1-codex-high": {
          "name": "GPT 5.1 Codex High (OAuth)",
          "limit": {
            "context": 272000,
            "output": 128000
          },
          "options": {
            "reasoningEffort": "high",
            "reasoningSummary": "detailed",
            "textVerbosity": "medium",
            "include": [
              "reasoning.encrypted_content"
            ],
            "store": false
          }
        },
        "gpt-5.1-codex-max": {
          "name": "GPT 5.1 Codex Max (OAuth)",
          "limit": {
            "context": 272000,
            "output": 128000
          },
          "options": {
            "reasoningEffort": "high",
            "reasoningSummary": "detailed",
            "textVerbosity": "medium",
            "include": [
              "reasoning.encrypted_content"
            ],
            "store": false
          }
        },
        "gpt-5.1-codex-max-low": {
          "name": "GPT 5.1 Codex Max Low (OAuth)",
          "limit": {
            "context": 272000,
            "output": 128000
          },
          "options": {
            "reasoningEffort": "low",
            "reasoningSummary": "detailed",
            "textVerbosity": "medium",
            "include": [
              "reasoning.encrypted_content"
            ],
            "store": false
          }
        },
        "gpt-5.1-codex-max-medium": {
          "name": "GPT 5.1 Codex Max Medium (OAuth)",
          "limit": {
            "context": 272000,
            "output": 128000
          },
          "options": {
            "reasoningEffort": "medium",
            "reasoningSummary": "detailed",
            "textVerbosity": "medium",
            "include": [
              "reasoning.encrypted_content"
            ],
            "store": false
          }
        },
        "gpt-5.1-codex-max-high": {
          "name": "GPT 5.1 Codex Max High (OAuth)",
          "limit": {
            "context": 272000,
            "output": 128000
          },
          "options": {
            "reasoningEffort": "high",
            "reasoningSummary": "detailed",
            "textVerbosity": "medium",
            "include": [
              "reasoning.encrypted_content"
            ],
            "store": false
          }
        },
        "gpt-5.1-codex-max-xhigh": {
          "name": "GPT 5.1 Codex Max Extra High (OAuth)",
          "limit": {
            "context": 272000,
            "output": 128000
          },
          "options": {
            "reasoningEffort": "xhigh",
            "reasoningSummary": "detailed",
            "textVerbosity": "medium",
            "include": [
              "reasoning.encrypted_content"
            ],
            "store": false
          }
        },
        "gpt-5.1-codex-mini-medium": {
          "name": "GPT 5.1 Codex Mini Medium (OAuth)",
          "limit": {
            "context": 272000,
            "output": 128000
          },
          "options": {
            "reasoningEffort": "medium",
            "reasoningSummary": "auto",
            "textVerbosity": "medium",
            "include": [
              "reasoning.encrypted_content"
            ],
            "store": false
          }
        },
        "gpt-5.1-codex-mini-high": {
          "name": "GPT 5.1 Codex Mini High (OAuth)",
          "limit": {
            "context": 272000,
            "output": 128000
          },
          "options": {
            "reasoningEffort": "high",
            "reasoningSummary": "detailed",
            "textVerbosity": "medium",
            "include": [
              "reasoning.encrypted_content"
            ],
            "store": false
          }
        },
        "gpt-5.1-low": {
          "name": "GPT 5.1 Low (OAuth)",
          "limit": {
            "context": 272000,
            "output": 128000
          },
          "options": {
            "reasoningEffort": "low",
            "reasoningSummary": "auto",
            "textVerbosity": "low",
            "include": [
              "reasoning.encrypted_content"
            ],
            "store": false
          }
        },
        "gpt-5.1-medium": {
          "name": "GPT 5.1 Medium (OAuth)",
          "limit": {
            "context": 272000,
            "output": 128000
          },
          "options": {
            "reasoningEffort": "medium",
            "reasoningSummary": "auto",
            "textVerbosity": "medium",
            "include": [
              "reasoning.encrypted_content"
            ],
            "store": false
          }
        },
        "gpt-5.1-high": {
          "name": "GPT 5.1 High (OAuth)",
          "limit": {
            "context": 272000,
            "output": 128000
          },
          "options": {
            "reasoningEffort": "high",
            "reasoningSummary": "detailed",
            "textVerbosity": "high",
            "include": [
              "reasoning.encrypted_content"
            ],
            "store": false
          }
        }
      }
    },
    "custom": {
      "name": "Custom OpenAI Provider",
      "options": {
        "baseURL": "OPENCODE_PROVIDER_URL_VALUE",
        "apiKey": "OPENCODE_API_KEY_VALUE"
      }
    }
  },
  "default_provider": "custom"
}
JSONCFG
      sed -i "s|OPENCODE_PROVIDER_URL_VALUE|$${OPENCODE_PROVIDER_URL}|g" /home/coder/.opencode/opencode.json
      sed -i "s|OPENCODE_API_KEY_VALUE|$${OPENCODE_API_KEY}|g" /home/coder/.opencode/opencode.json
      ln -sf /home/coder/.opencode/opencode.json /home/coder/.opencode/config.json || true
      chown -R "$USER:$USER" /home/coder/.opencode || true
    fi

    # Wrapper ya no necesario
EOT

  env = {
    GIT_AUTHOR_NAME       = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
    GIT_AUTHOR_EMAIL      = data.coder_workspace_owner.me.email
    GIT_COMMITTER_NAME    = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
    GIT_COMMITTER_EMAIL   = data.coder_workspace_owner.me.email
    HOME                  = "/home/coder"
    OPENCODE_PROVIDER_URL     = data.coder_parameter.opencode_provider_url.value
    OPENCODE_API_KEY          = data.coder_parameter.opencode_api_key.value
    OPENCODE_DEFAULT_BASE_URL = local.opencode_default_base_url
    MKS_KEY_ENDPOINT          = local.mks_key_endpoint
    MKS_BASE_URL              = data.coder_parameter.opencode_provider_url.value
    MKS_API_KEY               = data.coder_parameter.opencode_api_key.value
    AUTO_PROVISION_MKS_API_KEY = tostring(local.auto_provision_mks_key)
    CODER_USER_EMAIL      = data.coder_workspace_owner.me.email
    DEFAULT_REPO_PATH     = local.default_repo_path
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
}

# Módulos
module "code-server" {
  count      = data.coder_workspace.me.start_count
  source     = "registry.coder.com/coder/code-server/coder"
  version    = "~> 1.0"
  agent_id   = coder_agent.main.id
  folder     = "/home/coder/Projects"
  extensions = local.vscode_extensions
  order      = 1
}

module "kasmvnc" {
  count               = data.coder_workspace.me.start_count
  source              = "registry.coder.com/coder/kasmvnc/coder"
  version             = "~> 1.2"
  agent_id            = coder_agent.main.id
  desktop_environment = "kde"
  subdomain           = true
}

module "git-clone" {
  count    = data.coder_parameter.git_repo_url.value != "" ? data.coder_workspace.me.start_count : 0
  source   = "registry.coder.com/coder/git-clone/coder"
  version  = "~> 1.2"
  agent_id = coder_agent.main.id
  url      = data.coder_parameter.git_repo_url.value
  base_dir = "~/Projects"
}

module "coder-login" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/coder-login/coder"
  version  = "~> 1.1"
  agent_id = coder_agent.main.id
}

module "filebrowser" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/filebrowser/coder"
  version  = "~> 1.1"
  agent_id = coder_agent.main.id
  folder   = "/home/coder/project"
}

module "opencode" {
  source   = "registry.coder.com/coder-labs/opencode/coder"
  version  = "~> 0.1"
  agent_id = coder_agent.main.id
  workdir  = "/home/coder/"
}

# HOME PERSISTENTE
resource "docker_volume" "home_volume" {
  count = local.home_mount_host_path == "" ? 1 : 0
  name  = local.home_volume_resolved

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

# CONTENEDOR PRINCIPAL DEL WORKSPACE
resource "docker_container" "workspace" {
  depends_on = [null_resource.ensure_host_paths]
  image = local.workspace_image

  name     = "coder-${data.coder_workspace_owner.me.name}-${lower(data.coder_workspace.me.name)}"
  hostname = data.coder_workspace.me.name

  user = local.host_mount_path != "" ? local.host_mount_uid : "coder"

  entrypoint = [
    "sh",
    "-c",
    replace(coder_agent.main.init_script, "/localhost|127\\.0\\.0\\.1/", "host.docker.internal")
  ]

  env = [
    "CODER_AGENT_TOKEN=${coder_agent.main.token}",
    "TZ=Europe/Madrid",
    "NVIDIA_VISIBLE_DEVICES=${local.enable_gpu ? "all" : ""}",
    "NVIDIA_DRIVER_CAPABILITIES=compute,utility,graphics,video"
  ]

  shm_size = 2 * 1024 * 1024 * 1024
  # Permitir FUSE/SSHFS y montajes remotos
  capabilities {
    add = ["SYS_ADMIN"]
  }
  devices {
    host_path      = "/dev/fuse"
    container_path = "/dev/fuse"
    permissions    = "rwm"
  }

  security_opts = ["apparmor:unconfined"]

  dynamic "mounts" {
    for_each = local.home_mount_host_path != "" ? [local.home_mount_host_path] : []
    content {
      target = "/home/coder"
      type   = "bind"
      source = mounts.value
    }
  }

  dynamic "volumes" {
    for_each = local.home_mount_host_path == "" ? [local.home_volume_resolved] : []
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
