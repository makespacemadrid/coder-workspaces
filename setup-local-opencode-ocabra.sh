#!/usr/bin/env bash
# Preconfigura el OpenCode local contra Ocabra, reutilizando el mismo
# sincronizador de catálogo que usan los templates de Coder.
#
# Uso:
#   ./setup-local-opencode-ocabra.sh
#   ./setup-local-opencode-ocabra.sh --env /ruta/ocabra.env --config /ruta/opencode.json
#
# La clave se lee de ocabra.env (no se pasa nunca por argumentos ni se
# escribe en el historial de shell).
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${OCABRA_ENV_FILE:-$ROOT_DIR/ocabra.env}"
CONFIG_FILE="${OPENCODE_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/opencode/opencode.json}"
SYNC_SCRIPT="$ROOT_DIR/workspaces/_shared/sync_llm_models.py"

usage() {
  cat <<EOF
Uso: $(basename "$0") [opciones]

  --env FILE      Fichero con OCABRA_API_KEY y OCABRA_BASE_URL (por defecto: $ROOT_DIR/ocabra.env)
  --config FILE   Config de OpenCode a modificar (por defecto: $CONFIG_FILE)
  -h, --help      Muestra esta ayuda
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env)
      ENV_FILE="${2:?falta la ruta para --env}"
      shift 2
      ;;
    --config)
      CONFIG_FILE="${2:?falta la ruta para --config}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Opción no reconocida: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ ! -f "$ENV_FILE" ]]; then
  cat >&2 <<EOF
No existe $ENV_FILE.

Créalo con este contenido y rellena la clave:

  OCABRA_API_KEY=sk-ocabra-...
  OCABRA_BASE_URL=https://<host-de-ocabra>

EOF
  exit 1
fi

if [[ ! -f "$SYNC_SCRIPT" ]]; then
  echo "No se encuentra el sincronizador: $SYNC_SCRIPT" >&2
  exit 1
fi

# Cargar el fichero de entorno sin heredar variables de una sesión anterior.
unset OCABRA_API_KEY OCABRA_BASE_URL
set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

OCABRA_API_KEY="${OCABRA_API_KEY:-}"
OCABRA_BASE_URL="${OCABRA_BASE_URL:-}"

# Sin valor por defecto: la URL del despliegue no se versiona (ver CLAUDE.md).
if [[ -z "$OCABRA_BASE_URL" ]]; then
  echo "Rellena OCABRA_BASE_URL en $ENV_FILE antes de ejecutar este script." >&2
  exit 1
fi

if [[ -z "$OCABRA_API_KEY" || "$OCABRA_API_KEY" == "sk-ocabra-..." ]]; then
  echo "Rellena OCABRA_API_KEY en $ENV_FILE antes de ejecutar este script." >&2
  exit 1
fi

# El proveedor OpenAI-compatible de OpenCode necesita la base terminada en /v1.
OCABRA_BASE_URL="${OCABRA_BASE_URL%/}"
while [[ "$OCABRA_BASE_URL" == */ ]]; do
  OCABRA_BASE_URL="${OCABRA_BASE_URL%/}"
done
if [[ "$OCABRA_BASE_URL" != */v1 ]]; then
  OCABRA_BASE_URL="$OCABRA_BASE_URL/v1"
fi

export OCABRA_API_KEY
export OCABRA_BASE_URL

python3 - "$OCABRA_BASE_URL" "$OCABRA_API_KEY" <<'PY'
import json
import sys
import urllib.error
import urllib.request

base_url, api_key = sys.argv[1], sys.argv[2]
request = urllib.request.Request(
    f"{base_url}/models",
    headers={"Accept": "application/json", "Authorization": f"Bearer {api_key}"},
)
try:
    with urllib.request.urlopen(request, timeout=15) as response:
        payload = json.loads(response.read().decode("utf-8", "replace"))
except urllib.error.HTTPError as exc:
    print(f"Ocabra rechazó la petición ({exc.code}); revisa la clave de {base_url}.", file=sys.stderr)
    raise SystemExit(1)
except Exception as exc:
    print(f"No se pudo conectar con {base_url}: {exc}", file=sys.stderr)
    raise SystemExit(1)

rows = payload.get("data", payload) if isinstance(payload, dict) else payload
if not isinstance(rows, list):
    print(f"Respuesta inesperada de {base_url}/models.", file=sys.stderr)
    raise SystemExit(1)
print(f"Ocabra accesible: {len(rows)} modelos en el catálogo.")
PY

CONFIG_DIR="$(dirname -- "$CONFIG_FILE")"
mkdir -p "$CONFIG_DIR"

if [[ -f "$CONFIG_FILE" ]]; then
  backup="$CONFIG_FILE.bak"
  cp -p -- "$CONFIG_FILE" "$backup"
  echo "Copia de seguridad: $backup"
fi

python3 "$SYNC_SCRIPT" --opencode "$CONFIG_FILE"

python3 - "$CONFIG_FILE" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path, encoding="utf-8") as handle:
    data = json.load(handle)

provider = data.get("providers", {}).get("ocabra", {})
if not isinstance(provider, dict):
    provider = {}
models = provider.get("models", {})
if not isinstance(models, dict):
    models = {}
settings = provider.get("settings", {})
if not isinstance(settings, dict):
    settings = {}

print()
print(f"Config:              {path}")
print(f"Proveedor Ocabra:    {settings.get('baseURL', '(sin baseURL)')}")
print(f"Modelos disponibles: {len(models)}")
print(f"Modelo por defecto:  {data.get('model', '(sin definir)')}")
PY
