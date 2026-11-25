#!/usr/bin/env bash
set -u

# Joplin CLI: Data API local y sincronización periódica con Joplin Server.
export PATH="$HOME/.npm-global/bin:$HOME/.local/bin:$PATH"
service_dir="$(cd "$(dirname "$0")" && pwd)"
cd "$service_dir"

if ! curl -fsS http://127.0.0.1:41184/ping 2>/dev/null \
  | grep -q JoplinClipperServer; then
  nohup joplin server start >> server.log 2>&1 &
fi

while true; do
  joplin sync >> sync.log 2>&1
  tail -n 500 sync.log > sync.log.tmp && mv sync.log.tmp sync.log
  sleep 300
done
