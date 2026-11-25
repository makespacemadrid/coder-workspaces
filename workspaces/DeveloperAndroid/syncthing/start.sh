#!/usr/bin/env bash
# start-syncthing: arranca Syncthing supervisado (sin systemd). GUI/API solo en
# 127.0.0.1:8384; Coder la publica con la app "Syncthing" a través de
# loopback-proxy. Syncthing se actualiza solo: tras actualizarse sale y el bucle
# lo relanza con el binario nuevo (~/.local/bin, en el HOME persistente).
set -euo pipefail

state_dir="${SYNCTHING_HOME:-$HOME/.local/state/syncthing}"
run_dir="/tmp/syncthing-run"
pid_file="$run_dir/syncthing.pid"
launcher_log="$state_dir/launcher.log"

mkdir -p "$state_dir" "$run_dir"
chmod 700 "$state_dir"

if ! command -v syncthing >/dev/null 2>&1; then
  echo "Syncthing no está instalado" >&2
  exit 1
fi

if [ ! -f "$state_dir/config.xml" ]; then
  syncthing generate --home="$state_dir" --no-port-probing
fi

if [ -f "$pid_file" ] && kill -0 "$(cat "$pid_file")" 2>/dev/null; then
  exit 0
fi

nohup setsid bash -c '
  while :; do
    syncthing serve \
      --home="$1" \
      --no-browser \
      --no-port-probing \
      --no-restart \
      --gui-address=http://127.0.0.1:8384 \
      --log-file=default \
      --log-max-size=10485760 \
      --log-max-old-files=3
    status=$?
    echo "Syncthing salió ($status); reinicio en 5s" >&2
    sleep 5
  done
' syncthing-supervisor "$state_dir" >> "$launcher_log" 2>&1 < /dev/null &

echo $! > "$pid_file"

for _ in $(seq 30); do
  if curl -fsS --max-time 1 http://127.0.0.1:8384/rest/noauth/health \
    >/dev/null 2>&1; then
    exit 0
  fi
  sleep 1
done

echo "Syncthing no respondió en 127.0.0.1:8384; revisa $launcher_log" >&2
exit 1
