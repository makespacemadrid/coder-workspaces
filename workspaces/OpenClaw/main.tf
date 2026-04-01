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
    random = {
      source = "hashicorp/random"
    }
  }
}

variable "docker_socket" {
  default     = "unix:///var/run/docker.sock"
  description = "(Opcional) Docker socket URI (usa unix:// prefix)"
  type        = string
}

variable "opencode_default_base_url" {
  default     = ""
  description = "Base URL OpenAI-compatible por defecto (ej. $TF_VAR_opencode_default_base_url)."
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
  description = "Endpoint para solicitar keys FreeAPI (autoprovision)."
  type        = string
}

data "coder_parameter" "autoprovision_mks_key" {
  name         = "04_autoprovision_mks_key"
  display_name = "[AI/OpenCode] Provisionar API key MakeSpace automáticamente"
  description  = "Genera y precarga una API key MakeSpace (30 días)."
  type         = "bool"
  default      = true
  mutable      = true
}

data "coder_parameter" "autoprovision_freeapi_key" {
  name         = "04_autoprovision_freeapi_key"
  display_name = "[AI/OpenCode] Provisionar API key FreeAPI automáticamente"
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
  description  = "Modelo por defecto de OpenClaw (ej. makespace/qwen3:14b). Si se deja vacío, no se fuerza."
  type         = "string"
  default      = "makespace/qwen3:14b"
  mutable      = true
}

