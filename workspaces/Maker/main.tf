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
  default     = ""
  description = "(Optional) Docker socket URI (no se usa por defecto)"
  type        = string
}

variable "users_storage" {
  default     = ""
  description = "Ruta base para storage de usuarios (ej. $TF_VAR_users_storage)."
  type        = string
}

variable "ocabra_endpoint_base_url" {
  default     = ""
  description = "Base URL OpenAI-compatible por defecto (si no se define en parámetros)."
  type        = string
}

variable "ocabra_key" {
  default     = ""
  description = "Endpoint para solicitar keys Ocabra (autoprovision)."
  type        = string
}

# Parámetro de aceleración gráfica
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

data "coder_parameter" "ocabra_key_mode" {
  name         = "60_ocabra_key_mode"
  display_name = "[AI MakeSpace] Clave Ocabra"
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
  display_name = "[AI MakeSpace] Clave Ocabra manual"
  description  = "Solo se usa si arriba elegiste 'Usar mi propia clave'."
  type         = "string"
  default      = ""
  order        = 61
  mutable      = true
}

data "coder_parameter" "opencode_default_model" {
  # opencode/glm-5.3-flash-free: modelo gratuito del catálogo de OpenCode Zen
  # (confirmado en models.dev, distinto de glm-5.3-flash que es de pago).
  name         = "63_opencode_default_model"
  display_name = "[AI] Modelo por defecto de OpenCode"
  description  = "'auto' elige el modelo de mayor capacidad descubierto en Ocabra; también admite cualquier provider/model actual."
  type         = "string"
  default      = "opencode/glm-5.3-flash-free"
  order        = 63
  mutable      = true
}

data "coder_parameter" "enable_opencode_free_models" {
  name         = "64_enable_opencode_free_models"
  display_name = "[AI] Modelos gratuitos de OpenCode (Zen)"
  description  = "Desactivalo para que no aparezcan en el selector los modelos gratuitos integrados de OpenCode (glm-5.3-flash-free, etc.)."
  type         = "bool"
  default      = true
  order        = 64
  mutable      = true
}

data "coder_parameter" "ollama_api_key" {
  name         = "70_ollama_api_key"
  display_name = "[AI externa] Ollama Cloud (ollama.com)"
  description  = "Opcional. Si la rellenas, se anade como provider OpenAI-compatible en OpenCode con el catalogo vivo de ollama.com."
  type         = "string"
  default      = ""
  order        = 70
  mutable      = true
}

data "coder_parameter" "nvidia_api_key" {
  name         = "71_nvidia_api_key"
  display_name = "[AI externa] NVIDIA (build.nvidia.com)"
  description  = "Opcional. Si la rellenas, se anade como provider OpenAI-compatible en OpenCode con el catalogo vivo de integrate.api.nvidia.com."
  type         = "string"
  default      = ""
  order        = 71
  mutable      = true
}

