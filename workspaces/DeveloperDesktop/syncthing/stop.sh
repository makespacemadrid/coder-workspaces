#!/usr/bin/env bash
set -euo pipefail

pid_file="/tmp/syncthing-run/syncthing.pid"
if [ ! -f "$pid_file" ]; then
  echo "Syncthing no está ejecutándose."
  exit 0
fi

pid="$(cat "$pid_file")"
if kill -0 "$pid" 2>/dev/null; then
  kill -- "-$pid" 2>/dev/null || kill "$pid" 2>/dev/null || true
fi
rm -f "$pid_file"
echo "Syncthing parado."
