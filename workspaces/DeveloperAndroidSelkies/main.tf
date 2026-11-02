terraform {
  required_providers {
    coder  = { source = "coder/coder" }
    docker = { source = "kreuzwerker/docker" }
    null   = { source = "hashicorp/null" }
  }
}

variable "docker_socket" {
  default     = ""
  description = "Socket Docker opcional del provisioner."
  type        = string
}

variable "users_storage" {
  default     = ""
  description = "Ruta base para storage persistente de usuarios."
  type        = string
}

data "coder_parameter" "graphics_acceleration" {
  name         = "01_graphics_acceleration"
  display_name = "[Compute] Aceleración gráfica"
  description  = "Software: todo por CPU, sin GPU. GPU NVIDIA: pasa la GPU completa al contenedor para Selkies, Android Studio y el emulador."
  type         = "string"
  default      = "gpu"
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

data "coder_parameter" "display_backend" {
  name         = "01_display_backend"
  display_name = "[Desktop] Backend grafico"
  description  = "Wayland es la ruta preferida de Selkies; X11 permite comparar compatibilidad."
  type         = "string"
  form_type    = "dropdown"
  default      = "wayland"
  mutable      = true

  option {
    name  = "Wayland (recomendado)"
    value = "wayland"
  }
  option {
    name  = "X11"
    value = "x11"
  }
}

data "coder_parameter" "persist_config_storage" {
  name         = "02_persist_config_storage"
  display_name = "[Storage] Persistir perfil en el host"
  description  = "Monta /config en TF_VAR_users_storage/<usuario>/<workspace>."
  type         = "bool"
  default      = false
  mutable      = true
}

locals {
  username               = data.coder_workspace_owner.me.name
  workspace_image        = "ghcr.io/makespacemadrid/coder-mks-developer-android-selkies:latest"
  enable_gpu             = data.coder_parameter.graphics_acceleration.value == "gpu"
  enable_dri             = local.enable_gpu
  use_wayland            = data.coder_parameter.display_backend.value == "wayland"
  workspace_storage_root = trimspace(var.users_storage)
  config_mount_host_path = data.coder_parameter.persist_config_storage.value && local.workspace_storage_root != "" ? "${local.workspace_storage_root}/${local.username}/${lower(data.coder_workspace.me.name)}" : ""
  config_volume_name     = "coder-${data.coder_workspace.me.id}-android-selkies-config"
  wallpaper_path         = local.workspace_storage_root != "" ? "${local.workspace_storage_root}/_provisioning/desktop/wallpapers" : ""
  agent_init_script      = replace(coder_agent.main.init_script, "/localhost|127\\.0\\.0\\.1/", "host.docker.internal")
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
    mkdir -p "$HOME/.android" "$HOME/Desktop" "$HOME/Downloads" "$HOME/Projects"
    echo "Selkies backend: $${PIXELFLUX_WAYLAND:-false} (true=Wayland)"
    adb version | head -1 || true
    java -version 2>&1 | head -1 || true
    if [ -e /dev/kvm ]; then
      test -r /dev/kvm && test -w /dev/kvm && echo "KVM disponible" || echo "KVM sin permisos"
    fi
    nvidia-smi --query-gpu=name,driver_version --format=csv,noheader 2>/dev/null || true
  EOT

  env = {
    HOME                = "/config"
    ANDROID_HOME        = "/opt/android-sdk"
    ANDROID_SDK_ROOT    = "/opt/android-sdk"
    ANDROID_USER_HOME   = "/config/.android"
    GIT_AUTHOR_NAME     = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
    GIT_AUTHOR_EMAIL    = data.coder_workspace_owner.me.email
    GIT_COMMITTER_NAME  = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
    GIT_COMMITTER_EMAIL = data.coder_workspace_owner.me.email
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
    display_name = "GPU"
    key          = "2_gpu"
    script       = "nvidia-smi --query-gpu=name,utilization.gpu,memory.used,memory.total --format=csv,noheader 2>/dev/null || echo 'No disponible'"
    interval     = 10
    timeout      = 2
  }
  metadata {
    display_name = "Config Disk"
    key          = "3_config_disk"
    script       = "coder stat disk --path /config"
    interval     = 60
    timeout      = 1
  }
}

resource "coder_app" "selkies" {
  agent_id     = coder_agent.main.id
  slug         = "remote-desktop"
  display_name = "Remote Desktop"
  icon         = "/icon/desktop.svg"
  url          = "http://127.0.0.1:3000"
  share        = "owner"
  subdomain    = true
  open_in      = "tab"

  healthcheck {
    url       = "http://127.0.0.1:3000/"
    interval  = 5
    threshold = 12
  }
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

    wallpaper_source="/opt/makespace-provisioning/wallpapers/developer.png"
    if [ ! -r "$wallpaper_source" ]; then
      echo ">> Fondo privado de Developer no disponible; se omite."
      exit 0
    fi

    wallpaper_dir="$HOME/.local/share/wallpapers/MakeSpace"
    wallpaper="$wallpaper_dir/developer.png"
    helper="$HOME/.local/bin/makespace-apply-wallpaper"
    autostart="$HOME/.config/autostart/makespace-wallpaper.desktop"

    install -d -m 0700 "$wallpaper_dir" "$HOME/.local/bin" "$HOME/.config/autostart"
    install -m 0644 "$wallpaper_source" "$wallpaper"

    cat > "$helper" <<'EOF'
#!/usr/bin/env bash
set -u

wallpaper="$HOME/.local/share/wallpapers/MakeSpace/developer.png"
marker_dir="$HOME/.local/state/makespace"
marker="$marker_dir/wallpaper-developer.sha256"

[ -r "$wallpaper" ] || exit 0
expected="$(sha256sum "$wallpaper" | awk '{print $1}')"
[ "$(cat "$marker" 2>/dev/null || true)" != "$expected" ] || exit 0

for _attempt in $(seq 1 30); do
  if command -v plasma-apply-wallpaperimage >/dev/null 2>&1 && \
     plasma-apply-wallpaperimage "$wallpaper" >/dev/null 2>&1; then
    install -d -m 0700 "$marker_dir"
    printf '%s\n' "$expected" > "$marker"
    exit 0
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


resource "docker_volume" "config" {
  count = local.config_mount_host_path == "" ? 1 : 0
  name  = local.config_volume_name
  lifecycle {
    ignore_changes = all
  }
  labels {
    label = "coder.owner"
    value = data.coder_workspace_owner.me.name
  }
  labels {
    label = "coder.workspace_id"
    value = data.coder_workspace.me.id
  }
}

resource "null_resource" "ensure_config_path" {
  count    = local.config_mount_host_path != "" ? 1 : 0
  triggers = { config = local.config_mount_host_path }
  provisioner "local-exec" {
    command = "mkdir -p '${self.triggers.config}'"
  }
}

resource "docker_container" "workspace" {
  depends_on = [null_resource.ensure_config_path]
  image      = local.workspace_image
  name       = "coder-${data.coder_workspace_owner.me.name}-${lower(data.coder_workspace.me.name)}"
  hostname   = data.coder_workspace.me.name

  env = [
    "AUTO_GPU=${local.enable_gpu ? "true" : "false"}",
    "CODER_AGENT_INIT_SCRIPT_B64=${base64encode(local.agent_init_script)}",
    "CODER_AGENT_TOKEN=${coder_agent.main.token}",
    "NVIDIA_DRIVER_CAPABILITIES=compute,utility,graphics,video",
    "NVIDIA_VISIBLE_DEVICES=${local.enable_gpu ? "all" : "void"}",
    "PIXELFLUX_WAYLAND=${local.use_wayland ? "true" : "false"}",
    "PUID=1000",
    "PGID=1000",
    "SELKIES_ENABLE_BASIC_AUTH=false",
    "SELKIES_MODE=websockets",
    "START_DOCKER=false",
    "TITLE=MakeSpace Android (Selkies)",
    "TZ=Europe/Madrid"
  ]

  gpus     = local.enable_gpu ? "all" : null
  shm_size = 4 * 1024 * 1024 * 1024

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
    for_each = local.config_mount_host_path != "" ? [local.config_mount_host_path] : []
    content {
      target = "/config"
      type   = "bind"
      source = mounts.value
    }
  }

  dynamic "volumes" {
    for_each = local.config_mount_host_path == "" ? [local.config_volume_name] : []
    content {
      container_path = "/config"
      volume_name    = volumes.value
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