locals {
  username                   = data.coder_workspace_owner.me.name
  workspace_image            = "ghcr.io/makespacemadrid/coder-mks-design:latest"
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
  maker_provisioning_path    = local.workspace_storage_root != "" ? "${local.workspace_storage_root}/_provisioning/maker" : ""
  wallpaper_path             = local.workspace_storage_root != "" ? "${local.workspace_storage_root}/_provisioning/desktop/wallpapers" : ""
  home_volume_resolved       = "coder-${data.coder_workspace.me.id}-home"
  default_repo_path          = "/home/coder/Projects"
  ocabra_key_mode            = data.coder_parameter.ocabra_key_mode.value
  ocabra_key_value           = trimspace(data.coder_parameter.ocabra_key_value.value)
  openai_api_key             = local.ocabra_key_mode == "manual" ? local.ocabra_key_value : ""
  auto_provision_ocabra_key  = local.ocabra_key_mode == "auto"
  opencode_default_model     = trimspace(data.coder_parameter.opencode_default_model.value)
  enable_opencode_free_models = data.coder_parameter.enable_opencode_free_models.value
  ollama_api_key             = trimspace(data.coder_parameter.ollama_api_key.value)
  nvidia_api_key             = trimspace(data.coder_parameter.nvidia_api_key.value)
  ocabra_endpoint_base_url   = trimspace(var.ocabra_endpoint_base_url)
  ocabra_key                 = trimspace(var.ocabra_key)
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
    # claude-desktop: /usr/bin/claude-desktop es un symlink al binario Electron en
    # /usr/lib. Escribir el wrapper con 'tee' sobre el symlink machacaria el binario
    # real (RPATH=$ORIGIN), dejando un self-exec en bucle. Por eso: (1) solo actuar si
    # el binario real esta intacto, (2) borrar el symlink antes de escribir, (3) crear
    # un fichero regular que ejecuta el binario real con flags de render por software
    # (KasmVNC no tiene GPU).
    if [ -x /usr/lib/claude-desktop/claude-desktop ] && [ "$(stat -c%s /usr/lib/claude-desktop/claude-desktop 2>/dev/null || echo 0)" -gt 1000000 ]; then
      sudo rm -f /usr/bin/claude-desktop /usr/bin/claude-desktop.real
      sudo tee /usr/bin/claude-desktop >/dev/null <<'CLAUDEWRAP'
#!/bin/sh
exec env ELECTRON_DISABLE_SANDBOX=1 ELECTRON_OZONE_PLATFORM_HINT=auto COWORK_VM_BACKEND=host \
  /usr/lib/claude-desktop/claude-desktop \
  --no-sandbox --disable-gpu-sandbox --use-gl=angle --use-angle=swiftshader \
  --enable-unsafe-swiftshader --ignore-gpu-blocklist --disable-dev-shm-usage --password-store=basic "$@"
CLAUDEWRAP
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

    # MCP setup para herramientas Maker (Blender, FreeCAD, KiCad, Inkscape, GIMP)
    mkdir -p "$HOME/.local/bin" "$HOME/.local/share/mcp-servers" "$HOME/.config/inkscape/extensions" "$HOME/.cache/mcp-slicer"
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
    clone_or_update "https://github.com/mixelpixx/KiCAD-MCP-Server.git" "$HOME/.local/share/mcp-servers/kicad-mcp-server"
    clone_or_update "https://github.com/quellant/openscad-mcp.git" "$HOME/.local/share/mcp-servers/openscad-mcp"
    clone_or_update "https://github.com/maorcc/gimp-mcp.git" "$HOME/.local/share/mcp-servers/gimp-mcp"
    clone_or_update "https://github.com/Shriinivas/inkmcp.git" "$HOME/.config/inkscape/extensions/inkmcp"
    clone_or_update "https://github.com/neka-nat/freecad-mcp.git" "$HOME/.local/share/mcp-servers/freecad-mcp"
    # Retirar el add-on comunitario que instalaban versiones antiguas de la
    # plantilla. El home es persistente, por lo que actualizar la imagen no lo
    # elimina automáticamente y Blender puede seguir cargándolo junto al oficial.
    BLENDER_LEGACY_ADDON_FOUND=false
    for legacy_addon in "$HOME"/.config/blender/*/scripts/addons/blender_mcp.py; do
      if [ -f "$legacy_addon" ]; then
        BLENDER_LEGACY_ADDON_FOUND=true
        break
      fi
    done
    if [ "$BLENDER_LEGACY_ADDON_FOUND" = true ]; then
      blender --background --python-expr "import bpy; module='blender_mcp'; enabled=module in bpy.context.preferences.addons; enabled and bpy.ops.preferences.addon_disable(module=module); enabled and bpy.ops.wm.save_userpref()" >/dev/null 2>&1 || true
      for legacy_addon in "$HOME"/.config/blender/*/scripts/addons/blender_mcp.py; do
        [ ! -f "$legacy_addon" ] || rm -f -- "$legacy_addon"
      done
    fi

    # Instalar y habilitar el add-on oficial de Blender Lab horneado en la imagen.
    # Además del marcador se comprueba el manifiesto: así se repara una instalación
    # eliminada o incompleta sin reinstalarla innecesariamente en cada arranque.
    BLENDER_MCP_REVISION="$(cat /opt/blender-mcp-revision 2>/dev/null || true)"
    BLENDER_MCP_MARKER="$HOME/.config/blender/.mks-blender-mcp-revision"
    BLENDER_MM="$(blender --version 2>/dev/null | awk 'NR == 1 { split($2, version, "."); print version[1] "." version[2] }')"
    BLENDER_MCP_MANIFEST="$HOME/.config/blender/$BLENDER_MM/extensions/user_default/mcp/blender_manifest.toml"
    if [ -n "$BLENDER_MCP_REVISION" ] && \
       { [ "$(cat "$BLENDER_MCP_MARKER" 2>/dev/null || true)" != "$BLENDER_MCP_REVISION" ] || \
         [ ! -f "$BLENDER_MCP_MANIFEST" ]; }; then
      if blender --command extension install-file --repo=user_default --enable /opt/blender-mcp-addon.zip >/dev/null 2>&1; then
        mkdir -p "$(dirname "$BLENDER_MCP_MARKER")"
        printf '%s\n' "$BLENDER_MCP_REVISION" > "$BLENDER_MCP_MARKER"
      else
        echo "WARN: no se pudo instalar el add-on oficial Blender MCP" >&2
      fi
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
      [ -d "$HOME/.local/share/mcp-servers/openscad-mcp" ] && uv sync --directory "$HOME/.local/share/mcp-servers/openscad-mcp" >/dev/null 2>&1 || true
      [ -d "$HOME/.local/share/mcp-servers/gimp-mcp" ] && uv sync --directory "$HOME/.local/share/mcp-servers/gimp-mcp" >/dev/null 2>&1 || true
    fi
    # KiCad MCP (mixelpixx): build Node + deps Python. pcbnew lo aporta KiCad del sistema.
    # Solo se compila si falta dist/index.js (evita rebuild en cada arranque).
    KICAD_MCP_DIR="$HOME/.local/share/mcp-servers/kicad-mcp-server"
    if [ -d "$KICAD_MCP_DIR" ] && [ ! -f "$KICAD_MCP_DIR/dist/index.js" ] && command -v npm >/dev/null 2>&1; then
      ( cd "$KICAD_MCP_DIR" \
        && npm install --no-fund --no-audit >/dev/null 2>&1 \
        && { [ -f requirements.txt ] && python3 -m pip install --user --quiet --break-system-packages -r requirements.txt >/dev/null 2>&1 || true; } \
        && npm run build >/dev/null 2>&1 ) || true
    fi
    # KiCad: sembrar tablas de librerías de usuario. sym-lib-table solo la crea
    # eeschema en su primer arranque gráfico (que en headless no ocurre), así que
    # sin esto todo ERC avisa lib_symbol_issues por componente. Copiadas de las
    # plantillas del sistema. Y enlazar el jar de Freerouting donde lo busca el MCP.
    KICAD_USER_CFG="$HOME/.config/kicad/10.0"
    mkdir -p "$KICAD_USER_CFG"
    for _kt in sym-lib-table fp-lib-table; do
      if [ ! -f "$KICAD_USER_CFG/$_kt" ] && [ -f "/usr/share/kicad/template/$_kt" ]; then
        cp "/usr/share/kicad/template/$_kt" "$KICAD_USER_CFG/$_kt" || true
      fi
    done
    unset _kt
    mkdir -p "$HOME/.kicad-mcp"
    if [ ! -e "$HOME/.kicad-mcp/freerouting.jar" ] && [ -f /opt/freerouting/freerouting.jar ]; then
      ln -sf /opt/freerouting/freerouting.jar "$HOME/.kicad-mcp/freerouting.jar"
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
    codex_config="$HOME/.codex/config.toml"
    codex_config_previous="$HOME/.codex/config.toml.template-prev"
    cp -p "$codex_config" "$codex_config_previous" 2>/dev/null || true
    python3 - "$codex_config" <<'PY' || echo "WARN: fallo la configuracion segura de MCP; se conserva el archivo anterior" >&2
import os
import re
import stat
import sys
import tempfile
import tomllib

path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    original = f.read()

# Reparar solo la firma inequívoca dejada por la migracion antigua de Chrome MCP.
lines = original.splitlines()
out = []
i = 0
repaired = False
while i < len(lines):
    if lines[i].strip() == "[":
        j = i + 1
        while j < len(lines) and lines[j].strip() != "]":
            j += 1
        if j < len(lines):
            fragment = "\n".join(lines[i:j + 1])
            if '"-lc"' in fragment and "chrome-devtools-mcp" in fragment:
                end = j + 1
                if end < len(lines) and lines[end].strip() in ("enabled = true", "enabled = false"):
                    end += 1
                if end < len(lines) and not lines[end].strip():
                    end += 1
                repaired = True
                i = end
                continue
    out.append(lines[i])
    i += 1

content = "\n".join(out).rstrip("\n") if repaired else original.rstrip("\n")
content = (content + "\n") if content else ""
try:
    parsed = tomllib.loads(content)
except tomllib.TOMLDecodeError as exc:
    print(f"WARN: config.toml de Codex contiene un error desconocido; no se modifica: {exc}", file=sys.stderr)
    raise SystemExit(0)

fragments = {
    "blender": '''[mcp_servers.blender]
command = "/usr/local/bin/blender-mcp"''',
    "freecad": '''[mcp_servers.freecad]
command = "uvx"
args = ["freecad-mcp"]''',
    "kicad": '''[mcp_servers.kicad]
command = "node"
args = ["/home/coder/.local/share/mcp-servers/kicad-mcp-server/dist/index.js"]
env = { NODE_ENV = "production", LOG_LEVEL = "info", KICAD_AUTO_LAUNCH = "false", PYTHONPATH = "/usr/lib/python3/dist-packages:/usr/share/kicad/scripting/plugins:/usr/lib/kicad/lib/python3/dist-packages" }''',
    "openscad": '''[mcp_servers.openscad]
command = "uv"
args = ["run", "--directory", "/home/coder/.local/share/mcp-servers/openscad-mcp", "openscad-mcp"]
env = { OPENSCAD_PATH = "/usr/bin/openscad" }''',
    "gimp": '''[mcp_servers.gimp]
command = "uv"
args = ["run", "--directory", "/home/coder/.local/share/mcp-servers/gimp-mcp", "gimp_mcp_server.py"]''',
    "slicer": '''[mcp_servers.slicer]
command = "npx"
args = ["-y", "mcp-3d-printer-server"]
env = { SLICER_TYPE = "prusaslicer", SLICER_PATH = "/usr/bin/prusa-slicer", TEMP_DIR = "/home/coder/.cache/mcp-slicer" }''',
    "inkscape": '''[mcp_servers.inkscape]
command = "/home/coder/.local/bin/inkscape-mcp-launcher"''',
}

# Migrar la sección que administraba la plantilla desde el servidor comunitario
# al servidor oficial horneado en la imagen, conservando el resto del fichero.
if "blender" in parsed.get("mcp_servers", {}):
    content = re.sub(
        r"(?ms)^\[mcp_servers\.blender\]\n.*?(?=^\[|\Z)",
        fragments["blender"] + "\n\n",
        content,
    )
    parsed = tomllib.loads(content)

existing = parsed.get("mcp_servers", {})
missing = [fragment for name, fragment in fragments.items() if name not in existing]
candidate = content.rstrip("\n")
if missing:
    candidate = ((candidate + "\n\n") if candidate else "") + "\n\n".join(missing) + "\n"
elif candidate:
    candidate += "\n"
tomllib.loads(candidate)

if candidate != original:
    mode = stat.S_IMODE(os.stat(path).st_mode)
    fd, tmp = tempfile.mkstemp(prefix=".config.toml.", dir=os.path.dirname(path), text=True)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(candidate)
        os.chmod(tmp, mode)
        os.replace(tmp, path)
        if repaired:
            print("Reparado config.toml de Codex dañado por la migracion antigua")
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)
PY

    if ! python3 -c 'import sys,tomllib; tomllib.load(open(sys.argv[1], "rb"))' "$codex_config" 2>/dev/null; then
      cp -p "$codex_config_previous" "$codex_config" 2>/dev/null || true
      echo "WARN: cambios de MCP revertidos porque config.toml no supero la validacion TOML" >&2
    fi

    python3 - <<'PY'
