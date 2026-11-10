# Recursos compartidos de plantillas

`sync_llm_models.py` es la copia canónica del sincronizador de catálogos LLM.
`loopback_proxy.mjs` es la copia canónica del proxy HTTP/WebSocket que usan las
apps web de `OpenClaw` y `Hermes` (copia en cada una de esas plantillas).
`assistant_persona.md` es el contexto de MakeSpace que `OpenClaw` y `Hermes`
añaden a la personalidad de su agente (copia en cada una).
Cada plantilla conserva una copia local porque Coder empaqueta únicamente el
directorio de la plantilla durante `coder templates push`.

Antes de publicar, las copias deben tener el mismo checksum que este archivo.
