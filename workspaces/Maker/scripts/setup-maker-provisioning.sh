#!/usr/bin/env bash
set -euo pipefail

SLICER_CONFIG_ROOT="/opt/makespace-provisioning/maker"
WALLPAPER_ROOT="/opt/makespace-provisioning/wallpapers"

log() {
  printf '[maker-provisioning] %s\n' "$*"
}

if [ -r "$SLICER_CONFIG_ROOT/install-slicer-config.sh" ]; then
  log "Instalando perfiles compartidos de OrcaSlicer y PrusaSlicer."
  bash "$SLICER_CONFIG_ROOT/install-slicer-config.sh"
else
  log "Configuracion privada de laminadores no disponible; se omite."
fi

wallpaper_source="$WALLPAPER_ROOT/designer.png"
if [ ! -r "$wallpaper_source" ]; then
  log "Fondo privado de Designer no disponible; se omite."
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

# Si Plasma ya esta levantado, aplica el fondo ahora. El autostart cubre los
# casos en los que el escritorio se abre despues del script de Coder.
nohup "$helper" >/dev/null 2>&1 &
log "Aprovisionamiento Maker preparado."