import json
import os
import shutil

home = os.path.expanduser("~")
mcp_root = os.path.join(home, ".local", "share", "mcp-servers")
kicad_entry = os.path.join(mcp_root, "kicad-mcp-server", "dist", "index.js")
openscad_dir = os.path.join(mcp_root, "openscad-mcp")
gimp_dir = os.path.join(mcp_root, "gimp-mcp")
ink_launcher = os.path.join(home, ".local", "bin", "inkscape-mcp-launcher")

kicad_env = {
    "NODE_ENV": "production",
    "LOG_LEVEL": "info",
    "KICAD_AUTO_LAUNCH": "false",
    "PYTHONPATH": "/usr/lib/python3/dist-packages:/usr/share/kicad/scripting/plugins:/usr/lib/kicad/lib/python3/dist-packages",
}
openscad_env = {"OPENSCAD_PATH": "/usr/bin/openscad"}
slicer_env = {
    "SLICER_TYPE": "prusaslicer",
    "SLICER_PATH": "/usr/bin/prusa-slicer",
    "TEMP_DIR": os.path.join(home, ".cache", "mcp-slicer"),
}

claude_servers = {
    "blender": {"command": "/usr/local/bin/blender-mcp", "args": []},
    "freecad": {"command": "uvx", "args": ["freecad-mcp"]},
    "kicad": {"command": "node", "args": [kicad_entry], "env": kicad_env},
    "openscad": {"command": "uv", "args": ["run", "--directory", openscad_dir, "openscad-mcp"], "env": openscad_env},
    "gimp": {"command": "uv", "args": ["run", "--directory", gimp_dir, "gimp_mcp_server.py"]},
    "slicer": {"command": "npx", "args": ["-y", "mcp-3d-printer-server"], "env": slicer_env},
    "inkscape": {"command": ink_launcher},
}

