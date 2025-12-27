# MakeSpace Coder

Imágenes Docker y templates de Coder para workspaces de desarrollo y diseño en MakeSpace Madrid.

## Imágenes
- `ghcr.io/makespacemadrid/coder-mks-developer:latest` (Docker-Images/Developer): escritorio XFCE/KasmVNC, Docker, Node.js 20, CLIs de IA (Codex, Claude, Gemini, Continue, Qwen), VS Code, GitHub Desktop, Claude Desktop, AppImage Pool, Geany y audio (PulseAudio/ALSA).
- `ghcr.io/makespacemadrid/coder-mks-developer-android:latest` (Docker-Images/DeveloperAndroid): escritorio KDE/KasmVNC, toolchain Android (SDK/CLI), Node.js 20, VS Code, JetBrains Toolbox y utilidades Android (adb/scrcpy).
- `ghcr.io/makespacemadrid/coder-mks-design:latest` (Docker-Images/Designer): suite de diseño 2D/3D y electrónica (Inkscape, GIMP, Krita, Blender, FreeCAD, OpenSCAD, PrusaSlicer, MeshLab, LibreCAD, KiCad, Fritzing, SimulIDE, LaserGRBL via Wine), ImageMagick, FFmpeg, ExifTool, Pandoc, FontForge, AppImage Pool y Geany.

Build local:
```bash
docker build -t coder-mks-developer Docker-Images/Developer
docker build -t coder-mks-developer-android Docker-Images/DeveloperAndroid
docker build -t coder-mks-design Docker-Images/Designer
```

## Templates de workspaces
- Guía rápida y elección de template: `workspaces/README.md`
- Detalle de cada template: `workspaces/<Template>/README.md`
- Instrucciones para agentes: `AGENTS.md` y `CLAUDE.md`

## Publicación
- Cada push a `main`/`master` lanza el workflow de GitHub Actions (`.github/workflows/build.yml`) que construye y publica las imágenes en GHCR con tags `latest` y `sha`.
- Tras mergear cambios de templates, ejecuta `./push-templates.sh` para actualizar la versión disponible en Coder y sincronizar iconos (afecta a nuevos workspaces).
