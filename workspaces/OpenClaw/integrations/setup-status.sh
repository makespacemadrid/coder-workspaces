#!/usr/bin/env bash
# openclaw-setup-status: una línea con los pasos manuales pendientes. La usa
# el "metadata" del agente de Coder (estado en la página del workspace) y la
# app "Completar configuración".
pending=()
if [ "${JOPLIN_ENABLED:-false}" = "true" ] && [ ! -f "$HOME/.local/state/openclaw/joplin-setup.ok" ]; then
  pending+=("Joplin")
fi
if [ ${#pending[@]} -eq 0 ]; then
  echo "✅ Completa"
else
  echo "⏳ Pendiente: ${pending[*]} (app 'Completar configuración')"
fi