opencode_servers = {
    "blender": {"type": "local", "enabled": True, "command": ["/usr/local/bin/blender-mcp"]},
    "freecad": {"type": "local", "enabled": True, "command": ["uvx", "freecad-mcp"]},
    "kicad": {"type": "local", "enabled": True, "command": ["node", kicad_entry], "environment": kicad_env},
    "openscad": {"type": "local", "enabled": True, "command": ["uv", "run", "--directory", openscad_dir, "openscad-mcp"], "environment": openscad_env},
    "gimp": {"type": "local", "enabled": True, "command": ["uv", "run", "--directory", gimp_dir, "gimp_mcp_server.py"]},
    "slicer": {"type": "local", "enabled": True, "command": ["npx", "-y", "mcp-3d-printer-server"], "environment": slicer_env},
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
    if [ -f /usr/share/applications/ai.opencode.desktop.desktop ]; then
      ln -sfn /usr/share/applications/ai.opencode.desktop.desktop "$HOME/Desktop/OpenCode.desktop"
    fi
    for f in firefox.desktop blender.desktop freecad.desktop inkscape.desktop org.gimp.GIMP.desktop krita.desktop kicad.desktop openscad.desktop prusa-slicer.desktop librecad.desktop meshlab.desktop visicut.desktop geany.desktop appimagepool.desktop orcaslicer.desktop simulide.desktop OpenCode.desktop; do
      src="/usr/share/applications/$f"
      if [ -f "$src" ] && [ ! -e "$HOME/Desktop/$f" ]; then
        ln -sf "$src" "$HOME/Desktop/$f"
      fi
    done
    chmod +x ~/Desktop/*.desktop 2>/dev/null || true
    # Guia en el escritorio: modelos disponibles y como activar los de login.
    cat > "$HOME/Desktop/MODELOS-IA.md" <<'IAREADME'
# Modelos de IA en este workspace

## Listos sin login

- Ocabra se consulta en cada arranque. Solo aparecen modelos que el
  endpoint confirma como disponibles.
- OpenCode Zen (modelos gratuitos de OpenCode, ej. GLM-5.3-Flash) se puede
  desactivar con el parametro "[AI] Modelos gratuitos de OpenCode (Zen)".
- Si rellenas tu propia API key de Ollama Cloud o NVIDIA (build.nvidia.com)
  en los parametros "[AI externa]", aparecen tambien aqui con su catalogo vivo.

## Proveedores con login

Ejecuta:

    opencode auth login

OpenAI, Google y otros proveedores usan el catálogo actual de OpenCode/models.dev
y sus variantes de razonamiento. La plantilla no duplica esos modelos, así que
las altas y retiradas no requieren volver a publicar el workspace.

Antigravity no se instala automáticamente: el antiguo plugin quedó archivado y
el reemplazo no oficial advierte de posibles bloqueos de cuentas de Google.

Usa `/models` dentro de OpenCode para consultar el catálogo vivo y seleccionar
un modelo. La configuración existente del usuario se fusiona y no se reemplaza.
IAREADME

    # Guía rápida MCP en el escritorio.
    cat > "$HOME/Desktop/MCPS-README.md" <<'MCPREADME'
# MCPs en Maker: guía rápida

Este workspace trae MCPs de:
- Blender
- FreeCAD
- KiCad (mixelpixx, edición de PCB — requiere KiCad 9)
- OpenSCAD
- Inkscape
- GIMP
- Slicer (PrusaSlicer/OrcaSlicer, vía mcp-3d-printer-server)

## Comprobar estado

```bash
codex mcp list
claude mcp list
opencode mcp list
```

## Blender (paso obligatorio)

1. Abre Blender.
2. En `Edit > Preferences > Add-ons` confirma que está activo `MCP`, mantenido por Blender Lab.
3. En las preferencias del add-on activa el servidor local (y, si quieres, su autoarranque).

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

    # Autoprovisionar clave OpenCode Ocabra si está habilitado
    echo "Aviso IA: la API de Ocabra es privada en los servidores de Ocabra." >&2
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

    # Configuración de Continue solo cuando se autoprovisiona la key OpenAI-compatible
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

    # Script para regenerar y aplicar nueva key de Ocabra
    sudo tee /usr/local/bin/gen_ocabra_key >/dev/null <<'GENMKS'
#!/usr/bin/env bash
set -euo pipefail
KEY_ENDPOINT="$${OCABRA_ENDPOINT_BASE_URL%/}/ocabra/auth/keys"
PROVIDER="$${OPENCODE_PROVIDER_URL:-$${OCABRA_ENDPOINT_BASE_URL:-}}"
EMAIL="$${CODER_USER_EMAIL:-}"
          workspace_slug="$(printf '%s' "$${CODER_WORKSPACE_NAME:-workspace}" | tr -cs '[:alnum:]._-' '-')"; email_slug="$(printf '%s' "$${CODER_USER_EMAIL:-unknown}" | tr -cs '[:alnum:]._-' '-')"; alias="coder-$${workspace_slug}-$${email_slug}-$(tr -dc 0-9 </dev/urandom 2>/dev/null | head -c 8 | sed 's/^$/00000000/')"
if [ -z "$EMAIL" ]; then
  echo "Falta CODER_USER_EMAIL para solicitar la key" >&2
  exit 1
fi
if [ -z "$${OCABRA_KEY:-}" ] || [ -z "$${OCABRA_ENDPOINT_BASE_URL:-}" ]; then
  echo "Falta OCABRA_KEY para solicitar la key" >&2
  exit 1
fi
payload=$(printf '{"name":"%s","expires_in_days":30}' "$alias")
resp=$(curl -fsSL -X POST "$KEY_ENDPOINT" -H "Authorization: Bearer $${OCABRA_KEY:-}" -H "Content-Type: application/json" -d "$payload")
key=$(printf '%s' "$resp" | python3 -c 'import sys,json;x=json.load(sys.stdin);d=x if isinstance(x,dict) else {};dd=d.get("data") if isinstance(d.get("data"),dict) else {};print(d.get("key") or d.get("api_key") or d.get("apiKey") or dd.get("key") or dd.get("api_key") or dd.get("apiKey") or "")' 2>/dev/null || true)
if [ -z "$key" ]; then
  echo "No se obtuvo key de Ocabra" >&2
  exit 1
fi
export OPENCODE_API_KEY="$key"
export OPENCODE_PROVIDER_URL="$PROVIDER"
mkdir -p /home/coder/.opencode /home/coder/.config/opencode
printf "%s" "$key" > /home/coder/.opencode/.latest_ocabra_key || true
printf "%s" "$payload" > /home/coder/.opencode/.latest_ocabra_request || true
python3 - <<'PY'
import json,os
path="/home/coder/.config/opencode/opencode.json"
data={}
if os.path.exists(path):
  try:
    with open(path) as f:
      data=json.load(f)
  except Exception:
    data={}
prov_block=data.setdefault("provider",{}).setdefault("ocabra",{})
prov_block.setdefault("npm","@ai-sdk/openai-compatible")
prov_block.setdefault("name","Ocabra")
prov=prov_block.setdefault("options",{})
prov["baseURL"]=os.environ.get("OPENCODE_PROVIDER_URL") or os.environ.get("OCABRA_ENDPOINT_BASE_URL","")
prov["apiKey"]=os.environ.get("OPENCODE_API_KEY","")
os.makedirs(os.path.dirname(path),exist_ok=True)
with open(path,"w") as f:
  json.dump(data,f,indent=2)
PY
if [ -x /home/coder/.local/bin/sync-llm-models ]; then
  /home/coder/.local/bin/sync-llm-models --opencode /home/coder/.config/opencode/opencode.json --continue-config /home/coder/.continue/config.yaml || true
fi
ln -sf /home/coder/.config/opencode/opencode.json /home/coder/.opencode/opencode.json || true
ln -sf /home/coder/.config/opencode/opencode.json /home/coder/.opencode/config.json || true
echo "Nueva key guardada y aplicada"
GENMKS
    sudo chmod +x /usr/local/bin/gen_ocabra_key || true

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

    # Integraciones MCP propias de la plantilla Maker.
    python3 - <<'PY'
import json, os
import shutil
home = os.path.expanduser("~")
kicad_dir = os.path.join(home, ".local", "share", "mcp-servers", "kicad-mcp")
gimp_dir = os.path.join(home, ".local", "share", "mcp-servers", "gimp-mcp")
ink_launcher = os.path.join(home, ".local", "bin", "inkscape-mcp-launcher")
mcp_servers = {
  "blender": {"type": "local", "enabled": True, "command": ["/usr/local/bin/blender-mcp"]},
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

    # Wrapper ya no necesario
EOT

  env = {
    GIT_AUTHOR_NAME                = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
    GIT_AUTHOR_EMAIL               = data.coder_workspace_owner.me.email
    GIT_COMMITTER_NAME             = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
    GIT_COMMITTER_EMAIL            = data.coder_workspace_owner.me.email
    HOME                           = "/home/coder"
    OPENCODE_PROVIDER_URL          = ""
    OPENCODE_API_KEY               = local.openai_api_key
    OPENCODE_DEFAULT_MODEL         = local.opencode_default_model
    OCABRA_ENDPOINT_BASE_URL       = local.ocabra_endpoint_base_url
    OCABRA_KEY                     = local.ocabra_key
    OCABRA_BASE_URL                = ""
    OCABRA_API_KEY                 = local.openai_api_key
    AUTO_PROVISION_OCABRA_API_KEY  = tostring(local.auto_provision_ocabra_key)
    ENABLE_OPENCODE_FREE_MODELS    = tostring(local.enable_opencode_free_models)
    OLLAMA_API_KEY                 = local.ollama_api_key
    NVIDIA_API_KEY                 = local.nvidia_api_key
    CODER_USER_EMAIL               = data.coder_workspace_owner.me.email
    CODER_WORKSPACE_NAME           = data.coder_workspace.me.name
    DEFAULT_REPO_PATH              = local.default_repo_path
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
module "selkies" {
  # Vendorizado en ./modules/selkies (el módulo selkies-project/selkies aún no
  # está mergeado en registry.coder.com, PR coder/registry#1149 abierto). Se
  # vendoriza en vez de referenciar el fork remoto para poder personalizar
  # display_name/icon: el módulo original hardcodea icon="/icon/selkies.svg",
  # que no existe en este servidor Coder (404 confirmado) -> botón roto.
  count    = data.coder_workspace.me.start_count
  source   = "./modules/selkies"
  agent_id = coder_agent.main.id
  # El keyword "kde" intenta ejecutar un binario literal llamado `kde`, que no
  # existe en Debian/Ubuntu (solo hay startplasma-x11/startkde) -> confirmado
  # con el error real: "dbus-run-session: failed to exec 'kde'". Se pasa el
  # comando real, tal como documenta el propio módulo ("or gives a command to run").
  desktop_environment = "startplasma-x11"
  subdomain           = true
  display_name        = "Desktop"
  icon                 = "/icon/desktop.svg"
}

resource "coder_script" "selkies_audio_fix" {
  # El drop-in /etc/pulse/default.pa.d/10-null-sink.pa de la imagen (pensado
  # para que KasmVNC capturase audio del sink "vcable") deja "vcable" como sink
  # por defecto en CUALQUIER pulseaudio que arranque, incluido el que Selkies
  # lanza para sí mismo -> el audio de las apps nunca llega al sink "output"
  # que Selkies realmente captura. Forzamos aquí el sink correcto tras arrancar
  # Selkies, hasta que se retire del todo esa preconfig de la imagen (solo
  # cuando KasmVNC ya no se use en ningún template).
  count              = data.coder_workspace.me.start_count
  agent_id           = coder_agent.main.id
  display_name       = "Fix Selkies default audio sink"
  run_on_start       = true
  start_blocks_login = false
  script             = <<-EOT
    #!/usr/bin/env bash
    set -uo pipefail
    # Con GPU/NVENC real, Selkies tarda más en inicializar que en modo software;
    # 300 intentos de 1s da margen de sobra en ambos casos.
    for i in $(seq 1 300); do
      sock=$(ls -t /tmp/selkies-session-*/pulse/native 2>/dev/null | head -1)
      if [ -n "$sock" ]; then
        export PULSE_SERVER="unix:$sock"
        if pactl list short sinks 2>/dev/null | grep -q '\boutput\b' \
          && pactl set-default-sink output 2>/dev/null; then
          pactl set-sink-mute output 0 2>/dev/null || true
          echo "Selkies: sink por defecto fijado a 'output' (intento $i)"
          exit 0
        fi
      fi
      sleep 1
    done
    echo "No se pudo fijar el sink por defecto de Selkies a 'output' tras 300s" >&2
  EOT
  depends_on         = [module.selkies]
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
  folder   = "/home/coder/Projects"
}

