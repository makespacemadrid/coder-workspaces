# Watchtower para workspaces Coder

Ejemplo de `docker-compose` para actualizar automáticamente contenedores marcados cada 6 horas.

## Uso rápido
```sh
cd watchtower
docker compose up -d
```

- `watchtower` se levanta con `--label-enable` y `--scope coder-workspaces`.
- Solo actualiza contenedores con los labels:
  - `com.centurylinklabs.watchtower.enable=true`
  - `com.centurylinklabs.watchtower.scope=coder-workspaces`
- El ejemplo `demo-app` muestra cómo etiquetar un servicio.

Puedes ajustar la periodicidad cambiando `WATCHTOWER_SCHEDULE` (cron). Añade más servicios etiquetados para que se actualicen automáticamente.
