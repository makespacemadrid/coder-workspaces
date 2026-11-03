# MakeSpace Coder

Imágenes Docker y templates de Coder para workspaces de desarrollo y diseño en MakeSpace Madrid.

## Imágenes
- `ghcr.io/makespacemadrid/coder-mks-devtools-base:latest` (Docker-Images/DevTools-Base): base headless: Docker Engine, Node.js 24 + CLIs de IA (Codex, Claude, Gemini, Continue, Qwen), uv/pipx, gh y utilidades de consola.
- `ghcr.io/makespacemadrid/coder-mks-developer-cli:latest` (Docker-Images/DeveloperCLI): `DevTools-Base` sin escritorio, usada por el template `Developer`.
- `ghcr.io/makespacemadrid/coder-mks-desktop-kde:latest` (Docker-Images/Desktop-KDE): `DevTools-Base` + KDE Plasma real, Firefox/Chrome, Claude Desktop, OpenCode Desktop.
- `ghcr.io/makespacemadrid/coder-mks-developer-desktop:latest` (Docker-Images/DeveloperDesktop): `Desktop-KDE` + VS Code, GitHub Desktop, Antigravity, AppImage Pool; escritorio vía Selkies. Es la base de `DeveloperRE` y `DeveloperAndroid`.
- `ghcr.io/makespacemadrid/coder-mks-developer-re:latest` (Docker-Images/DeveloperRE): `DeveloperDesktop` + toolchain gratuita de ingeniería inversa (Ghidra, JADX, apktool, GDB+pwndbg, binwalk, unblob, pwntools, mitmproxy, tshark, sigrok, WABT, rizin); escritorio vía KasmVNC.
- `ghcr.io/makespacemadrid/coder-mks-developer-android:latest` (Docker-Images/DeveloperAndroid): `DeveloperDesktop` + toolchain Android (SDK/CLI/Studio/Gradle), JetBrains Toolbox y utilidades Android (adb/scrcpy); escritorio vía Selkies.
- `ghcr.io/makespacemadrid/coder-mks-design:latest` (Docker-Images/Designer): `Desktop-KDE` + suite de diseño 2D/3D y electrónica (Inkscape, GIMP, Krita, Blender, FreeCAD, OpenSCAD, PrusaSlicer, MeshLab, LibreCAD, KiCad, Fritzing, SimulIDE, LaserGRBL via Wine), ImageMagick, FFmpeg, ExifTool, Pandoc, FontForge, AppImage Pool y Geany; escritorio vía Selkies.
- `ghcr.io/makespacemadrid/coder-mks-developer:latest` (Docker-Images/Developer): escritorio XFCE/KasmVNC heredado, todavía en uso por `OpenClaw`/`Hermes` mientras se completa su migración.

Build local:
```bash
docker build -t coder-mks-devtools-base Docker-Images/DevTools-Base
docker build -t coder-mks-developer-cli Docker-Images/DeveloperCLI
docker build -t coder-mks-desktop-kde Docker-Images/Desktop-KDE
docker build -t coder-mks-developer-desktop Docker-Images/DeveloperDesktop
docker build -t coder-mks-developer-re Docker-Images/DeveloperRE
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
