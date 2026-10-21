# DeveloperAndroidSelkies

Variante de prueba del workspace Android con KDE servido por Selkies/PixelFlux.
Mantiene `DeveloperAndroid` con KasmVNC disponible para poder comparar ambos.

Incluye Android Studio, Android SDK y emulador, Gradle, JetBrains Toolbox,
Chrome, VS Code, Node.js 24 y los CLI de IA. La imagen hereda las capas del
escritorio Maker Selkies, por lo que también comparte su integración de GPU,
audio y aplicaciones preinstaladas.

## Dispositivos

- `/dev/kvm` se monta para acelerar el emulador Android.
- `/dev/dri` se puede activar o desactivar desde el formulario.
- NVIDIA está activa por defecto y puede deshabilitarse.

El perfil se guarda en `/config`; puede usar un volumen Docker o storage del
host mediante `TF_VAR_users_storage`.
