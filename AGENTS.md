# Guía rápida para agentes

Lee esto antes de tocar plantillas o imágenes. Para notas privadas, usa `AGENTS.private.md` (no versionado).

## Docs clave
- Visión general del repo: `README.md`
- Resumen de templates y flujos de creación: `workspaces/README.md`
- Detalle de cada template: `workspaces/*/README.md`
- Notas específicas para Claude: `CLAUDE.md`
- Ejemplo de Watchtower: `watchtower/README.md`

## Imágenes base
- `ghcr.io/makespacemadrid/coder-mks-developer:latest` (Docker-Images/Developer/Dockerfile): escritorio XFCE/KasmVNC, Docker Engine, Node.js 20, CLIs de IA (Codex, Claude, Gemini), VS Code, GitHub Desktop, Claude Desktop, AppImage Pool, audio (PulseAudio/ALSA), Geany y tooling dev (Docker, gh, etc.).
- `ghcr.io/makespacemadrid/coder-mks-design:latest` (Docker-Images/Designer/Dockerfile): stack de diseño 2D/3D y electrónica (Inkscape, GIMP, Krita, Blender, FreeCAD, OpenSCAD, PrusaSlicer, OrcaSlicer, MeshLab, LibreCAD, KiCad, Fritzing, SimulIDE, LaserGRBL via Wine) + AppImage Pool y Geany.

## Templates Coder
- `Developer` (DinD): workspace general con Docker-in-Docker y GPUs opcionales; volúmenes persistentes `/home/coder` y `/var/lib/docker`; red bridge. Escritorio XFCE/KasmVNC.
- `AdvancedHostDANGER`: **DANGER** acceso directo a Docker y red del host. Usa `Developer` si no necesitas tocar el host. Escritorio XFCE/KasmVNC.
- `DeveloperAndroid`: escritorio KDE/KasmVNC con toolchain Android (SDK/CLI), Node 20 y VS Code base.
- `Maker`: escritorio KDE/KasmVNC con herramientas de diseño/CAD/EDA; GPUs opcionales; home persistente; módulos Filebrowser/OpenCode. RDP aplica solo a workspaces Windows según [la guía de Coder](https://coder.com/docs/user-guides/workspace-access/remote-desktops).
- `Minimal`: sin escritorio; code-server + Docker-in-Docker ligeros.

## Publicar cambios
1) Merge a `main`.
2) GitHub Actions ( `.github/workflows/build.yml` ) construye y publica imágenes en GHCR con tags `latest` y `sha`.
3) Ejecuta `coder templates push` tras el merge para actualizar los templates en Coder (afecta solo a nuevos workspaces).

## Operativa y mantenimiento
- Todos los contenedores llevan labels `com.centurylinklabs.watchtower.*` para actualizaciones automáticas si lanzas Watchtower con `--label-enable` y `--scope coder-workspaces`.
- Hay un `docker-compose` de ejemplo en `watchtower/docker-compose.yml` (cron de 6h y servicio de muestra).

## Instrucciones sensibles
- No añadas endpoints ni credenciales aquí. Documenta accesos locales o pasos específicos del host en `AGENTS.private.md` (está en `.gitignore`) y mantenlo actualizado.
