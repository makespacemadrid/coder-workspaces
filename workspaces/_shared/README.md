# Recursos compartidos de plantillas

`sync_llm_models.py` es la copia canónica del sincronizador de catálogos LLM.
Cada plantilla conserva una copia local porque Coder empaqueta únicamente el
directorio de la plantilla durante `coder templates push`.

Antes de publicar, las copias deben tener el mismo checksum que este archivo.
