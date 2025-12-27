# Instrucciones para Claude Code

## Contexto del proyecto

Este repositorio contiene imágenes Docker y templates de workspaces de Coder para Makers/Hackers de MakeSpace Madrid.

**Lee primero `AGENTS.md` y `workspaces/README.md`** para entender imágenes, templates y flujo de publicación.

## Principios de trabajo

1. **Lee antes de modificar**: Siempre lee los archivos completos (Dockerfiles, templates, workflows) antes de proponer cambios
2. **Seguridad**: Evita vulnerabilidades en Dockerfiles y templates
3. **Simplicidad**: No sobre-ingenierices. Solo lo necesario
4. **Testing local**: Verifica builds y templates localmente cuando sea posible

## Estructura del proyecto
```
Docker-Images/
  Developer/Dockerfile        # Imagen dev
  Designer/Dockerfile         # Imagen diseño/CAD/EDA
workspaces/                   # Templates de Coder y docs de cada uno
watchtower/                   # Ejemplo de auto-actualización
.github/workflows/            # CI/CD (build y push a GHCR)
AGENTS.md                     # Guía principal (léela)
AGENTS.private.md             # Notas privadas (gitignored)
```

## Flujo de trabajo

1. Cambios se hacen en branches
2. Merge a `main` dispara build automático en GitHub Actions
3. Imágenes se publican en `ghcr.io/makespacemadrid/coder-mks-{developer,design}:latest`
4. Tras cambios en templates, ejecuta `coder templates push` (solo afecta nuevos workspaces)

## Notas importantes

- **No versiones datos sensibles**: URLs internas, IPs, credenciales van en `AGENTS.private.md` (gitignored)
- **Watchtower**: Las imágenes llevan labels para auto-actualización
- **Agent fallback**: Existe bootstrap local para entornos con red restringida
- **AdvancedHostDANGER**: Template DANGER con acceso host, usar con precaución

## Comandos útiles

```bash
# Build local
docker build -f Docker-Images/Developer/Dockerfile -t test-dev .
docker build -f Docker-Images/Designer/Dockerfile -t test-design .

# Push templates
coder templates push Developer
coder templates push Maker
```

Consulta `AGENTS.md` y `workspaces/README.md` para más detalles y UX de creación.
