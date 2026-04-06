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
  description = "(Optional) Docker socket URI (use unix:// prefix)"
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
# Parámetros
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

data "coder_parameter" "enable_host_network" {
  name         = "02_00_enable_host_network"
  display_name = "[Network] Usar red del host (network_mode=host)"
  description  = "Conecta el contenedor directamente a la red del host (sin mapeo de puertos)."
  type         = "bool"
  default      = false
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

data "coder_parameter" "autoprovision_mks_key" {
  name         = "04_autoprovision_mks_key"
  display_name = "[AI/MakeSpace] Provisionar API key MakeSpace automáticamente"
  description  = "Genera y precarga una API key MakeSpace. La API de MakeSpace es privada en los servidores de MakeSpace."
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
  workspace_image      = "ghcr.io/makespacemadrid/coder-mks-developer-android:latest"
  enable_gpu           = data.coder_parameter.enable_gpu.value
  enable_dri           = data.coder_parameter.enable_dri.value
  enable_host_network  = data.coder_parameter.enable_host_network.value
  persist_home_storage           = data.coder_parameter.persist_home_storage.value
  persist_projects_storage       = data.coder_parameter.persist_projects_storage.value
  host_mount_path                = ""
  host_mount_uid                 = "1000"
  workspace_storage_root         = trimspace(var.users_storage)
  workspace_storage_home         = local.workspace_storage_root != "" ? "${local.workspace_storage_root}/${local.username}/${lower(data.coder_workspace.me.name)}" : ""
  workspace_storage_projects     = local.workspace_storage_root != "" ? "${local.workspace_storage_root}/${local.username}/${lower(data.coder_workspace.me.name)}/Projects" : ""
  home_mount_host_path           = local.persist_home_storage && local.workspace_storage_root != "" ? local.workspace_storage_home : ""
  projects_mount_host_path       = local.persist_projects_storage && local.workspace_storage_root != "" ? local.workspace_storage_projects : ""
  opencode_default_base_url      = trimspace(var.opencode_default_base_url)
  mks_key_endpoint               = trimspace(var.mks_key_endpoint)
  freeapi_base_url               = trimspace(var.freeapi_base_url)
  freeapi_key_endpoint           = trimspace(var.freeapi_key_endpoint)
  home_volume_resolved = "coder-${data.coder_workspace.me.id}-home"
  repo_url          = trimspace(data.coder_parameter.git_repo_url.value)
  repo_name         = local.repo_url != "" ? trimsuffix(basename(local.repo_url), ".git") : ""
  default_repo_path = local.repo_name != "" ? "/home/coder/Projects/${local.repo_name}" : "/home/coder/Projects"
  openai_base_url         = ""
  openai_api_key          = ""
  auto_provision_mks_key  = data.coder_parameter.autoprovision_mks_key.value
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

    # Levantar dbus (necesario para apps Electron)
    if ! pgrep -x dbus-daemon >/dev/null 2>&1; then
      sudo mkdir -p /run/dbus
      sudo dbus-daemon --system --fork || true
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
    if ! pgrep -u "$USER" pulseaudio >/dev/null 2>&1; then
      pulseaudio --start --exit-idle-time=-1 || true
    fi
    # Cargar null-sink virtual para que KasmVNC pueda capturar audio
    # (en contenedores Docker no hay hardware de audio; el null-sink actua como sink por defecto)
    for _pa_try in 1 2 3; do
      if pactl load-module module-null-sink sink_name=vcable sink_properties=device.description="VirtualCable" 2>/dev/null; then
        pactl set-default-sink vcable 2>/dev/null || true
        break
      fi
      sleep 1
    done
    unset _pa_try

    # Configurar Claude Desktop cowork VM para usar HostBackend en Docker
    # COWORK_VM_BACKEND=host evita que Claude Desktop use bwrap (que falla en contenedores)
    # El contenedor Docker ya provee el aislamiento necesario
    COWORK_TAG="# managed-by-android-template: cowork-vm-backend"
    for cowork_file in "$HOME/.xsessionrc" "$HOME/.profile"; do
      if ! grep -qF "$COWORK_TAG" "$cowork_file" 2>/dev/null; then
        printf '%s\nexport COWORK_VM_BACKEND=host\n' "$COWORK_TAG" >> "$cowork_file"
      fi
    done
    mkdir -p "$HOME/.config/environment.d"
    cat > "$HOME/.config/environment.d/claude-cowork.conf" <<EOF
$${COWORK_TAG}
COWORK_VM_BACKEND=host
EOF
    CLAUDE_WRAP_TAG="# managed-by-android-template: claude-desktop-wrapper"
    if [ -x /usr/bin/claude-desktop ] && ! grep -qF "$CLAUDE_WRAP_TAG" /usr/bin/claude-desktop 2>/dev/null; then
      if [ ! -x /usr/bin/claude-desktop.real ]; then
        sudo cp /usr/bin/claude-desktop /usr/bin/claude-desktop.real
      fi
      sudo tee /usr/bin/claude-desktop >/dev/null <<EOF
#!/bin/sh
$${CLAUDE_WRAP_TAG}
exec env ELECTRON_DISABLE_SANDBOX=1 ELECTRON_OZONE_PLATFORM_HINT="$${ELECTRON_OZONE_PLATFORM_HINT:-auto}" COWORK_VM_BACKEND="$${COWORK_VM_BACKEND:-host}" \
  /usr/bin/claude-desktop.real "$$@"
EOF
      sudo chmod 0755 /usr/bin/claude-desktop
    fi

    # Alinear grupos para /dev/kvm sin tocar permisos del host
    if [ -e /dev/kvm ]; then
      kvm_gid=$(stat -c '%g' /dev/kvm 2>/dev/null || echo "")
      if [ -n "$kvm_gid" ]; then
        kvm_group=$(getent group "$kvm_gid" | cut -d: -f1)
        if [ -z "$kvm_group" ]; then
          kvm_group="hostkvm"
          if ! getent group "$kvm_group" >/dev/null; then
            sudo groupadd -g "$kvm_gid" "$kvm_group" || true
          fi
        fi
        sudo usermod -aG "$kvm_group" "$USER" || true
      fi
      if command -v setfacl >/dev/null 2>&1; then
        sudo setfacl -m "u:$USER:rw" /dev/kvm 2>/dev/null || true
      fi
    fi

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

    # Revertir config gestionada de hw3d/zink en workspaces existentes.
    mkdir -p "$HOME/.vnc"
    KASM_USER_CFG="$HOME/.vnc/kasmvnc.yaml"
    KASM_MANAGED_TAG="# managed-by-developerandroid-template: kasmvnc-hw3d"
    if [ -f "$KASM_USER_CFG" ] && grep -qF "$KASM_MANAGED_TAG" "$KASM_USER_CFG"; then
      rm -f "$KASM_USER_CFG"
    fi
    python3 - <<'PY'
import os

path = os.path.expanduser("~/.xsessionrc")
tag = "# managed-by-developerandroid-template: zink-nvidia"
try:
    with open(path, encoding="utf-8") as f:
        lines = f.readlines()
except FileNotFoundError:
    lines = []

if lines:
    cleaned = []
    skip = 0
    for line in lines:
        if skip:
            skip -= 1
            continue
        if line.rstrip("\n") == tag:
            skip = 2
            continue
        cleaned.append(line)
    if cleaned != lines:
        with open(path, "w", encoding="utf-8") as f:
            f.writelines(cleaned)
PY

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
    if [ -n "$${DEFAULT_REPO_PATH:-}" ]; then
      mkdir -p "$DEFAULT_REPO_PATH"
    fi
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
    mkdir -p "$HOME/.codex"
    touch "$HOME/.codex/config.toml"
    # Migrar config antigua de chrome-devtools (formato bash -lc) si existe
    python3 - <<'PY'
import os
path = os.path.expanduser("~/.codex/config.toml")
try:
    with open(path, encoding="utf-8") as f:
        content = f.read()
except FileNotFoundError:
    content = ""
if "[mcp_servers.chrome-devtools]" in content and '"bash"' in content:
    lines = content.splitlines()
    cleaned = []
    i = 0
    removed = False
    while i < len(lines):
        if lines[i].strip() == "[mcp_servers.chrome-devtools]":
            j = i + 1
            block = [lines[i]]
            while j < len(lines) and not lines[j].lstrip().startswith("["):
                block.append(lines[j])
                j += 1
            if '"bash"' in "\n".join(block):
                removed = True
                i = j
                continue
        cleaned.append(lines[i])
        i += 1
    if removed:
        content = "\n".join(cleaned).rstrip("\n")
        with open(path, "w", encoding="utf-8") as f:
            f.write((content + "\n") if content else "")
PY
    if ! grep -q '^\[mcp_servers\.chrome-devtools\]' "$HOME/.codex/config.toml" 2>/dev/null; then
      cat >> "$HOME/.codex/config.toml" <<'CODEXCFG'

[mcp_servers.chrome-devtools]
command = "npx"
args = [
  "-y",
  "chrome-devtools-mcp@latest",
  "--chrome-arg=--use-gl=angle",
  "--chrome-arg=--use-angle=swiftshader",
  "--chrome-arg=--enable-unsafe-swiftshader",
  "--chrome-arg=--no-sandbox",
  "--chrome-arg=--disable-gpu-sandbox",
  "--chrome-arg=--disable-setuid-sandbox",
  "--chrome-arg=--disable-dev-shm-usage",
]
env = { DISPLAY=":1", XAUTHORITY="/home/coder/.Xauthority" }
enabled = true
CODEXCFG
    fi
    if ! grep -q '^\[mcp_servers\.docker\]' "$HOME/.codex/config.toml" 2>/dev/null; then
      cat >> "$HOME/.codex/config.toml" <<'CODEXCFG'

[mcp_servers.docker]
command = "npx"
args = ["-y", "@quantgeekdev/docker-mcp"]
enabled = true
CODEXCFG
    fi
    mkdir -p ~/.opencode ~/.config/opencode
    if [ ! -f ~/.opencode/opencode.json ]; then
      cat > ~/.opencode/opencode.json <<'JSONCFG'
{}
JSONCFG
    fi
    ln -sf ~/.opencode/opencode.json ~/.opencode/config.json || true
    ln -sf ~/.opencode/opencode.json ~/.config/opencode/opencode.json || true

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
    for f in android-studio.desktop code.desktop OpenCode.desktop firefox.desktop google-chrome.desktop; do
      src="/usr/share/applications/$f"
      if [ -f "$src" ] && [ ! -e "$HOME/Desktop/$f" ]; then
        ln -sf "$src" "$HOME/Desktop/$f"
      fi
    done
    chmod +x ~/Desktop/*.desktop 2>/dev/null || true

    # Forzar launcher nativo de Android Studio para evitar studio.sh
    if [ -f /usr/share/applications/android-studio.desktop ]; then
      mkdir -p "$HOME/.local/share/applications"
      cp -f /usr/share/applications/android-studio.desktop "$HOME/.local/share/applications/android-studio.desktop" || true
      sed -i 's|^Exec=.*|Exec=/opt/android-studio/bin/studio|g' "$HOME/.local/share/applications/android-studio.desktop" || true
      chmod +x "$HOME/.local/share/applications/android-studio.desktop" || true
    fi

    MKS_AUTOPROVISIONED_OPENAI="$${MKS_AUTOPROVISIONED_OPENAI:-false}"
    auto_flag="$${AUTO_PROVISION_MKS_API_KEY:-true}"
    if printf '%s' "$auto_flag" | grep -Eq '^(1|true|TRUE|yes|on)$'; then
      if [ -z "$${OPENCODE_PROVIDER_URL:-}" ] && [ -n "$${OPENCODE_DEFAULT_BASE_URL:-}" ]; then
        OPENCODE_PROVIDER_URL="$${OPENCODE_DEFAULT_BASE_URL}"
        export OPENCODE_PROVIDER_URL
      fi
      if [ -z "$${OPENCODE_API_KEY:-}" ]; then
        KEY_ENDPOINT="$${MKS_KEY_ENDPOINT:-}"
        if [ -z "$KEY_ENDPOINT" ]; then
          echo "MKS_KEY_ENDPOINT no configurado; omitiendo autoprovision de key" >&2
        else
        alias="coder-$(tr -dc 0-9 </dev/urandom 2>/dev/null | head -c 8 | sed 's/^$/00000000/')"
        payload=$(printf '{"email":"%s","alias":"%s"}' "$${CODER_USER_EMAIL:-}" "$alias")
        resp=$(curl -fsSL -X POST "$KEY_ENDPOINT" -H "Content-Type: application/json" -d "$payload" 2>/dev/null || true)
        key=$(printf '%s' "$resp" | python3 -c 'import sys,json;x=json.load(sys.stdin);d=x if isinstance(x,dict) else {};dd=d.get("data") if isinstance(d.get("data"),dict) else {};print(d.get("key") or d.get("api_key") or d.get("apiKey") or dd.get("key") or dd.get("api_key") or dd.get("apiKey") or "")' 2>/dev/null || true)
        if [ -n "$key" ]; then
          OPENCODE_API_KEY="$key"
          export OPENCODE_API_KEY
          MKS_AUTOPROVISIONED_OPENAI="true"
          mkdir -p /home/coder/.opencode
          printf "%s" "$key" > /home/coder/.opencode/.latest_mks_key || true
          printf "%s" "$payload" > /home/coder/.opencode/.latest_mks_request || true
        fi
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
  x=json.load(sys.stdin)
  d=x if isinstance(x,dict) else {}
  dd=d.get("data") if isinstance(d.get("data"),dict) else {}
  print(d.get("key") or d.get("api_key") or d.get("apiKey") or dd.get("key") or dd.get("api_key") or dd.get("apiKey") or "")
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
prov_block=data.setdefault("provider",{}).setdefault("litellm",{})
prov_block.setdefault("npm","@ai-sdk/openai-compatible")
prov_block.setdefault("name","MakeSpace IA")
prov=prov_block.setdefault("options",{})
prov["baseURL"]=os.environ.get("OPENCODE_PROVIDER_URL") or os.environ.get("OPENCODE_DEFAULT_BASE_URL","")
prov["apiKey"]=os.environ.get("OPENCODE_API_KEY","")
prov_block.setdefault("models",{
  "devstral-small-2:24b":{"name":"Devstral Small 2 24b"},
  "opencoder-8b-base":{"name":"OpenCoder 8b Base"},
  "qwen2.5-coder:7b-base":{"name":"Qwen2.5 Coder 7b Base"},
  "qwen3-coder:30b":{"name":"Qwen3 Coder 30b"},
  "qwen3.5:27b":{"name":"Qwen3.5 27b"},
  "qwen3:32b":{"name":"Qwen3 32b"},
  "qwen3:14b":{"name":"Qwen3 14b"},
  "qwen3:8b":{"name":"Qwen3 8b"},
  "gpt-oss:20b":{"name":"GPT-OSS 20b"},
  "gpt-oss-safeguard:latest":{"name":"GPT-OSS Safeguard"}
})
os.makedirs(os.path.dirname(path),exist_ok=True)
with open(path,"w") as f:
  json.dump(data,f,indent=2)
PY
ln -sf /home/coder/.opencode/opencode.json /home/coder/.opencode/config.json || true
echo "Nueva key guardada y aplicada"
GENMKS
    sudo chmod +x /usr/local/bin/gen_mks_litellm_key || true

    # Config inicial de OpenCode (opcional)
    if [ -n "$${OPENCODE_PROVIDER_URL:-$${OPENCODE_DEFAULT_BASE_URL:-}}" ] || [ -n "$${MKS_KEY_ENDPOINT:-}" ] || [ -n "$${FREEAPI_BASE_URL:-}" ] || [ -n "$${FREEAPI_KEY_ENDPOINT:-}" ] || [ -n "$${OPENCODE_API_KEY:-}" ] || [ -n "$${FREEAPI_API_KEY:-}" ]; then
      mkdir -p /home/coder/.opencode
      cat > /home/coder/.opencode/opencode.json <<'JSONCFG'
{
  "$schema": "https://opencode.ai/config.json",
  "plugin": [
    "opencode-openai-codex-auth@4.0.2",
    "opencode-gemini-auth@latest",
    "opencode-antigravity-auth@beta",
    "opencode-agent-memory",
    "opencode-mystatus",
    "opencode-handoff"
  ],
  "disabled_providers": ["openai", "google"],
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
    "litellm": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "MakeSpace IA",
      "options": {
        "baseURL": "OPENCODE_PROVIDER_URL_VALUE",
        "apiKey": "OPENCODE_API_KEY_VALUE"
      },
      "models": {
        "devstral-small-2:24b": { "name": "Devstral Small 2 24b" },
        "opencoder-8b-base": { "name": "OpenCoder 8b Base" },
        "qwen2.5-coder:7b-base": { "name": "Qwen2.5 Coder 7b Base" },
        "qwen3-coder:30b": { "name": "Qwen3 Coder 30b" },
        "qwen3.5:27b": { "name": "Qwen3.5 27b" },
        "qwen3:32b": { "name": "Qwen3 32b" },
        "qwen3:14b": { "name": "Qwen3 14b" },
        "qwen3:8b": { "name": "Qwen3 8b" },
        "gpt-oss:20b": { "name": "GPT-OSS 20b" },
        "gpt-oss-safeguard:latest": { "name": "GPT-OSS Safeguard" }
      }
    },
    "google": {
      "models": {
        "antigravity-claude-opus-4-5-thinking": {
          "name": "Claude Opus 4.5 Thinking (Antigravity)",
          "options": { "thinkingBudget": 10000, "includeThoughts": true }
        },
        "antigravity-claude-sonnet-4-5-thinking": {
          "name": "Claude Sonnet 4.5 Thinking (Antigravity)",
          "options": { "thinkingBudget": 5000, "includeThoughts": true }
        },
        "antigravity-gemini-3-pro": {
          "name": "Gemini 3 Pro (Antigravity)",
          "options": { "thinkingLevel": "high", "includeThoughts": true }
        },
        "antigravity-gemini-3-flash": { "name": "Gemini 3 Flash (Antigravity)" },
        "gemini-2.5-pro": {
          "name": "Gemini 2.5 Pro (Free Tier)",
          "options": { "thinkingBudget": 5000, "includeThoughts": true }
        },
        "gemini-2.5-flash": { "name": "Gemini 2.5 Flash (Free Tier)" },
        "gemini-3-pro-preview": {
          "name": "Gemini 3 Pro Preview (Free Tier)",
          "options": { "thinkingLevel": "high", "includeThoughts": true }
        },
        "gemini-3-flash-preview": { "name": "Gemini 3 Flash Preview (Free Tier)" }
      }
    }
  }
}
JSONCFG
      sed -i "s|OPENCODE_PROVIDER_URL_VALUE|$${OPENCODE_PROVIDER_URL}|g" /home/coder/.opencode/opencode.json
      sed -i "s|OPENCODE_API_KEY_VALUE|$${OPENCODE_API_KEY}|g" /home/coder/.opencode/opencode.json
      FREEAPI_BASE="$${FREEAPI_BASE_URL:-}"
      FREEAPI_KEY="$${FREEAPI_API_KEY:-}"
      FREEAPI_BASE="$${FREEAPI_BASE%/}"
      if [ -n "$FREEAPI_BASE" ]; then
        FREEAPI_BASE_URL="$FREEAPI_BASE" FREEAPI_API_KEY="$FREEAPI_KEY" python3 - <<'PY'
import json, os, urllib.request
path = "/home/coder/.opencode/opencode.json"
base_url = (os.environ.get("FREEAPI_BASE_URL") or "").strip().rstrip("/")
api_key = (os.environ.get("FREEAPI_API_KEY") or "").strip()
if not base_url:
    raise SystemExit(0)
with open(path, "r", encoding="utf-8") as f:
    data = json.load(f)
def norm_model_id(raw):
    if not isinstance(raw, str):
        return ""
    s = raw.strip()
    if not s:
        return ""
    if "//" in s:
        s = s.split("//", 1)[1]
    if "/" in s:
        s = s.rsplit("/", 1)[-1]
    return s
model_ids = []
for p in ("/v1/models", "/models"):
    try:
        headers = {"Accept": "application/json"}
        if api_key:
            headers["Authorization"] = f"Bearer {api_key}"
        req = urllib.request.Request(f"{base_url}{p}", headers=headers)
        with urllib.request.urlopen(req, timeout=10) as resp:
            payload = json.loads(resp.read().decode("utf-8", "replace"))
        items = payload.get("data", payload if isinstance(payload, list) else [])
        for item in items:
            if not isinstance(item, dict):
                continue
            mid = norm_model_id(item.get("id"))
            if mid.endswith("-ha"):
                model_ids.append(mid)
        if model_ids:
            break
    except Exception:
        continue
models = {}
for mid in sorted(set(model_ids)):
    models[mid] = {"name": mid}
provider = data.setdefault("provider", {})
provider["freeapi"] = {
    "npm": "@ai-sdk/openai-compatible",
    "name": "FreeAPI",
    "options": {"baseURL": base_url, "apiKey": api_key},
    "models": models,
}
with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
PY
      fi
      ln -sf /home/coder/.opencode/opencode.json /home/coder/.opencode/config.json || true
      chown -R "$USER:$USER" /home/coder/.opencode || true
    fi

    # Configuración de Continue solo cuando la key OpenAI se autoprovisiona
    if [ "$${MKS_AUTOPROVISIONED_OPENAI:-false}" = "true" ] \
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
  EOT

  env = {
    GIT_AUTHOR_NAME       = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
    GIT_AUTHOR_EMAIL      = data.coder_workspace_owner.me.email
    GIT_COMMITTER_NAME    = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
    GIT_COMMITTER_EMAIL   = data.coder_workspace_owner.me.email
    HOME                  = "/home/coder"
    OPENCODE_PROVIDER_URL     = local.openai_base_url
    OPENCODE_API_KEY          = local.openai_api_key
    OPENCODE_DEFAULT_BASE_URL = local.opencode_default_base_url
    MKS_KEY_ENDPOINT          = local.mks_key_endpoint
    FREEAPI_BASE_URL          = local.freeapi_base_url
    FREEAPI_KEY_ENDPOINT      = local.freeapi_key_endpoint
    MKS_BASE_URL              = local.openai_base_url
    MKS_API_KEY               = local.openai_api_key
    AUTO_PROVISION_MKS_API_KEY = tostring(local.auto_provision_mks_key)
    AUTO_PROVISION_FREEAPI_API_KEY = tostring(local.auto_provision_freeapi_key)
    INSTALL_CLAUDE        = tostring(local.install_claude)
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
  version    = "~> 1.1"
  agent_id   = coder_agent.main.id
  folder     = "/home/coder/Projects"
  order      = 1
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

module "coder-login" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/coder-login/coder"
  version  = "~> 1.1"
  agent_id = coder_agent.main.id
}

module "tmux" {
  source   = "registry.coder.com/anomaly/tmux/coder"
  version  = "~> 1.0"
  agent_id = coder_agent.main.id
}

module "kasmvnc" {
  count               = data.coder_workspace.me.start_count
  source              = "registry.coder.com/coder/kasmvnc/coder"
  version             = "~> 1.2"
  agent_id            = coder_agent.main.id
  desktop_environment = "kde"
  subdomain           = true
}

module "filebrowser" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/filebrowser/coder"
  version  = "~> 1.1"
  agent_id = coder_agent.main.id
  folder   = "/home/coder"
}

module "jetbrains" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/jetbrains/coder"
  version  = "~> 1.2"
  agent_id = coder_agent.main.id
  folder   = local.default_repo_path
  default  = ["IU"] # IntelliJ IDEA (instala el plugin Android)
  options  = ["IU"]
  tooltip  = "Necesitas JetBrains Gateway o Coder Desktop para abrir IntelliJ IDEA remoto (puedes añadir el plugin Android)."
}

module "opencode" {
  count        = local.install_claude ? 0 : 1
  source       = "registry.coder.com/coder-labs/opencode/coder"
  version      = "~> 0.1"
  agent_id     = coder_agent.main.id
  workdir      = "/home/coder/"
  report_tasks = true
  cli_app      = false
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

# CONTENEDOR PRINCIPAL
resource "docker_container" "workspace" {
  depends_on = [null_resource.ensure_host_paths]
  image = local.workspace_image

  name     = "coder-${data.coder_workspace_owner.me.name}-${lower(data.coder_workspace.me.name)}"
  hostname = data.coder_workspace.me.name

  user = local.host_mount_path != "" ? local.host_mount_uid : "coder"

  privileged = true # Requerido para KVM

  # Acceso directo a la red del host (sin mapeo de puertos)
  network_mode = local.enable_host_network ? "host" : null

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

  shm_size = 8 * 1024 * 1024 * 1024
  # Permitir FUSE/SSHFS y montajes remotos
  capabilities {
    add = ["SYS_ADMIN"]
  }
  devices {
    host_path      = "/dev/fuse"
    container_path = "/dev/fuse"
    permissions    = "rwm"
  }
  # Mapear el dispositivo KVM para emuladores acelerados
  devices {
    host_path      = "/dev/kvm"
    container_path = "/dev/kvm"
    permissions    = "rwm"
  }
  dynamic "devices" {
    for_each = local.enable_dri ? ["/dev/dri"] : []
    content {
      host_path      = devices.value
      container_path = devices.value
      permissions    = "rwm"
    }
  }

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
