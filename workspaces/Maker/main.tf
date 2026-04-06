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
# Parámetro para GPUs opcionales
data "coder_parameter" "enable_gpu" {
  name         = "01_enable_gpu"
  display_name = "[Compute] GPU"
  description  = "Expone GPUs al contenedor."
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

data "coder_parameter" "opencode_default_model" {
  name         = "04_opencode_default_model"
  display_name = "[AI/OpenCode] Modelo por defecto"
  description  = "Modelo por defecto de OpenCode. En Auto: si hay FreeAPI se usa freeapi/glm-5-ha; si no, litellm/qwen3.5:27b."
  type         = "string"
  form_type    = "dropdown"
  default      = "auto"
  mutable      = true
  option {
    name  = "Auto (regla Maker)"
    value = "auto"
  }
  option {
    name  = "MakeSpace: qwen3.5:27b"
    value = "litellm/qwen3.5:27b"
  }
  option {
    name  = "FreeAPI: glm-5-ha"
    value = "freeapi/glm-5-ha"
  }
}

locals {
  username             = data.coder_workspace_owner.me.name
  workspace_image      = "ghcr.io/makespacemadrid/coder-mks-design:latest"
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
  home_volume_resolved = "coder-${data.coder_workspace.me.id}-home"
  repo_url          = trimspace(data.coder_parameter.git_repo_url.value)
  repo_name         = local.repo_url != "" ? trimsuffix(basename(local.repo_url), ".git") : ""
  default_repo_path = local.repo_name != "" ? "/home/coder/Projects/${local.repo_name}" : "/home/coder/Projects"
  auto_provision_mks_key  = data.coder_parameter.autoprovision_mks_key.value
  auto_provision_freeapi_key = data.coder_parameter.autoprovision_freeapi_key.value
  opencode_default_model      = trimspace(data.coder_parameter.opencode_default_model.value)
  opencode_default_base_url      = trimspace(var.opencode_default_base_url)
  mks_key_endpoint               = trimspace(var.mks_key_endpoint)
  freeapi_base_url               = trimspace(var.freeapi_base_url)
  freeapi_key_endpoint           = trimspace(var.freeapi_key_endpoint)
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

    # Asegurar soporte de user namespaces para Steam/Flatpak
    if ! command -v newuidmap >/dev/null 2>&1; then
      echo "WARN: uidmap no disponible; Steam/Flatpak pueden fallar" >&2
    fi
    if [ -w /etc/subuid ] && ! grep -q "^$USER:" /etc/subuid 2>/dev/null; then
      echo "$USER:100000:65536" | sudo tee -a /etc/subuid >/dev/null
    fi
    if [ -w /etc/subgid ] && ! grep -q "^$USER:" /etc/subgid 2>/dev/null; then
      echo "$USER:100000:65536" | sudo tee -a /etc/subgid >/dev/null
    fi

    # Asegurar permisos de FUSE
    if ! getent group fuse >/dev/null 2>&1; then
      sudo groupadd -r fuse || true
    fi
    sudo usermod -aG fuse "$USER" || true
    if [ -e /dev/fuse ] && getent group fuse >/dev/null 2>&1; then
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
    COWORK_TAG="# managed-by-maker-template: cowork-vm-backend"
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
    CLAUDE_WRAP_TAG="# managed-by-maker-template: claude-desktop-wrapper"
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
      KASM_MANAGED_TAG="# managed-by-maker-template: kasmvnc-hw3d"
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
# managed-by-maker-template: kasmvnc-hw3d
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
        ZINK_TAG="# managed-by-maker-template: zink-nvidia"
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

    # Symlink de opencode cuando se instale bajo /root (start script espera /home/coder/.opencode)
    if [ -d /root/.opencode ] && [ ! -e /home/coder/.opencode ]; then
      sudo ln -s /root/.opencode /home/coder/.opencode || true
    fi

    # Configurar PATH para OpenCode CLI y .local/bin
    mkdir -p /home/coder/.local/bin
    if [ ! -f /home/coder/.profile ]; then
      echo '# ~/.profile: executed by the command interpreter for login shells.' > /home/coder/.profile
      echo 'if [ -n "$BASH_VERSION" ]; then' >> /home/coder/.profile
      echo '    if [ -f "$HOME/.bashrc" ]; then' >> /home/coder/.profile
      echo '        . "$HOME/.bashrc"' >> /home/coder/.profile
      echo '    fi' >> /home/coder/.profile
      echo 'fi' >> /home/coder/.profile
    fi
    if ! grep -q "/.opencode/bin" /home/coder/.profile 2>/dev/null; then
      echo 'export PATH="$HOME/.opencode/bin:$HOME/.local/bin:$PATH"' >> /home/coder/.profile
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
    mkdir -p ~/.opencode ~/.config/opencode
    if [ ! -f ~/.opencode/opencode.json ]; then
      cat > ~/.opencode/opencode.json <<'JSONCFG'
{}
JSONCFG
    fi
    ln -sf ~/.opencode/opencode.json ~/.opencode/config.json || true
    ln -sf ~/.opencode/opencode.json ~/.config/opencode/opencode.json || true

    # MCP setup para herramientas Maker (Blender, FreeCAD, KiCad, Inkscape, GIMP)
    mkdir -p "$HOME/.local/bin" "$HOME/.local/share/mcp-servers" "$HOME/.config/inkscape/extensions"
    clone_or_update() {
      repo_url="$1"
      target_dir="$2"
      if [ -d "$target_dir/.git" ]; then
        git -C "$target_dir" pull --ff-only >/dev/null 2>&1 || true
      else
        rm -rf "$target_dir"
        git clone --depth 1 "$repo_url" "$target_dir" >/dev/null 2>&1 || true
      fi
    }
    clone_or_update "https://github.com/lamaalrajih/kicad-mcp.git" "$HOME/.local/share/mcp-servers/kicad-mcp"
    clone_or_update "https://github.com/maorcc/gimp-mcp.git" "$HOME/.local/share/mcp-servers/gimp-mcp"
    clone_or_update "https://github.com/Shriinivas/inkmcp.git" "$HOME/.config/inkscape/extensions/inkmcp"
    clone_or_update "https://github.com/neka-nat/freecad-mcp.git" "$HOME/.local/share/mcp-servers/freecad-mcp"
    clone_or_update "https://github.com/ahujasid/blender-mcp.git" "$HOME/.local/share/mcp-servers/blender-mcp"

    # Blender MCP addon preinstalado y habilitado en el perfil del usuario.
    BLENDER_MM="$(blender --version 2>/dev/null | awk 'NR==1 { split($2, v, "."); print v[1] "." v[2] }')"
    if [ -n "$BLENDER_MM" ] && [ -f "$HOME/.local/share/mcp-servers/blender-mcp/addon.py" ]; then
      BLENDER_ADDONS_DIR="$HOME/.config/blender/$BLENDER_MM/scripts/addons"
      mkdir -p "$BLENDER_ADDONS_DIR"
      cp -f "$HOME/.local/share/mcp-servers/blender-mcp/addon.py" "$BLENDER_ADDONS_DIR/blender_mcp.py"
      blender --background --factory-startup --python-expr "import bpy; bpy.ops.preferences.addon_enable(module='blender_mcp'); bpy.ops.wm.save_userpref()" >/dev/null 2>&1 || true
    fi

    mkdir -p "$HOME/.local/share/FreeCAD/Mod" "$HOME/.FreeCAD/Mod"
    if [ -d "$HOME/.local/share/mcp-servers/freecad-mcp/addon/FreeCADMCP" ]; then
      rm -rf "$HOME/.local/share/FreeCAD/Mod/FreeCADMCP" "$HOME/.FreeCAD/Mod/FreeCADMCP"
      cp -r "$HOME/.local/share/mcp-servers/freecad-mcp/addon/FreeCADMCP" "$HOME/.local/share/FreeCAD/Mod/FreeCADMCP"
      cp -r "$HOME/.local/share/mcp-servers/freecad-mcp/addon/FreeCADMCP" "$HOME/.FreeCAD/Mod/FreeCADMCP"
    fi
    # Instalación robusta del entrypoint de Inkscape MCP (evita problemas con symlinks en algunos entornos).
    if [ -f "$HOME/.config/inkscape/extensions/inkmcp/inkscape_mcp.inx" ]; then
      cp -f "$HOME/.config/inkscape/extensions/inkmcp/inkscape_mcp.inx" "$HOME/.config/inkscape/extensions/inkscape_mcp.inx"
    fi
    cat > "$HOME/.config/inkscape/extensions/inkscape_mcp.py" <<'INKWRAP'
#!/usr/bin/env python3
import os
import runpy
import sys

base = os.path.expanduser("~/.config/inkscape/extensions")
repo = os.path.join(base, "inkmcp")
for p in (base, repo):
    if p not in sys.path:
        sys.path.insert(0, p)

target = os.path.join(repo, "inkscape_mcp.py")
if not os.path.isfile(target):
    raise SystemExit(f"inkscape_mcp.py no encontrado en {target}")

runpy.run_path(target, run_name="__main__")
INKWRAP
    chmod +x "$HOME/.config/inkscape/extensions/inkscape_mcp.py"

    INK_RUN="$HOME/.config/inkscape/extensions/inkmcp/inkmcp/run_inkscape_mcp.sh"
    [ -f "$INK_RUN" ] && chmod +x "$INK_RUN" || true
    chmod +x "$HOME/.config/inkscape/extensions/inkmcp/inkmcp/inkmcpcli.py" "$HOME/.config/inkscape/extensions/inkmcp/inkmcp/inkscape_mcp_server.py" "$HOME/.config/inkscape/extensions/inkmcp/inkmcp/main.py" 2>/dev/null || true

    if command -v uv >/dev/null 2>&1; then
      [ -d "$HOME/.local/share/mcp-servers/kicad-mcp" ] && uv sync --directory "$HOME/.local/share/mcp-servers/kicad-mcp" >/dev/null 2>&1 || true
      [ -d "$HOME/.local/share/mcp-servers/gimp-mcp" ] && uv sync --directory "$HOME/.local/share/mcp-servers/gimp-mcp" >/dev/null 2>&1 || true
    fi
    if [ -f "$HOME/.config/inkscape/extensions/inkmcp/inkmcp/requirements.txt" ]; then
      python3 -m pip install --user --quiet --break-system-packages -r "$HOME/.config/inkscape/extensions/inkmcp/inkmcp/requirements.txt" >/dev/null 2>&1 || true
    fi

    cat > "$HOME/.local/bin/inkscape-mcp-launcher" <<'INKLAUNCH'
#!/usr/bin/env bash
set -euo pipefail
BASE="$HOME/.config/inkscape/extensions/inkmcp/inkmcp"
if [ ! -f "$BASE/main.py" ]; then
  echo "inkmcp no encontrado en $BASE" >&2
  exit 1
fi
export XDG_RUNTIME_DIR="$${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export DBUS_SESSION_BUS_ADDRESS="$${DBUS_SESSION_BUS_ADDRESS:-unix:path=$${XDG_RUNTIME_DIR}/bus}"
if ! python3 -c 'import fastmcp' >/dev/null 2>&1; then
  python3 -m pip install --user --quiet --break-system-packages fastmcp
fi
python3 "$BASE/main.py"
INKLAUNCH
    chmod +x "$HOME/.local/bin/inkscape-mcp-launcher"

    mkdir -p "$HOME/.codex"
    touch "$HOME/.codex/config.toml"
    if ! grep -q '^\[mcp_servers\.blender\]' "$HOME/.codex/config.toml" 2>/dev/null; then
      cat >> "$HOME/.codex/config.toml" <<'CODEXMCP'

[mcp_servers.blender]
command = "uvx"
args = ["blender-mcp"]

[mcp_servers.freecad]
command = "uvx"
args = ["freecad-mcp"]

[mcp_servers.kicad]
command = "uv"
args = ["run", "--directory", "/home/coder/.local/share/mcp-servers/kicad-mcp", "main.py"]

[mcp_servers.gimp]
command = "uv"
args = ["run", "--directory", "/home/coder/.local/share/mcp-servers/gimp-mcp", "gimp_mcp_server.py"]

[mcp_servers.inkscape]
command = "/home/coder/.local/bin/inkscape-mcp-launcher"
CODEXMCP
    fi

    python3 - <<'PY'
import json
import os
import shutil

home = os.path.expanduser("~")
kicad_dir = os.path.join(home, ".local", "share", "mcp-servers", "kicad-mcp")
gimp_dir = os.path.join(home, ".local", "share", "mcp-servers", "gimp-mcp")
ink_launcher = os.path.join(home, ".local", "bin", "inkscape-mcp-launcher")

claude_servers = {
    "blender": {"command": "uvx", "args": ["blender-mcp"]},
    "freecad": {"command": "uvx", "args": ["freecad-mcp"]},
    "kicad": {"command": "uv", "args": ["run", "--directory", kicad_dir, "main.py"]},
    "gimp": {"command": "uv", "args": ["run", "--directory", gimp_dir, "gimp_mcp_server.py"]},
    "inkscape": {"command": ink_launcher},
}

opencode_servers = {
    "blender": {"type": "local", "enabled": True, "command": ["uvx", "blender-mcp"]},
    "freecad": {"type": "local", "enabled": True, "command": ["uvx", "freecad-mcp"]},
    "kicad": {"type": "local", "enabled": True, "command": ["uv", "run", "--directory", kicad_dir, "main.py"]},
    "gimp": {"type": "local", "enabled": True, "command": ["uv", "run", "--directory", gimp_dir, "gimp_mcp_server.py"]},
    "inkscape": {"type": "local", "enabled": True, "command": [ink_launcher]},
}

def load_json(path):
    if not os.path.exists(path):
        return {}
    try:
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return {}

def save_json(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2)

claude_path = os.path.join(home, ".claude.json")
claude_cfg = load_json(claude_path)
claude_cfg.setdefault("mcpServers", {}).update(claude_servers)
save_json(claude_path, claude_cfg)

claude_desktop_path = os.path.join(home, ".config", "Claude", "claude_desktop_config.json")
claude_desktop_cfg = load_json(claude_desktop_path)
claude_desktop_cfg.setdefault("mcpServers", {}).update(claude_servers)
save_json(claude_desktop_path, claude_desktop_cfg)

for path in (
    os.path.join(home, ".opencode", "opencode.json"),
    os.path.join(home, ".config", "opencode", "opencode.json"),
):
    cfg = load_json(path)
    mcp_cfg = cfg.setdefault("mcp", {})
    mcp_cfg.update(opencode_servers)
    if shutil.which("coder") is None and "coder" in mcp_cfg:
        mcp_cfg["coder"] = {"enabled": False}
    save_json(path, cfg)
PY

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
    for f in firefox.desktop blender.desktop freecad.desktop inkscape.desktop org.gimp.GIMP.desktop krita.desktop kicad.desktop openscad.desktop prusa-slicer.desktop librecad.desktop meshlab.desktop visicut.desktop geany.desktop appimagepool.desktop orcaslicer.desktop simulide.desktop OpenCode.desktop; do
      src="/usr/share/applications/$f"
      if [ -f "$src" ] && [ ! -e "$HOME/Desktop/$f" ]; then
        ln -sf "$src" "$HOME/Desktop/$f"
      fi
    done
    chmod +x ~/Desktop/*.desktop 2>/dev/null || true

    # Guía rápida MCP en el escritorio.
    cat > "$HOME/Desktop/MCPS-README.md" <<'MCPREADME'
# MCPs en Maker: guía rápida

Este workspace trae MCPs de:
- Blender
- FreeCAD
- KiCad
- Inkscape
- GIMP

## Comprobar estado

```bash
codex mcp list
claude mcp list
opencode mcp list
```

## Blender (paso obligatorio)

1. Abre Blender.
2. Confirma addon activo: `Blender MCP` (`blender_mcp`).
3. En la vista 3D pulsa `N` y abre la pestaña `BlenderMCP`.
4. Pulsa `Connect to MCP server` / `Start Server`.

Si no haces este paso, verás: "Blender no está conectado".

## FreeCAD

- El addon `FreeCADMCP` queda instalado en:
  - `~/.local/share/FreeCAD/Mod/FreeCADMCP`
  - `~/.FreeCAD/Mod/FreeCADMCP`
- Abre FreeCAD, selecciona el workbench MCP Addon y dale a Start RPC server.

## Inkscape

- Inkscape MCP necesita Inkscape abierto para operaciones sobre el documento activo.
- La extensión `inkmcp` se instala en: `~/.config/inkscape/extensions/inkmcp`
- Launcher MCP usado por los clientes: `~/.local/bin/inkscape-mcp-launcher`
- Si el estado sale `failed`, abre Inkscape y vuelve a lanzar el comando del cliente MCP.

## GIMP (paso obligatorio)

1. Instala el plugin de GIMP MCP (primera vez):
   ```bash
   mkdir -p ~/.config/GIMP/3.0/plug-ins/gimp-mcp-plugin
   cp ~/.local/share/mcp-servers/gimp-mcp/gimp-mcp-plugin.py ~/.config/GIMP/3.0/plug-ins/gimp-mcp-plugin/
   chmod +x ~/.config/GIMP/3.0/plug-ins/gimp-mcp-plugin/gimp-mcp-plugin.py
   ```
2. Reinicia GIMP.
3. Abre una imagen.
4. En GIMP: `Tools > Start MCP Server`.
5. Deja GIMP abierto mientras uses herramientas MCP.

## KiCad

- Si una operación requiere UI/contexto del proyecto, abre KiCad primero.

## Prueba rápida sugerida

1. Abre Blender y arranca su servidor MCP.
2. Ejecuta: `claude mcp list` (debe salir `blender ... ✓ Connected`).
3. Pide al agente crear un cubo y guardar en:
   `/home/coder/Projects/mcp-blender-test.blend`
MCPREADME
    chown "$USER:$USER" "$HOME/Desktop/MCPS-README.md" || true

    # Autoprovisionar clave OpenCode MakeSpace si está habilitado
    echo "Aviso IA: la API de MakeSpace es privada en los servidores de MakeSpace." >&2
    echo "Aviso IA: FreeAPI está conectada a recursos cloud gratis que pueden ser no libres." >&2
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
    "opencode-dynamic-context-pruning",
    "opencode-mystatus",
    "opencode-handoff",
    "opencode-background-agents"
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
      OPENCODE_DEFAULT_MODEL="$${OPENCODE_DEFAULT_MODEL:-auto}" python3 - <<'PY'
import json
import os

path = "/home/coder/.opencode/opencode.json"
requested = (os.environ.get("OPENCODE_DEFAULT_MODEL") or "auto").strip()

if not os.path.exists(path):
    raise SystemExit(0)

with open(path, "r", encoding="utf-8") as f:
    try:
        data = json.load(f)
    except Exception:
        data = {}

providers = data.get("provider", {}) if isinstance(data.get("provider"), dict) else {}
litellm_models = (providers.get("litellm", {}) or {}).get("models", {}) if isinstance(providers.get("litellm", {}), dict) else {}
freeapi_models = (providers.get("freeapi", {}) or {}).get("models", {}) if isinstance(providers.get("freeapi", {}), dict) else {}

def first_model_key(models_obj):
    if isinstance(models_obj, dict) and models_obj:
        return next(iter(models_obj.keys()))
    return ""

if requested and requested.lower() != "auto":
    selected_model = requested
else:
    if isinstance(freeapi_models, dict) and freeapi_models:
        freeapi_default = "glm-5-ha" if "glm-5-ha" in freeapi_models else first_model_key(freeapi_models)
        selected_model = f"freeapi/{freeapi_default}" if freeapi_default else ""
    elif isinstance(litellm_models, dict) and litellm_models:
        mks_default = "qwen3.5:27b" if "qwen3.5:27b" in litellm_models else first_model_key(litellm_models)
        selected_model = f"litellm/{mks_default}" if mks_default else ""
    else:
        selected_model = ""

if selected_model:
    data["model"] = selected_model

with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
PY
      ln -sf /home/coder/.opencode/opencode.json /home/coder/.opencode/config.json || true
      python3 - <<'PY'
import json, os
import shutil
home = os.path.expanduser("~")
kicad_dir = os.path.join(home, ".local", "share", "mcp-servers", "kicad-mcp")
gimp_dir = os.path.join(home, ".local", "share", "mcp-servers", "gimp-mcp")
ink_launcher = os.path.join(home, ".local", "bin", "inkscape-mcp-launcher")
mcp_servers = {
  "blender": {"type": "local", "enabled": True, "command": ["uvx", "blender-mcp"]},
  "freecad": {"type": "local", "enabled": True, "command": ["uvx", "freecad-mcp"]},
  "kicad": {"type": "local", "enabled": True, "command": ["uv", "run", "--directory", kicad_dir, "main.py"]},
  "gimp": {"type": "local", "enabled": True, "command": ["uv", "run", "--directory", gimp_dir, "gimp_mcp_server.py"]},
  "inkscape": {"type": "local", "enabled": True, "command": [ink_launcher]},
}
for path in (os.path.join(home, ".opencode", "opencode.json"), os.path.join(home, ".config", "opencode", "opencode.json")):
  if not os.path.exists(path):
    continue
  try:
    with open(path, "r", encoding="utf-8") as f:
      cfg = json.load(f)
  except Exception:
    cfg = {}
  mcp_cfg = cfg.setdefault("mcp", {})
  mcp_cfg.update(mcp_servers)
  if shutil.which("coder") is None and "coder" in mcp_cfg:
    mcp_cfg["coder"] = {"enabled": False}
  with open(path, "w", encoding="utf-8") as f:
    json.dump(cfg, f, indent=2)
PY
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
    OPENCODE_PROVIDER_URL     = ""
    OPENCODE_API_KEY          = ""
    OPENCODE_DEFAULT_MODEL    = local.opencode_default_model
    OPENCODE_DEFAULT_BASE_URL = local.opencode_default_base_url
    MKS_KEY_ENDPOINT          = local.mks_key_endpoint
    FREEAPI_BASE_URL          = local.freeapi_base_url
    FREEAPI_KEY_ENDPOINT      = local.freeapi_key_endpoint
    MKS_BASE_URL              = ""
    MKS_API_KEY               = ""
    AUTO_PROVISION_MKS_API_KEY = tostring(local.auto_provision_mks_key)
    AUTO_PROVISION_FREEAPI_API_KEY = tostring(local.auto_provision_freeapi_key)
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
  dynamic "devices" {
    for_each = local.enable_dri ? ["/dev/dri"] : []
    content {
      host_path      = devices.value
      container_path = devices.value
      permissions    = "rwm"
    }
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
