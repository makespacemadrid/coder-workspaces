#!/usr/bin/env bash
# openclaw-joplin-setup: guarda servidor, usuario y contraseña de Joplin Server
# en ~/.joplin-server-config (600; la contraseña nunca va a los parámetros de
# Coder, que ven los administradores), configura la sincronización del perfil
# local y sincroniza.
#
# Uso: openclaw-joplin-setup            (interactivo, en una terminal)
#      openclaw-joplin-setup --stdin    (no interactivo; lo usa la app
#                                        "Completar configuración")
# En modo --stdin la contraseña llega por stdin (vacía = conservar la guardada)
# y JOPLIN_SETUP_URL / JOPLIN_SETUP_EMAIL, si vienen, sustituyen al servidor y
# al usuario guardados. Al sincronizar bien deja
# ~/.local/state/openclaw/joplin-setup.ok.
set -euo pipefail
from_stdin=false
[ "${1:-}" = "--stdin" ] && from_stdin=true
marker="$HOME/.local/state/openclaw/joplin-setup.ok"
export PATH="$HOME/.npm-global/bin:$HOME/.local/bin:$PATH"
cfg="$HOME/.joplin-server-config"

# Leer como texto (nunca ejecutar el fichero: la contraseña puede llevar $, ;…).
saved() { [ -f "$cfg" ] && grep -m1 "^$1=" "$cfg" | cut -d= -f2- || true; }
old_url=$(saved JOPLIN_SERVER_URL); old_email=$(saved JOPLIN_EMAIL); old_password=$(saved JOPLIN_PASSWORD)
url="${JOPLIN_SETUP_URL:-${old_url:-${JOPLIN_SERVER_URL:-}}}"
email="${JOPLIN_SETUP_EMAIL:-${old_email:-${JOPLIN_EMAIL:-}}}"

if $from_stdin; then
  IFS= read -r password || true
else
  read -r -p "URL de Joplin Server [${url}]: " ans; url="${ans:-$url}"
  read -r -p "Usuario (email) [${email}]: " ans; email="${ans:-$email}"
  read -r -s -p "Contraseña de Joplin Server para $email (vacía = conservar la guardada): " password; echo
fi
password="${password:-$old_password}"
url="${url%/}"

[ -n "$url" ] && [ -n "$email" ] || { echo "Faltan el servidor o el usuario de Joplin." >&2; exit 1; }
case "$url" in http://*|https://*) ;; *) echo "El servidor debe empezar por https:// (o http://)." >&2; exit 1 ;; esac
[ -n "$password" ] || { echo "Falta la contraseña de Joplin Server." >&2; exit 1; }
command -v joplin >/dev/null 2>&1 || { echo "Joplin CLI aún no está instalado; espera a que termine el script 'Joplin' del workspace." >&2; exit 1; }

if [ -n "$old_url" ] && { [ "$url" != "$old_url" ] || [ "$email" != "$old_email" ]; }; then
  echo "Aviso: cambias de cuenta/servidor ($old_email @ $old_url → $email @ $url). Las notas locales se subirán a la cuenta nueva en la próxima sincronización."
fi

( umask 077; printf 'JOPLIN_SERVER_URL=%s\nJOPLIN_EMAIL=%s\nJOPLIN_PASSWORD=%s\n' "$url" "$email" "$password" > "$cfg" )
chmod 600 "$cfg"
joplin config sync.target 9 >/dev/null
joplin config sync.9.path "$url" >/dev/null
joplin config sync.9.username "$email" >/dev/null
joplin config sync.9.password "$password" >/dev/null
joplin config locale es_ES >/dev/null
unset password old_password
echo "Sincronizando con $url ..."
rm -f "$marker"
# "joplin sync" sale con 0 aunque falle: el error solo aparece en la salida.
sync_out=$(joplin sync 2>&1) || true
printf '%s\n' "$sync_out"
if printf '%s' "$sync_out" | grep -qiE "(último error|last error|error:)"; then
  echo "La sincronización falló: revisa el servidor, el usuario y la contraseña." >&2
  exit 1
fi
mkdir -p "$(dirname "$marker")"; date -Is > "$marker"
echo "Listo. El MCP de Joplin queda disponible para OpenClaw (reinicia la sesión del agente si ya estaba abierta)."
