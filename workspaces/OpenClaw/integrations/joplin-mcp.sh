#!/usr/bin/env bash
set -euo pipefail

# Garantiza que la Data API y el sync estén activos y ejecuta el MCP por stdio.
export PATH="$HOME/.npm-global/bin:$HOME/.local/bin:$PATH"
service_dir="$(cd "$(dirname "$0")" && pwd)"

if [ ! -s "$HOME/.joplin-server-config" ] || ! grep -q '^JOPLIN_PASSWORD=.' "$HOME/.joplin-server-config"; then
  echo "Joplin no está configurado: ejecuta 'openclaw-joplin-setup' en una terminal del workspace." >&2
  exit 1
fi

if ! pgrep -f "$service_dir/run.sh" >/dev/null; then
  nohup setsid "$service_dir/run.sh" >/dev/null 2>&1 < /dev/null &
fi

ready=false
for _ in $(seq 30); do
  if curl -fsS http://127.0.0.1:41184/ping 2>/dev/null \
    | grep -q JoplinClipperServer; then
    ready=true
    break
  fi
  sleep 1
done

if [ "$ready" != true ]; then
  echo "La Data API de Joplin no respondió en 30 segundos" >&2
  exit 1
fi

export JOPLIN_URL="http://127.0.0.1:41184"
JOPLIN_TOKEN="$(joplin config api.token | sed 's/^api.token = //')"
export JOPLIN_TOKEN

if [ -z "$JOPLIN_TOKEN" ]; then
  echo "Joplin no devolvió api.token" >&2
  exit 1
fi

exec uvx joplin-mcp==0.10.0 "$@"
