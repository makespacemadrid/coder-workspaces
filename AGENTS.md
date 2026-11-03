# Guía rápida para agentes

Lee esto antes de tocar plantillas o imágenes. Para notas privadas, usa `AGENTS.private.md` (no versionado).

## Docs clave
- Visión general del repo: `README.md`
- Resumen de templates y flujos de creación: `workspaces/README.md`
- Detalle de cada template: `workspaces/*/README.md`
- Notas específicas para Claude: `CLAUDE.md`
- Ejemplo de Watchtower: `watchtower/README.md`

## Imágenes base
- `ghcr.io/makespacemadrid/coder-mks-devtools-base:latest` (Docker-Images/DevTools-Base/Dockerfile): base headless de tooling: Docker Engine, Node.js 24 + 5 CLIs de IA (Codex, Claude, Gemini, Continue, Qwen), uv/pipx, gh y utilidades de consola. La usan `DeveloperCLI` y `Desktop-KDE`.
- `ghcr.io/makespacemadrid/coder-mks-developer-cli:latest` (Docker-Images/DeveloperCLI/Dockerfile): `DevTools-Base` sin nada propio; code-server/JupyterLab se instalan vía módulo de Coder en runtime. La usa el template `Developer`.
- `ghcr.io/makespacemadrid/coder-mks-desktop-kde:latest` (Docker-Images/Desktop-KDE/Dockerfile): `DevTools-Base` + KDE Plasma real, Firefox/Chrome, Claude Desktop, OpenCode Desktop. Base de escritorio compartida por `DeveloperDesktop`, `Designer` y `DeveloperAndroid`.
- `ghcr.io/makespacemadrid/coder-mks-developer-desktop:latest` (Docker-Images/DeveloperDesktop/Dockerfile): `Desktop-KDE` + VS Code, GitHub Desktop, Antigravity, AppImage Pool. La usa el template `DeveloperDesktop` (Selkies) y es la base de `DeveloperRE` y `DeveloperAndroid`.
- `ghcr.io/makespacemadrid/coder-mks-developer:latest` (Docker-Images/Developer/Dockerfile): escritorio XFCE/KasmVNC (imagen heredada, en migración pendiente); la usan todavía `OpenClaw` y `Hermes`.
- `ghcr.io/makespacemadrid/coder-mks-developer-re:latest` (Docker-Images/DeveloperRE/Dockerfile): `DeveloperDesktop` + toolchain gratuita de ingeniería inversa (Ghidra, JADX, apktool, GDB+pwndbg, binwalk, unblob, pwntools, mitmproxy, tshark, sigrok, WABT, rizin) para usar con rea.
- `ghcr.io/makespacemadrid/coder-mks-design:latest` (Docker-Images/Designer/Dockerfile): `Desktop-KDE` + stack de diseño 2D/3D y electrónica (Inkscape, GIMP, Krita, Blender, FreeCAD, OpenSCAD, PrusaSlicer, OrcaSlicer, MeshLab, LibreCAD, KiCad, Fritzing, SimulIDE, LaserGRBL via Wine) + AppImage Pool y Geany. La usa `Maker`, con Selkies como backend de escritorio.
- `ghcr.io/makespacemadrid/coder-mks-developer-android:latest` (Docker-Images/DeveloperAndroid/Dockerfile): `DeveloperDesktop` + Android SDK/Studio/Gradle/JetBrains Toolbox. Backend de escritorio Selkies.

## Templates Coder
- `Developer` (DinD): workspace general **headless** con Docker-in-Docker, CLIs de IA y JupyterLab; GPU opcional solo para cómputo (CUDA/NVENC, no hay escritorio que acelerar). Sustituye a `Minimal`.
- `DeveloperDesktop` (DinD): igual que `Developer` pero con escritorio KDE real vía Selkies; VS Code, GitHub Desktop, Claude Desktop, OpenCode Desktop, Antigravity.
- `DeveloperRE`: imagen `coder-mks-developer-re` (sobre `DeveloperDesktop`, escritorio KDE real vía KasmVNC) con toolchain de ingeniería inversa para usar con rea (morluto/rea).
- `DeveloperAndroid`: imagen sobre `DeveloperDesktop`, escritorio KDE real vía Selkies con toolchain Android (SDK/CLI), Node 24 y VS Code base.
- `Maker`: escritorio KDE real vía Selkies con herramientas de diseño/CAD/EDA; GPUs opcionales; home persistente; módulo OpenCode. RDP aplica solo a workspaces Windows según [la guía de Coder](https://coder.com/docs/user-guides/workspace-access/remote-desktops).
- `Minimal`: **en retirada**, sustituido por `Developer` headless; queda solo por un workspace pendiente de migrar (no crear workspaces nuevos aquí).
- `OpenClaw`: template headless (sin escritorio) para agentes/OpenClaw: gateway OpenClaw + DinD, arranque configurable (`[OpenClaw] Auto-iniciar servicio`, puerto, directorio y comando).
- `Hermes`: template headless (sin escritorio) para el agente [Hermes](https://hermes-agent.nousresearch.com/) de Nous Research; dashboard web propio, directorio de trabajo y modelo por defecto configurables.

`AdvancedHostDANGER`, el spike `developer-selkies-spike`, y las variantes experimentales `MakerSelkies`/`DeveloperAndroidSelkies` (incluida la base `linuxserver/webtop:ubuntu-kde`) se han retirado: Maker y DeveloperAndroid ya corren Selkies de forma nativa sobre `Desktop-KDE`, igual que `DeveloperDesktop`.

## OpenClaw: regla de origen (importante)
- No configures `gateway.controlUi.allowedOrigins` con `*` en OpenClaw: termina en errores de conexión (`origin not allowed` / `disconnected (1006)`).
- Usa siempre orígenes explícitos de Coder, por ejemplo:
  `https://openclaw-ui--<workspace>--<owner>.<host-coder>` y `https://<host-coder>`.

## Publicar cambios
1) Merge a `main`.
2) GitHub Actions ( `.github/workflows/build.yml` ) construye y publica imágenes en GHCR con tags `latest` y `sha`.
3) Ejecuta `coder templates push` tras el merge para actualizar los templates en Coder (afecta solo a nuevos workspaces).

## Operativa y mantenimiento
- Todos los contenedores llevan labels `com.centurylinklabs.watchtower.*` para actualizaciones automáticas si lanzas Watchtower con `--label-enable` y `--scope coder-workspaces`.
- Hay un `docker-compose` de ejemplo en `watchtower/docker-compose.yml` (cron de 6h y servicio de muestra).

## Instrucciones sensibles
- No añadas endpoints ni credenciales aquí. Documenta accesos locales o pasos específicos del host en `AGENTS.private.md` (está en `.gitignore`) y mantenlo actualizado.
