---
display_name: Maker
description: Entorno gráfico para diseño 2D/3D y electrónica (autoprovisiona key IA Ocabra si activas OpenCode)
icon: icon.svg
maintainer_github: makespacemadrid
tags: [design, cad, 3d, electronics, ocabra]
---

# Maker

Template con escritorio KDE real vía Selkies (streaming WebRTC) y herramientas de diseño 2D/3D + electrónica usando la imagen `ghcr.io/makespacemadrid/coder-mks-design:latest`.

## Apps incluidas (imagen base)
- 2D: Inkscape, GIMP 3.2.6, Krita 5.3.4
- 3D/CAD: Blender 5.2.2 LTS, FreeCAD 1.1.3, OpenSCAD, MeshLab, LibreCAD
- Impresión 3D: PrusaSlicer, OrcaSlicer (AppImage)
- Electrónica/EDA: KiCad (footprints/símbolos/templates), Fritzing, SimulIDE
- Láser/CNC: LaserGRBL (via Wine)
- Navegación y utilidades: Firefox (.deb, sin snap), Geany, OpenCode Desktop, AppImage Pool (tienda/gestor de AppImage)
- Media/imagen: ImageMagick, FFmpeg, ExifTool
- Docs/tipografía: Pandoc, FontForge
- Módulos Coder: Selkies (escritorio), Filebrowser, OpenCode. RDP aplica solo a workspaces Windows según [las docs de Coder](https://coder.com/docs/user-guides/workspace-access/remote-desktops); esta imagen Linux usa Selkies.
- Blender MCP oficial de Blender Lab, con servidor y add-on fijados a una revisión reproducible e instalados sin depender de la red durante el arranque.
- Apps Craft (Rust, Apache-2.0, versiones fijas y verificadas con el SHA256SUMS oficial): **SolidCraft** (CAD 3D paramétrico, STL/3MF/STEP), **CADCraft** (dibujo 2D, DXF/DWG), **VectorCraft** (vectorial, SVG), **PhotoCraft** (edición de fotos) y **PdfCraft** (PDF). Cada una trae su servidor MCP oficial.

## Agentes y apps Craft (MCP)
Las cinco apps Craft quedan registradas como servidores MCP en Claude (Code y Desktop), OpenCode y Codex (`solidcraft`, `cadcraft`, `vectorcraft`, `photocraft`, `pdfcraft`) mediante `~/.local/bin/craft-mcp`, que decide el modo al arrancar el servidor:
- **App abierta:** se conecta a ella y ves en la ventana lo que hace el agente. Las apps escuchan en `127.0.0.1` (puertos 27801-27804, variables `*_CONTROL_PORT` de la imagen). PhotoCraft exige además un token, que crea en `~/.config/photocraft/control.token` (permisos 600).
- **App cerrada:** sesión headless, sin ventana. Lee y escribe solo en `~/Projects` (CADCraft no permite limitar carpetas).
- La decisión se toma al empezar la sesión del agente: **abre la app antes** si quieres verlo trabajar. Si la abres después, reinicia la sesión del agente o su servidor MCP.
- PdfCraft solo funciona en headless (su canal de control no va por puerto).

- `OpenCode Web` se inicia automáticamente y aparece como app privada del propietario en Coder.

## Perfiles compartidos de impresión 3D

Si existe `$TF_VAR_users_storage/_provisioning`, el template monta de solo lectura los perfiles privados de OrcaSlicer y PrusaSlicer y el fondo de escritorio de Designer. Los perfiles y conexiones compartidos se sincronizan en cada arranque; las preferencias personales existentes se conservan. Las credenciales no forman parte del template, de la imagen ni del estado de Terraform.

## Creación rápida en Coder
- [Compute] Aceleración gráfica: `Software` (CPU) o `GPU NVIDIA` (NVENC/CUDA).
- [Storage] Persistencia: `Ninguna` (volumen Docker), `Home completo` o `Solo ~/Projects` en el host.
- [AI MakeSpace] Clave Ocabra: auto-aprovisionar una key nueva (por defecto) o usar la tuya.
- [AI] Modelo por defecto de OpenCode: `opencode/glm-5.3-flash-free` (gratuito) por defecto; también acepta `auto` o cualquier `provider/model` del catálogo.
- [AI externa] Modelos gratuitos de OpenCode (Zen): activos por defecto; desactívalo si no quieres que aparezcan en el selector.
- [AI externa] Ollama Cloud / NVIDIA (build.nvidia.com): campos opcionales para tu propia API key; si la rellenas, OpenCode añade ese proveedor con su catálogo vivo.

## Notas
- Home persistente en `/home/coder` (volumen o bind mount según parámetros). Escritorio con accesos directos a las apps clave.
- Escritorio KDE real vía Selkies (streaming WebRTC/H.264 con detección NVENC); incluye code-server y filebrowser por si necesitas editar assets/scripts.
- Labels `com.centurylinklabs.watchtower.*` para que Watchtower pueda actualizar si usas `--label-enable`.
- Si necesitas más programas (Cura, QCAD, LightBurn, simuladores SPICE), avisa y se añaden a la imagen.

## Publicación
Tras actualizar imagen o template:
1) Merge a `main`.
2) GH Actions publica la imagen en GHCR.
3) `coder templates push` para actualizar el template en Coder.
