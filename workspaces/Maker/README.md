---
display_name: Ocabra Maker
description: Entorno gráfico para diseño 2D/3D y electrónica (autoprovisiona key IA Ocabra si activas OpenCode)
icon: icon.svg
maintainer_github: makespacemadrid
tags: [design, cad, 3d, electronics, ocabra]
---

# Ocabra Maker

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

- `OpenCode Web` se inicia automáticamente y aparece como app privada del propietario en Coder.

## Perfiles compartidos de impresión 3D

Si existe `$TF_VAR_users_storage/_provisioning`, el template monta de solo lectura los perfiles privados de OrcaSlicer y PrusaSlicer y el fondo de escritorio de Designer. Los perfiles y conexiones compartidos se sincronizan en cada arranque; las preferencias personales existentes se conservan. Las credenciales no forman parte del template, de la imagen ni del estado de Terraform.

## Creación rápida en Coder
- [Compute] Aceleración gráfica: `Software` (CPU) o `GPU NVIDIA` (NVENC/CUDA).
- [Storage] Persistencia: `Ninguna` (volumen Docker), `Home completo` o `Solo ~/Projects` en el host.
- [AI] Clave Ocabra: auto-aprovisionar una key nueva (por defecto) o usar la tuya.
- [AI] Provisionar API key FreeAPI automáticamente: activo por defecto.
- [AI] Modelo por defecto de OpenCode.

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
