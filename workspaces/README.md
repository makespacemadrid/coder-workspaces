# Workspaces Coder

Guía rápida para elegir template y rellenar los parámetros al crear un workspace en Coder.

## Qué template usar
- `Developer` (DinD): desarrollo general headless (sin escritorio), Docker in Docker, CLIs de IA, JupyterLab, puertos opcionales y GPU solo para cómputo (CUDA/NVENC).
- `DeveloperDesktop`: igual que `Developer` pero con escritorio KDE real vía **Selkies** (streaming WebRTC), VS Code, GitHub Desktop, Claude Desktop, Antigravity. Úsalo si necesitas GUI.
- `DeveloperRE`: como `DeveloperDesktop` (KDE real vía Selkies) más toolchain gratuita de ingeniería inversa (Ghidra, JADX, apktool, GDB+pwndbg, binwalk, unblob, pwntools, mitmproxy, tshark, sigrok, WABT, rizin) para usar con [rea](https://github.com/morluto/rea).
- `DeveloperAndroid`: escritorio KDE real vía Selkies con toolchain Android (SDK/CLI), Node 24, VS Code base y JetBrains Toolbox (+ IntelliJ remoto vía Gateway).
- `Maker`: entorno gráfico KDE real vía Selkies con suite de diseño 2D/3D, CAD y EDA. GPU opcional.
- `OpenClaw`: template inicial para agentes/OpenClaw, sin escritorio (OpenClaw es headless por diseño); DinD y arranque configurable.
- `Hermes`: template headless para el agente [Hermes](https://hermes-agent.nousresearch.com/) de Nous Research.

Los templates con Docker in Docker (`Developer`, `DeveloperDesktop`, `DeveloperRE`, `DeveloperAndroid` y `OpenClaw`) incluyen una limpieza automática semanal, configurable desde `[Maintenance] Limpieza automática de Docker`. Conserva volúmenes y contenedores: solo elimina caché de build sin uso durante 7 días e imágenes sin contenedores asociadas de más de 30 días.

Los dos templates Maker pueden cargar perfiles privados compartidos de OrcaSlicer y PrusaSlicer desde `$TF_VAR_users_storage/_provisioning`. El origen se monta de solo lectura y su contenido no se incluye en Git, las imágenes ni el estado de Terraform.

Todos los templates con escritorio (`DeveloperDesktop`, `DeveloperRE`, `DeveloperAndroid`, `Maker`) aplican un fondo de pantalla compartido en el primer arranque si existe `$TF_VAR_users_storage/_provisioning/desktop/wallpapers`, sin sobrescribir un fondo que ya hayas cambiado. `Developer`, `OpenClaw` y `Hermes` quedan fuera por no tener escritorio.

## Creación rápida en Coder
1) Elige template y revisa su README (`workspaces/<Template>/README.md`) para ver qué incluye.
2) Rellena los parámetros clave:
   - **GPU**: actívalo si lo necesitas.
   - **Puertos** (`Developer`): decide si expones puertos al host y el rango.
   - **Persistir home en el host**: monta `/home/coder` en `TF_VAR_users_storage/<usuario>/<workspace>`.
   - **Persistir solo ~/Projects**: monta `/home/coder/Projects` en `TF_VAR_users_storage/<usuario>/<workspace>/Projects`.
   - **Montar ruta host en ~/host**: monta una ruta del host en `/home/coder/host`.
   - **Especificar UID para montar la ruta host**: UID para ejecutar el contenedor cuando montas `/home/coder/host` (por defecto 1000).
   - **OpenCode**: en plantillas con autoprovisión, deja activa la casilla de MakeSpace; requiere `TF_VAR_opencode_default_base_url` y `TF_VAR_mks_key_endpoint`.
   - **Clonado inicial**: añade `Repositorio Git` para clonar en `~/Projects` al primer arranque (pre-rellenado con `TF_VAR_default_repo_url`).
3) Crea el workspace. En las plantillas con escritorio (RDP solo aplica a plantillas Windows).

## Documentación de cada template
- `workspaces/Developer/README.md`
- `workspaces/DeveloperDesktop/README.md`
- `workspaces/DeveloperRE/README.md`
- `workspaces/DeveloperAndroid/README.md`
- `workspaces/Maker/README.md`
- `workspaces/OpenClaw/README.md`
- `workspaces/Hermes/README.md`

Para publicar cambios tras editarlos, consulta `README.md` y `AGENTS.md`.
