#!/usr/bin/env bash
set -euo pipefail

state_dir="${SYNCTHING_HOME:-$HOME/.local/state/syncthing}"
vault_path="${1:?Uso: check-folder-sync RUTA}"

for command in syncthing curl jq readlink; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "Falta el comando requerido: $command" >&2
    exit 1
  fi
done

if [ ! -d "$vault_path" ]; then
  echo "No existe la carpeta sincronizada: $vault_path" >&2
  exit 1
fi

vault_real="$(readlink -f -- "$vault_path")"
folder_id=""
configured_path=""

while IFS= read -r candidate_id; do
  [ -n "$candidate_id" ] || continue
  candidate_path="$(
    syncthing cli --home="$state_dir" \
      config folders "$candidate_id" path get
  )"
  candidate_real="$(readlink -f -- "$candidate_path" 2>/dev/null || true)"
  if [ "$candidate_real" = "$vault_real" ]; then
    folder_id="$candidate_id"
    configured_path="$candidate_path"
    break
  fi
done < <(syncthing cli --home="$state_dir" config folders list)

if [ -z "$folder_id" ]; then
  echo "Syncthing no tiene configurada la carpeta: $vault_real" >&2
  exit 1
fi

api_key="$(syncthing cli --home="$state_dir" config gui apikey get)"
status="$(
  curl -fsS --max-time 5 \
    -H "X-API-Key: $api_key" \
    "http://127.0.0.1:8384/rest/db/status?folder=$folder_id"
)"
unset api_key

printf '%s\n' "$status" | jq \
  --arg folder_id "$folder_id" \
  --arg path "$configured_path" \
  '{
    folderId: $folder_id,
    path: $path,
    state,
    globalFiles,
    localFiles,
    needFiles,
    needDirectories,
    needBytes,
    errors,
    pullErrors,
    synchronized: (
      .state == "idle" and
      .needFiles == 0 and
      .needDirectories == 0 and
      .needBytes == 0 and
      .errors == 0 and
      .pullErrors == 0
    )
  }'

printf '%s\n' "$status" | jq -e '
  .state == "idle" and
  .needFiles == 0 and
  .needDirectories == 0 and
  .needBytes == 0 and
  .errors == 0 and
  .pullErrors == 0
' >/dev/null