module "opencode" {
  source   = "registry.coder.com/coder-labs/opencode/coder"
  version  = "~> 0.1"
  agent_id = coder_agent.main.id
  workdir  = "/home/coder/"
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

# Aplica el fondo de escritorio compartido si el montaje de solo lectura
# _provisioning/desktop/wallpapers esta disponible; conserva el fondo si el
# usuario lo ha cambiado despues.
resource "coder_script" "setup_wallpaper" {
  agent_id           = coder_agent.main.id
  display_name       = "Fondo de escritorio MakeSpace"
  icon               = "/icon/desktop.svg"
  run_on_start       = true
  start_blocks_login = false
  timeout            = 120
  script             = <<-EOT
    #!/usr/bin/env bash
    set -u

    wallpaper_source="/opt/makespace-provisioning/wallpapers/designer.png"
    if [ ! -r "$wallpaper_source" ]; then
      echo ">> Fondo privado de Designer no disponible; se omite."
      exit 0
    fi

    wallpaper_dir="$HOME/.local/share/wallpapers/MakeSpace"
    wallpaper="$wallpaper_dir/designer.png"
    helper="$HOME/.local/bin/makespace-apply-wallpaper"
    autostart="$HOME/.config/autostart/makespace-wallpaper.desktop"

    install -d -m 0700 "$wallpaper_dir" "$HOME/.local/bin" "$HOME/.config/autostart"
    install -m 0644 "$wallpaper_source" "$wallpaper"

    cat > "$helper" <<'EOF'
#!/usr/bin/env bash
set -u

wallpaper="$HOME/.local/share/wallpapers/MakeSpace/designer.png"
marker_dir="$HOME/.local/state/makespace"
marker="$marker_dir/wallpaper-designer.sha256"

[ -r "$wallpaper" ] || exit 0
expected="$(sha256sum "$wallpaper" | awk '{print $1}')"
[ "$(cat "$marker" 2>/dev/null || true)" != "$expected" ] || exit 0

for _attempt in $(seq 1 30); do
  # plasma-apply-wallpaperimage necesita DBUS_SESSION_BUS_ADDRESS/DISPLAY de
  # la sesion real de Plasma -- el coder_script corre desligado de esa sesion
  # y sin esto falla en silencio ("Not connected to D-Bus server"), aunque el
  # comando exista. Se descubren leyendo el entorno de un proceso de la
  # sesion ya viva.
  session_pid="$(pgrep -u "$(id -u)" -x plasmashell | head -1)"
  if [ -n "$session_pid" ] && [ -r "/proc/$session_pid/environ" ]; then
    unset DBUS_SESSION_BUS_ADDRESS DISPLAY
    while IFS= read -r envline; do
      case "$envline" in
        DBUS_SESSION_BUS_ADDRESS=*|DISPLAY=*) export "$envline" ;;
      esac
    done < <(tr '\0' '\n' < "/proc/$session_pid/environ")
    if [ -n "$${DBUS_SESSION_BUS_ADDRESS:-}" ] && command -v plasma-apply-wallpaperimage >/dev/null 2>&1 && \
       plasma-apply-wallpaperimage "$wallpaper" >/dev/null 2>&1; then
      install -d -m 0700 "$marker_dir"
      printf '%s\n' "$expected" > "$marker"
      exit 0
    fi
  fi
  sleep 2
done

exit 0
EOF
    chmod 0700 "$helper"