locals {
  username                   = data.coder_workspace_owner.me.name
  workspace_image            = "ghcr.io/makespacemadrid/coder-mks-developer:latest"
  enable_gpu                 = false
  enable_dri                 = false
  home_mount_host_path       = ""
  host_mount_path            = ""
  host_mount_uid             = "1000"
  projects_mount_host_path   = ""
  opencode_default_base_url  = trimspace(var.opencode_default_base_url)
  mks_key_endpoint           = trimspace(var.mks_key_endpoint)
  freeapi_base_url           = trimspace(var.freeapi_base_url)
  freeapi_key_endpoint       = trimspace(var.freeapi_key_endpoint)
  openai_base_url            = local.opencode_default_base_url
  openai_api_key             = ""
  auto_provision_mks_key     = data.coder_parameter.autoprovision_mks_key.value
  auto_provision_freeapi_key = data.coder_parameter.autoprovision_freeapi_key.value
  openclaw_autostart         = data.coder_parameter.openclaw_autostart.value
  openclaw_port              = 3333
  openclaw_gateway_token     = random_password.openclaw_gateway_token.result
  openclaw_workdir           = trimspace(data.coder_parameter.openclaw_workdir.value)
  openclaw_workdir_resolved  = local.openclaw_workdir != "" ? local.openclaw_workdir : "/home/coder/Projects"
  openclaw_default_model     = trimspace(data.coder_parameter.openclaw_default_model.value)
  coder_access_host          = split("/", data.coder_workspace.me.access_url)[2]
  openclaw_ui_gateway_ws_url   = "wss://${local.coder_access_host}/@${data.coder_workspace_owner.me.name}/${data.coder_workspace.me.name}.main/apps/openclaw-ui/?token=${urlencode(local.openclaw_gateway_token)}"
  openclaw_ui_origin_subdomain = "https://openclaw-ui--${lower(data.coder_workspace.me.name)}--${lower(data.coder_workspace_owner.me.name)}.${local.coder_access_host}"
  openclaw_ui_origin_coder     = "https://${local.coder_access_host}"
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

  startup_script = <<-EOT
    set -e

    # Levantar dbus (necesario para apps Electron/navegadores en entorno grafico)
    if ! pgrep -x dbus-daemon >/dev/null 2>&1; then
      sudo mkdir -p /run/dbus
      sudo dbus-daemon --system --fork || true
    fi

    # Audio basico para sesiones KasmVNC
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
    COWORK_TAG="# managed-by-openclaw-template: cowork-vm-backend"
    if ! grep -qF "$COWORK_TAG" "$HOME/.xsessionrc" 2>/dev/null; then
      printf '%s\nexport COWORK_VM_BACKEND=host\n' "$COWORK_TAG" >> "$HOME/.xsessionrc"
    fi

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

      # Activar aceleracion 3D en KasmVNC solo cuando la ruta GBM/DRI es viable.
      # Nota: con driver NVIDIA propietario suele fallar con "Failed to create gbm".
      mkdir -p "$HOME/.vnc"
      KASM_USER_CFG="$HOME/.vnc/kasmvnc.yaml"
      KASM_MANAGED_TAG="# managed-by-openclaw-template: kasmvnc-hw3d"
      HAS_RENDER_NODE=false
      if [ -e /dev/dri/renderD128 ] && [ -r /dev/dri/renderD128 ] && [ -w /dev/dri/renderD128 ]; then
        HAS_RENDER_NODE=true
      fi
      HAS_NVIDIA=false
      if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi >/dev/null 2>&1; then
        HAS_NVIDIA=true
      fi

      if [ "$HAS_RENDER_NODE" = "true" ] && [ "$HAS_NVIDIA" = "false" ]; then
        cat > "$KASM_USER_CFG" <<'KASMGPUCFG'
# managed-by-openclaw-template: kasmvnc-hw3d
desktop:
  gpu:
    hw3d: true
    drinode: /dev/dri/renderD128
KASMGPUCFG
      elif [ "$HAS_NVIDIA" = "true" ]; then
        # NVIDIA propietario: hw3d no soporta DRI3/GBM; configurar Zink (OpenGL→Vulkan→GPU)
        if [ -f "$KASM_USER_CFG" ] && grep -qF "$KASM_MANAGED_TAG" "$KASM_USER_CFG"; then
          rm -f "$KASM_USER_CFG"
        fi
        ZINK_TAG="# managed-by-openclaw-template: zink-nvidia"
        if ! grep -qF "$ZINK_TAG" "$HOME/.xsessionrc" 2>/dev/null; then
          printf '%s\nexport MESA_LOADER_DRIVER_OVERRIDE=zink\nexport GALLIUM_DRIVER=zink\n' \
            "$ZINK_TAG" >> "$HOME/.xsessionrc"
        fi
      else
        # Sin render node accesible: limpiar config gestionada
        if [ -f "$KASM_USER_CFG" ] && grep -qF "$KASM_MANAGED_TAG" "$KASM_USER_CFG"; then
          rm -f "$KASM_USER_CFG"
        fi
      fi
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

    if ! grep -q "/.local/bin" /home/coder/.profile 2>/dev/null; then
      echo 'export PATH="$HOME/.local/bin:$PATH"' >> /home/coder/.profile
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

    # Asegurar permisos de pipx para el usuario actual
    sudo mkdir -p /opt/pipx /opt/pipx/bin
    sudo chown -R "$USER:$USER" /opt/pipx || true

    # Inicializar /etc/skel la primera vez
    if [ ! -f ~/.init_done ]; then
      cp -rT /etc/skel ~ || true
      touch ~/.init_done
    fi

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
          key=$(printf '%s' "$resp" | python3 -c 'import sys,json;x=json.load(sys.stdin);d=x if isinstance(x,dict) else {};dd=d.get("data") if isinstance(d.get("data"),dict) else {};print(d.get("key") or d.get("api_key") or d.get("apiKey") or dd.get("key") or dd.get("api_key") or dd.get("apiKey") or "")' 2>/dev/null || true)
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

    # Propagar variables a nuevas shells interactivas
    if [ -n "$${OPENCODE_PROVIDER_URL:-}" ]; then
      MKS_BASE_URL="$${MKS_BASE_URL:-$OPENCODE_PROVIDER_URL}"
      export MKS_BASE_URL
      OPENAI_BASE_URL="$OPENCODE_PROVIDER_URL"
      export OPENAI_BASE_URL
      if ! grep -q "MKS_BASE_URL=" ~/.bashrc 2>/dev/null; then
        echo "export MKS_BASE_URL=\"$MKS_BASE_URL\"" >> ~/.bashrc
      fi
      if ! grep -q "OPENCODE_PROVIDER_URL=" ~/.bashrc 2>/dev/null; then
        echo "export OPENCODE_PROVIDER_URL=\"$OPENCODE_PROVIDER_URL\"" >> ~/.bashrc
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
      MKS_API_KEY="$${MKS_API_KEY:-$OPENCODE_API_KEY}"
      export MKS_API_KEY
      OPENAI_API_KEY="$${OPENAI_API_KEY:-$OPENCODE_API_KEY}"
      export OPENAI_API_KEY
      if ! grep -q "MKS_API_KEY=" ~/.bashrc 2>/dev/null; then
        echo "export MKS_API_KEY=\"$MKS_API_KEY\"" >> ~/.bashrc
      fi
      if ! grep -q "OPENCODE_API_KEY=" ~/.bashrc 2>/dev/null; then
        echo "export OPENCODE_API_KEY=\"$OPENCODE_API_KEY\"" >> ~/.bashrc
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

    # Navegador para escritorio basico (preferencia: Google Chrome)
    if ! command -v google-chrome >/dev/null 2>&1 && ! command -v chromium >/dev/null 2>&1 && ! command -v chromium-browser >/dev/null 2>&1; then
      echo ">> Installing browser for desktop session..."
      sudo apt-get update -y || true
      sudo apt-get install -y ca-certificates curl gnupg || true
      if [ ! -f /etc/apt/keyrings/google-chrome.gpg ]; then
        sudo install -d -m 0755 /etc/apt/keyrings
        curl -fsSL https://dl.google.com/linux/linux_signing_key.pub | sudo gpg --dearmor -o /etc/apt/keyrings/google-chrome.gpg || true
        sudo chmod a+r /etc/apt/keyrings/google-chrome.gpg || true
      fi
      if [ ! -f /etc/apt/sources.list.d/google-chrome.list ]; then
        echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/google-chrome.gpg] http://dl.google.com/linux/chrome/deb/ stable main" \
          | sudo tee /etc/apt/sources.list.d/google-chrome.list >/dev/null || true
      fi
      sudo apt-get update -y || true
      sudo DEBIAN_FRONTEND=noninteractive apt-get install -y google-chrome-stable || \
      sudo DEBIAN_FRONTEND=noninteractive apt-get install -y chromium-browser || \
      sudo DEBIAN_FRONTEND=noninteractive apt-get install -y chromium || true
    fi

    # OpenClaw requiere Node >= 22.12.0
    ensure_node22=false
    if ! command -v node >/dev/null 2>&1; then
      ensure_node22=true
    else
      node_ver=$(node -p 'process.versions.node' 2>/dev/null || echo "0.0.0")
      min_node_ver="22.12.0"
      if [ "$(printf '%s\n%s\n' "$min_node_ver" "$node_ver" | sort -V | head -n1)" != "$min_node_ver" ]; then
        ensure_node22=true
      fi
    fi
    if [ "$ensure_node22" = "true" ]; then
      echo ">> Installing/upgrading Node.js 22.x (required by OpenClaw)..."
      sudo apt-get update -y
      sudo DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates curl gnupg
      curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
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
      if ! OPENCLAW_NO_PROMPT=1 OPENCLAW_NO_ONBOARD=1 OPENCLAW_USE_GUM=0 curl -fsSL https://openclaw.ai/install.sh | bash -s -- --no-prompt --no-onboard --no-gum; then
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
      openclaw config set gateway.port "$${OPENCLAW_PORT:-3333}" >/dev/null 2>&1 || true
      openclaw config set gateway.auth.mode token >/dev/null 2>&1 || true
      openclaw config set gateway.auth.token "$${OPENCLAW_GATEWAY_TOKEN:-}" >/dev/null 2>&1 || true
      openclaw config set gateway.controlUi.dangerouslyDisableDeviceAuth true >/dev/null 2>&1 || true
      # Coder abre la app por subdominio y también por host principal (path mode).
      # OpenClaw exige orígenes completos aquí; '*' no evita "origin not allowed".
      openclaw config set gateway.controlUi.allowedOrigins '["${local.openclaw_ui_origin_subdomain}","${local.openclaw_ui_origin_coder}"]' >/dev/null 2>&1 || true
      openclaw config set gateway.controlUi.dangerouslyAllowHostHeaderOriginFallback true >/dev/null 2>&1 || true
      openclaw config set gateway.trustedProxies '["*"]' >/dev/null 2>&1 || \
      openclaw config set gateway.trustedProxies "*" >/dev/null 2>&1 || true
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
    "makespace:manual": {
      "type": "api_key",
      "provider": "makespace",
      "key": "$OPENAI_API_KEY"
    }
  },
  "lastGood": {
    "makespace": "makespace:manual"
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
      if [ -n "$${OPENAI_BASE_URL:-}" ]; then
        makespace_provider_json=$(python3 - <<'PY'
import json, os
cfg = {
    "baseUrl": os.environ.get("OPENAI_BASE_URL", ""),
    "auth": "api-key",
    "api": "openai-completions",
    "models": [
        {"id": "qwen3:14b", "name": "qwen3:14b", "reasoning": True, "input": ["text"], "contextWindow": 32768, "maxTokens": 8192},
        {"id": "qwen3:32b", "name": "qwen3:32b", "reasoning": True, "input": ["text"], "contextWindow": 32768, "maxTokens": 8192},
        {"id": "qwen3-coder:30b", "name": "qwen3-coder:30b", "reasoning": True, "input": ["text"], "contextWindow": 32768, "maxTokens": 8192},
        {"id": "gpt-oss:20b", "name": "gpt-oss:20b", "reasoning": False, "input": ["text"], "contextWindow": 32768, "maxTokens": 8192},
    ],
}
print(json.dumps(cfg, separators=(",", ":")))
PY
)
        openclaw config set models.providers.makespace "$makespace_provider_json" >/dev/null 2>&1 || true
      fi
      if [ -n "$${FREEAPI_BASE_URL:-}" ]; then
        freeapi_provider_json=$(python3 - <<'PY'
import json, os, urllib.request

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

base_url = os.environ.get("FREEAPI_BASE_URL", "").strip().rstrip("/")
api_key = os.environ.get("FREEAPI_API_KEY", "").strip()
discovered_ids = []
for path in ("/v1/models", "/models"):
    if not base_url:
        continue
    try:
        headers = {"Accept": "application/json"}
        if api_key:
            headers["Authorization"] = f"Bearer {api_key}"
        req = urllib.request.Request(f"{base_url}{path}", headers=headers)
        with urllib.request.urlopen(req, timeout=10) as resp:
            payload = json.loads(resp.read().decode("utf-8", "replace"))
        items = payload.get("data", payload if isinstance(payload, list) else [])
        for item in items:
            if not isinstance(item, dict):
                continue
            model_id = norm_model_id(item.get("id"))
            if model_id.endswith("-ha"):
                discovered_ids.append(model_id)
        if discovered_ids:
            break
    except Exception:
        continue
discovered_ids = sorted(set(discovered_ids))

# Enriquecer capacidades/tokens/costes desde /model/info (LiteLLM-compatible).
meta = {}
for path in ("/v1/model/info", "/model/info"):
    if not base_url:
        continue
    try:
        headers = {"Accept": "application/json"}
        if api_key:
            headers["Authorization"] = f"Bearer {api_key}"
        req = urllib.request.Request(f"{base_url}{path}", headers=headers)
        with urllib.request.urlopen(req, timeout=12) as resp:
            payload = json.loads(resp.read().decode("utf-8", "replace"))
        rows = payload.get("data", payload if isinstance(payload, list) else [])
        for row in rows:
            if not isinstance(row, dict):
                continue
            model_id = norm_model_id(row.get("model_name") or row.get("id"))
            if not model_id.endswith("-ha"):
                continue
            mi = row.get("model_info", {}) if isinstance(row.get("model_info"), dict) else {}
            lp = row.get("litellm_params", {}) if isinstance(row.get("litellm_params"), dict) else {}
            tags = lp.get("tags", [])
            tags = tags if isinstance(tags, list) else []

            entry = meta.setdefault(model_id, {
                "contextWindow": 0,
                "maxTokens": 0,
                "reasoning": False,
                "input": {"text"},
                "cost": {"input": None, "output": None, "cacheRead": None, "cacheWrite": None},
            })

            # Tokens
            in_tok = mi.get("max_input_tokens") or mi.get("context_window") or mi.get("max_tokens")
            out_tok = (
                mi.get("max_output_tokens")
                or mi.get("max_completion_tokens")
                or mi.get("output_tokens")
                or mi.get("max_tokens")
            )
            for val in (in_tok,):
                if isinstance(val, int) and val > entry["contextWindow"]:
                    entry["contextWindow"] = val
            for val in (out_tok,):
                if isinstance(val, int) and val > entry["maxTokens"]:
                    entry["maxTokens"] = val

            # Capacidades
            tagset = {t for t in tags if isinstance(t, str)}
            if (
                any("capability:thinking" == t for t in tagset)
                or bool(lp.get("merge_reasoning_content_in_choices"))
                or bool(mi.get("supports_reasoning"))
            ):
                entry["reasoning"] = True
            if any("capability:vision" == t or "capability:image" == t for t in tagset) or bool(mi.get("supports_vision")):
                entry["input"].add("image")
            if any("capability:audio" == t for t in tagset) or bool(mi.get("supports_audio_input")):
                entry["input"].add("audio")

            # Costes
            cmap = {
                "input": lp.get("input_cost_per_token"),
                "output": lp.get("output_cost_per_token"),
                "cacheRead": lp.get("cache_read_input_token_cost"),
                "cacheWrite": lp.get("cache_creation_input_token_cost"),
            }
            for k, v in cmap.items():
                if isinstance(v, (int, float)):
                    entry["cost"][k] = v
    except Exception:
        continue

models = []
for model_id in discovered_ids:
    m = meta.get(model_id, {})
    context_window = m.get("contextWindow") if isinstance(m.get("contextWindow"), int) and m.get("contextWindow", 0) > 0 else 32768
    max_tokens = m.get("maxTokens") if isinstance(m.get("maxTokens"), int) and m.get("maxTokens", 0) > 0 else 8192
    reasoning = bool(m.get("reasoning")) or model_id.startswith("qwen3")
    inputs = sorted(m.get("input", {"text"})) if isinstance(m.get("input"), set) else ["text"]
    cost = m.get("cost") if isinstance(m.get("cost"), dict) else {}
    for key in ("input", "output", "cacheRead", "cacheWrite"):
        if not isinstance(cost.get(key), (int, float)):
            cost[key] = 0
    models.append({
        "id": model_id,
        "name": model_id,
        "reasoning": reasoning,
        "input": inputs,
        "contextWindow": context_window,
        "maxTokens": max_tokens,
        "cost": cost,
    })
cfg = {
    "baseUrl": base_url,
    "auth": "api-key",
    "api": "openai-completions",
    "models": models,
}
print(json.dumps(cfg, separators=(",", ":")))
PY
)
        openclaw config set models.providers.freeapi "$freeapi_provider_json" >/dev/null 2>&1 || true
      fi
      # Exponer en el selector de agentes todos los modelos iniciales configurados.
      has_makespace=0
      has_freeapi=0
      if openclaw config get models.providers.makespace >/dev/null 2>&1; then
        has_makespace=1
      fi
      if openclaw config get models.providers.freeapi >/dev/null 2>&1; then
        has_freeapi=1
      fi
      freeapi_models_json="[]"
      if [ "$has_freeapi" = "1" ]; then
        freeapi_provider_cfg_json=$(openclaw config get models.providers.freeapi --json 2>/dev/null || echo "{}")
        freeapi_models_json=$(FREEAPI_PROVIDER_CFG_JSON="$freeapi_provider_cfg_json" python3 - <<'PY'
import json, os
try:
    cfg = json.loads(os.environ.get("FREEAPI_PROVIDER_CFG_JSON", "{}"))
except Exception:
    cfg = {}
models = cfg.get("models", [])
ids = []
for item in models:
    if isinstance(item, dict):
        model_id = item.get("id")
        if isinstance(model_id, str) and model_id.endswith("-ha"):
            ids.append(model_id)
print(json.dumps(sorted(set(ids)), separators=(",", ":")))
PY
)
      fi
      allowed_models_json=$(HAS_MAKESPACE="$has_makespace" HAS_FREEAPI="$has_freeapi" FREEAPI_MODELS_JSON="$freeapi_models_json" python3 - <<'PY'
import json, os
allowed = {}
if os.environ.get("HAS_MAKESPACE") == "1":
    for model in ("qwen3:14b", "qwen3:32b", "qwen3-coder:30b", "gpt-oss:20b"):
        allowed[f"makespace/{model}"] = {}
if os.environ.get("HAS_FREEAPI") == "1":
    try:
        freeapi_models = json.loads(os.environ.get("FREEAPI_MODELS_JSON", "[]"))
    except Exception:
        freeapi_models = []
    for model in freeapi_models:
        if isinstance(model, str) and model.endswith("-ha"):
            allowed[f"freeapi/{model}"] = {}
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
        if ! printf '%s' "$target_model" | grep -q '/'; then
          target_model="makespace/$target_model"
        fi
        target_provider="$${target_model%%/*}"
        if openclaw config get "models.providers.$target_provider" >/dev/null 2>&1; then
          openclaw models set "$target_model" >/dev/null 2>&1 || true
        else
          echo "WARN: modelo por defecto '$target_model' omitido: provider '$target_provider' no configurado." >&2
        fi
      fi
    fi

    # Persistir configuración de OpenClaw para invocaciones manuales posteriores
    mkdir -p "$HOME/.local/state/openclaw"
    cat > "$HOME/.local/state/openclaw/runtime.env" <<EOF
OPENCLAW_PORT="$${OPENCLAW_PORT:-3333}"
OPENCLAW_GATEWAY_TOKEN="$${OPENCLAW_GATEWAY_TOKEN:-}"
OPENCLAW_WORKDIR="$${OPENCLAW_WORKDIR:-$HOME/Projects}"
OPENCLAW_DEFAULT_MODEL="$${OPENCLAW_DEFAULT_MODEL:-makespace/qwen3:14b}"
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
    GIT_AUTHOR_NAME                 = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
    GIT_AUTHOR_EMAIL                = data.coder_workspace_owner.me.email
    GIT_COMMITTER_NAME              = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
    GIT_COMMITTER_EMAIL             = data.coder_workspace_owner.me.email
    HOME                            = "/home/coder"
    OPENCODE_PROVIDER_URL           = local.openai_base_url
    OPENCODE_API_KEY                = local.openai_api_key
    OPENCODE_DEFAULT_BASE_URL       = local.opencode_default_base_url
    MKS_KEY_ENDPOINT                = local.mks_key_endpoint
    FREEAPI_BASE_URL                = local.freeapi_base_url
    FREEAPI_KEY_ENDPOINT            = local.freeapi_key_endpoint
    MKS_BASE_URL                    = local.openai_base_url
    MKS_API_KEY                     = local.openai_api_key
    AUTO_PROVISION_MKS_API_KEY      = tostring(local.auto_provision_mks_key)
    AUTO_PROVISION_FREEAPI_API_KEY  = tostring(local.auto_provision_freeapi_key)
    CODER_USER_EMAIL                = data.coder_workspace_owner.me.email
    OPENCLAW_AUTOSTART              = tostring(local.openclaw_autostart)
    OPENCLAW_PORT                   = tostring(local.openclaw_port)
    OPENCLAW_GATEWAY_TOKEN          = local.openclaw_gateway_token
    OPENCLAW_WORKDIR                = local.openclaw_workdir_resolved
    OPENCLAW_DEFAULT_MODEL          = local.openclaw_default_model
  }
}

module "kasmvnc" {
  count               = data.coder_workspace.me.start_count
  source              = "registry.coder.com/coder/kasmvnc/coder"
  version             = "~> 1.2"
  agent_id            = coder_agent.main.id
  desktop_environment = "xfce"
  subdomain           = true
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

resource "docker_container" "workspace" {
  image      = local.workspace_image

  name     = "coder-${data.coder_workspace_owner.me.name}-${lower(data.coder_workspace.me.name)}"
  hostname = data.coder_workspace.me.name

  user = "coder"

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
