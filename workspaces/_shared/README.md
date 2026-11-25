# Recursos compartidos de plantillas

`sync_llm_models.py` es la copia canónica del sincronizador de catálogos LLM.
`loopback_proxy.mjs` es la copia canónica del proxy HTTP/WebSocket que usan las
apps web de `OpenClaw` (Control UI y GUI de Syncthing; copia en esa plantilla).
`assistant_persona.md` es el contexto de MakeSpace que `OpenClaw`
añaden a la personalidad de su agente (copia en cada una).
Cada plantilla conserva una copia local porque Coder empaqueta únicamente el
directorio de la plantilla durante `coder templates push`.

Antes de publicar, las copias deben tener el mismo checksum que este archivo.

`syncthing/` contiene los scripts de la opción Syncthing (`start.sh`, `stop.sh`,
`check-folder-sync.sh`) y su proxy de GUI (`gui-proxy.mjs`, copia de
`loopback_proxy.mjs`); cada plantilla con Syncthing lleva una copia en su carpeta
`syncthing/` (OpenClaw en `integrations/`).