    cat > "$autostart" <<EOF
[Desktop Entry]
Type=Application
Name=MakeSpace Wallpaper
Exec=$helper
Terminal=false
OnlyShowIn=KDE;
X-KDE-autostart-after=panel
EOF
    chmod 0600 "$autostart"

    # Si Plasma ya esta levantado, aplica el fondo ahora. El autostart cubre
    # los casos en los que el escritorio se abre despues del script de Coder.
    nohup "$helper" >/dev/null 2>&1 &
    echo ">> Fondo de escritorio MakeSpace preparado."
  EOT
}

resource "coder_script" "setup_maker_provisioning" {
  agent_id           = coder_agent.main.id
  display_name       = "Perfiles de impresion 3D"
  icon               = "/emojis/1f5a8.png"
  script             = file("${path.module}/scripts/setup-maker-provisioning.sh")
  run_on_start       = true
  start_blocks_login = false
  timeout            = 300
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
  # count (no must_run: must_run=false en este provider significa "no
  # forzar que siga corriendo", NO "pararlo" -- confirmado en vivo que un
  # stop con must_run=false deja el contenedor corriendo igual). Con count
  # el contenedor se destruye de verdad al parar y se recrea al arrancar;
  # los volumes ya tienen ignore_changes=all para sobrevivir a eso.
  count      = data.coder_workspace.me.start_count
  depends_on = [null_resource.ensure_host_paths]
  image      = local.workspace_image
  restart    = "unless-stopped"

  name     = "coder-${data.coder_workspace_owner.me.name}-${lower(data.coder_workspace.me.name)}"
  hostname = data.coder_workspace.me.name

  user = local.host_mount_path != "" ? local.host_mount_uid : "coder"

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

  dynamic "volumes" {
    for_each = local.maker_provisioning_path != "" ? [local.maker_provisioning_path] : []
    content {
      container_path = "/opt/makespace-provisioning/maker"
      host_path      = volumes.value
      read_only      = true
    }
  }

  dynamic "volumes" {
    for_each = local.wallpaper_path != "" ? [local.wallpaper_path] : []
    content {
      container_path = "/opt/makespace-provisioning/wallpapers"
      host_path      = volumes.value
      read_only      = true
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
