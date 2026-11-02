---
display_name: MakeSpace Maker Selkies
description: Webtop KDE para impresion 3D acelerado con Selkies y NVIDIA NVENC
icon: icon.svg
maintainer_github: makespacemadrid
tags: [design, cad, 3d, printing, selkies, nvidia]
---

# MakeSpace Maker Selkies

Template experimental para comparar Selkies con el escritorio KasmVNC del template `Maker`. Ejecuta Selkies, KDE y el conjunto completo de aplicaciones Maker dentro del mismo workspace de Coder. La app de acceso aparece como **Remote Desktop**.

## Aplicaciones incluidas

- Laminadores: OrcaSlicer 2.4.2, PrusaSlicer y UltiMaker Cura 5.13.0.
- CAD y reparación: FreeCAD 1.1.4, OpenSCAD, Blender 5.2, MeshLab y LibreCAD.
- Diseño 2D: Inkscape, GIMP, Krita, ImageMagick, FFmpeg, ExifTool, Pandoc y FontForge.
- Electrónica: KiCad, Fritzing, SimulIDE y Freerouting.
- Láser: VisiCut y LaserGRBL mediante Wine.
- Desarrollo: VS Code, Geany, Node.js 24, Codex, Claude Code, OpenCode CLI/Desktop, Claude Desktop y uv.
- MCPs Maker preconfigurados para Codex, Claude Code, Claude Desktop y OpenCode: Blender, FreeCAD, KiCad, OpenSCAD, Inkscape, GIMP y PrusaSlicer.
- Utilidades: AppImage Pool, ADMesh, Assimp, avrdude, dfu-util, usbutils, Mesa/Vulkan tools y Firefox.

El perfil completo vive en `/config`; ahí se guardan el escritorio, los perfiles de los laminadores, `Projects` y `Downloads`.

## Parámetros recomendados para la prueba

- **GPU NVIDIA**: activada.
- **DRI**: activado; el host debe ofrecer `/dev/dri` y NVIDIA Container Toolkit.
- **Backend gráfico**: comienza con Wayland. Cambia a X11 únicamente para comparar compatibilidad.
- **Persistir perfil en el host**: opcional. Sin activarlo se utiliza un volumen Docker persistente.

Selkies se publica como una app privada del propietario a través del proxy autenticado de Coder. La primera prueba usa WebSocket/WebCodecs y no abre puertos del contenedor en el host. WebRTC se deja fuera de esta fase porque requiere un camino UDP directo o TURN.

La preparación de MCPs se ejecuta al arrancar y conserva la configuración existente. Consulta `~/Desktop/MCPS-README.md` para los pasos que requieren activar el servidor dentro de la aplicación gráfica.

Si existe `$TF_VAR_users_storage/_provisioning`, el template monta de solo lectura los perfiles privados de OrcaSlicer y PrusaSlicer y el fondo de escritorio de Designer. Los perfiles y conexiones compartidos se sincronizan en cada arranque; las preferencias personales existentes se conservan. Las credenciales no forman parte del template, de la imagen ni del estado de Terraform.

## Comprobaciones dentro del escritorio

```bash
nvidia-smi
vulkaninfo --summary
glxinfo -B
```

En la barra lateral de Selkies comprueba que el encoder activo sea H.264 por hardware/NVENC y observa FPS, bitrate y latencia. Para comparar de forma justa con `Maker`, usa la misma resolución y el mismo modelo 3D en OrcaSlicer.

## Limitaciones

- No redirige USB desde el navegador. Para una impresora USB debe mapearse explícitamente su dispositivo estable `/dev/serial/by-id/...` o utilizar OctoPrint/Moonraker en red.
- La autenticación propia de Selkies está desactivada porque el acceso queda protegido por la app privada de Coder. No publiques directamente los puertos 3000/3001.

## Publicación

1. Construye y publica `ghcr.io/makespacemadrid/coder-mks-design-selkies:latest`.
2. Ejecuta `coder templates push` para `workspaces/MakerSelkies`.
3. Crea un workspace con GPU y compara Wayland/X11 antes de promoverlo sobre `Maker`.
