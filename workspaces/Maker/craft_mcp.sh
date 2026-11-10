#!/usr/bin/env bash
# craft-mcp <app>: servidor MCP (stdio) para las apps Craft instaladas en Maker.
#
# Al arrancar decide el modo:
# - Si la app de escritorio está abierta (su puerto de control escucha), se
#   conecta a ella: el agente trabaja en la ventana que ves.
# - Si no, abre una sesión headless (sin ventana) limitada a ~/Projects.
# La decisión se toma al arrancar el servidor, es decir, al empezar la sesión
# del agente: abre la app antes si quieres ver lo que hace.
#
# Los puertos de control y el token de PhotoCraft vienen de la imagen
# (variables *_CONTROL_PORT y PHOTOCRAFT_CONTROL_TOKEN_FILE), así que la app
# abierta desde el menú ya escucha en ellos. Solo en 127.0.0.1.
set -euo pipefail

app="${1:-}"
root="${CRAFT_MCP_ROOT:-$HOME/Projects}"
mkdir -p "$root"

listening() { (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null; }

# En modo headless, sin las variables de control: algunas CLI las leen como
# "conéctate a la app" (p. ej. PHOTOCRAFT_CONTROL_PORT equivale a --bridge).
headless() {
  exec env -u CADCRAFT_CONTROL_PORT -u PHOTOCRAFT_CONTROL_PORT -u VECTORCRAFT_CONTROL_PORT \
    -u SOLIDCRAFT_CONTROL_PORT "$@"
}

case "$app" in
  cadcraft)
    port="${CADCRAFT_CONTROL_PORT:-27801}"
    if listening "$port"; then exec cadcraft-cli mcp --connect "127.0.0.1:$port"; fi
    # CADCraft no tiene opción para limitar carpetas en headless.
    cd "$root" && headless cadcraft-cli mcp
    ;;
  photocraft)
    port="${PHOTOCRAFT_CONTROL_PORT:-27802}"
    if listening "$port"; then exec photocraft-cli mcp --bridge "127.0.0.1:$port"; fi
    headless photocraft-cli mcp --automation-read-root "$root" --automation-write-root "$root"
    ;;
  vectorcraft)
    port="${VECTORCRAFT_CONTROL_PORT:-27803}"
    if listening "$port"; then exec vectorcraft-cli mcp --connect "127.0.0.1:$port"; fi
    headless vectorcraft-cli mcp --headless --automation-read-root "$root" --automation-write-root "$root"
    ;;
  solidcraft)
    port="${SOLIDCRAFT_CONTROL_PORT:-27804}"
    if listening "$port"; then exec solidcraft-cli mcp --connect "127.0.0.1:$port"; fi
    headless solidcraft-cli mcp --headless --allow-path "$root"
    ;;
  pdfcraft)
    # PdfCraft no tiene modo conectado por puerto: siempre headless.
    headless pdfcraft-cli mcp --compact --automation-read-root "$root" --automation-write-root "$root"
    ;;
  *)
    echo "uso: craft-mcp cadcraft|photocraft|vectorcraft|solidcraft|pdfcraft" >&2
    exit 2
    ;;
esac
