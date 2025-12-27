---
display_name: MakeSpace Maker
description: Entorno gráfico para diseño 2D/3D y electrónica (autoprovisiona key IA MakeSpace si activas OpenCode)
icon: icon.svg
maintainer_github: makespacemadrid
tags: [design, cad, 3d, electronics, makespace]
---

# MakeSpace Maker

Template con escritorio KDE/KasmVNC y herramientas de diseño 2D/3D + electrónica usando la imagen `ghcr.io/makespacemadrid/coder-mks-design:latest`.

## Apps incluidas (imagen base)
- 2D: Inkscape, GIMP, Krita
- 3D/CAD: Blender, FreeCAD, OpenSCAD, MeshLab, LibreCAD
- Impresión 3D: PrusaSlicer, OrcaSlicer (AppImage)
- Electrónica/EDA: KiCad (footprints/símbolos/templates), Fritzing, SimulIDE
- Láser/CNC: LaserGRBL (via Wine)
- Navegación y utilidades: Firefox (.deb, sin snap), Geany, AppImage Pool (tienda/gestor de AppImage)
- Media/imagen: ImageMagick, FFmpeg, ExifTool
- Docs/tipografía: Pandoc, FontForge
- Módulos Coder: KasmVNC, Filebrowser, OpenCode. RDP aplica solo a workspaces Windows según [las docs de Coder](https://coder.com/docs/user-guides/workspace-access/remote-desktops); esta imagen Linux usa KasmVNC.

## Creación rápida en Coder
- `Habilitar GPUs`: actívalo si lo necesitas.
- `Persistir home en el host`: monta `/home/coder` en `TF_VAR_users_storage/<usuario>/<workspace>`.
- `Persistir solo ~/Projects`: monta `/home/coder/Projects` en `TF_VAR_users_storage/<usuario>/<workspace>/Projects`.
- `Montar ruta host en ~/host`: monta una ruta del host en `/home/coder/host`.
- `Especificar UID para montar la ruta host`: UID para ejecutar el contenedor cuando montas `/home/coder/host` (por defecto 1000).
- `Repositorio Git`: clona en `~/Projects` al primer arranque.
- `OpenCode`: deja activo el checkbox `OpenCode: provisionar API key MakeSpace automáticamente` para generar una key MakeSpace de 30 días y configurar Continue; requiere `TF_VAR_opencode_default_base_url` y `TF_VAR_mks_key_endpoint`.

## Notas
- Home persistente en `/home/coder` (volumen o bind mount según parámetros). Escritorio con accesos directos a las apps clave.
- KasmVNC para escritorio gráfico; incluye code-server y filebrowser por si necesitas editar assets/scripts.
- Labels `com.centurylinklabs.watchtower.*` para que Watchtower pueda actualizar si usas `--label-enable`.
- Si necesitas más programas (Cura, QCAD, LightBurn, simuladores SPICE), avisa y se añaden a la imagen.

## Publicación
Tras actualizar imagen o template:
1) Merge a `main`.
2) GH Actions publica la imagen en GHCR.
3) `coder templates push` para actualizar el template en Coder.
