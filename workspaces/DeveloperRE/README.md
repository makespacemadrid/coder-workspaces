---
display_name: DeveloperRE
description: "Workspace Developer (Docker in Docker) extendido con toolchain gratuita de ingeniería inversa para usar con rea (morluto/rea)"
icon: icon.svg
maintainer_github: makespacemadrid
tags: [docker, dind, gpu, workspace, ocabra, reverse-engineering]
---

# DeveloperRE (Developer + ingeniería inversa)

Es el template `Developer` (Docker in Docker, escritorio XFCE/KasmVNC) con una capa adicional de herramientas de ingeniería inversa, pensado para trabajar con [rea](https://github.com/morluto/rea) ("Reverse Engineer Anything"). Usa la imagen `ghcr.io/makespacemadrid/coder-mks-developer-re:latest`.

## Para qué sirve
- Analizar binarios nativos, APKs, apps JS/Electron, firmware, capturas de red o señales lógicas con `rea` como MCP/CLI.
- Todo lo que ofrece `Developer` (DinD, GPU opcional, escritorio KasmVNC, CLIs de IA) más el stack de ingeniería inversa.

## Arrancar con rea
El workspace registra rea automáticamente en cada arranque con **todos los agentes de IA que detecte** en la imagen (`npx rea-agents setup --all-detected --yes`, script "Configurar rea para los agentes de IA detectados" — log en `~/.rea-setup.log`): OpenCode, Claude Code (si diste token), Codex, Gemini CLI. No se preinstala como paquete, así siempre se usa la versión más reciente. Detecta automáticamente las herramientas de abajo porque ya están en el `PATH`.

## Qué incluye (gratuito / open-source)
- **Binarios nativos**: Ghidra (descompilador NSA), rizin (build estático oficial), GNU objdump, GDB con [pwndbg](https://pwndbg.re/) integrado (`pwndbg` en vez de `gdb` para análisis de crashes).
- **Android**: JADX (descompilador), apktool (recursos), adb, OpenJDK 21.
- **Firmware**: binwalk (v3, compilado con cargo — el paquete `binwalk` de PyPI está roto desde hace años), unblob (extracción; vía `pipx`).
- **Exploiting / crashes**: pwntools (vía `pipx`).
- **Red**: tshark + capinfos (el usuario `coder` está en el grupo `wireshark` para capturar sin root), mitmproxy/mitmdump (vía `pipx`).
- **Señales lógicas**: sigrok-cli.
- **WebAssembly**: WABT (wasm2wat, wat2wasm, etc.).
- **Web/Electron**: Chrome (ya incluido en `Developer`) para el análisis con navegador headless de rea.
- Todo lo demás de `Developer`: Docker Engine interno (DinD), escritorio XFCE/KasmVNC, Node.js, CLIs de IA, VS Code, etc. — ver `workspaces/Developer/README.md`.

## Qué NO incluye (licencia comercial o sin confirmar)
rea también sabe hablar con estas herramientas, pero no se instalan por requerir una licencia que no podemos redistribuir. Si tienes una, instálalas tú mismo dentro del workspace:
- **IDA Pro / Hex-Rays** — comercial.
- **Hopper** — comercial; su demo es de tiempo/función limitada, no es una alternativa gratuita real.
- **JEB** — comercial (rea espera `REA_JEB_MCP_URL` apuntando a tu propio cliente JEB si lo usas).
- **Kuna** — licencia no confirmada como libre, se deja fuera por precaución.

## Creación rápida en Coder
Los parámetros son idénticos a `Developer` (GPU, puertos, persistencia de home/Projects, autoprovisión de Ocabra, repo Git inicial, etc.) — consulta `workspaces/Developer/README.md` para el detalle de cada uno.

## Cómo publicar cambios
- Edita este template y la imagen base en `Docker-Images/DeveloperRE/Dockerfile`.
- Tras el merge a `main`, espera a que GitHub Actions publique `ghcr.io/makespacemadrid/coder-mks-developer-re:latest` antes de crear un workspace real con este template.
- Ejecuta `coder templates push DeveloperRE` para desplegar el template en Coder.
