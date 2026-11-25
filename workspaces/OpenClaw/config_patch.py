#!/usr/bin/env python3
"""Genera el parche de configuración de OpenClaw para el template de Coder.

Sustituye ~40 llamadas a `openclaw config set` (cada una arranca Node y tarda
~2 s) por un único `openclaw config patch --stdin` (una escritura validada).
Los objetos del parche se fusionan con la config existente, las listas y los
escalares la reemplazan y `null` borra la clave: la configuración propia del
usuario que no se menciona aquí se conserva.

Entradas (variables de entorno):
  OPENCLAW_PORT, OPENCLAW_GATEWAY_TOKEN, OPENCLAW_UI_BASE_PATH,
  OPENCLAW_PUBLIC_WS_URL, OPENAI_API_KEY, OPENAI_BASE_URL,
  PROVIDER_JSON   salida de `sync-llm-models --openclaw-provider ocabra`
  TARGET_MODEL    modelo por defecto ya resuelto (provider/modelo) o vacío
  TELEGRAM_BOT_TOKEN, TELEGRAM_ALLOWED_USERS, JOPLIN_ENABLED
  OPENCLAW_CONFIG_PATH  (por defecto ~/.openclaw/openclaw.json)
Salida: el parche JSON por stdout; avisos por stderr.
"""
import json
import os
import sys
from pathlib import Path


def env(name, default=""):
    return (os.environ.get(name) or default).strip()


def load_json(text, fallback):
    try:
        value = json.loads(text) if text else fallback
    except Exception:
        return fallback
    return value if isinstance(value, type(fallback)) else fallback


config_path = Path(env("OPENCLAW_CONFIG_PATH") or Path.home() / ".openclaw" / "openclaw.json")
try:
    current = json.loads(config_path.read_text(encoding="utf-8")) if config_path.exists() else {}
    config_readable = True
except Exception:
    # openclaw.json admite JSON5; si no se puede leer como JSON no se toca
    # nada que dependa del estado actual (p. ej. la compactación del usuario).
    current, config_readable = {}, False


def current_get(*keys):
    node = current
    for key in keys:
        if not isinstance(node, dict) or key not in node:
            return None
        node = node[key]
    return node


key = env("OPENAI_API_KEY")
base_url = env("OPENAI_BASE_URL")
have_ocabra = bool(key and base_url)

patch = {
    # La app de Coder entra por loopback-proxy, que presenta el tráfico como
    # local (pairing automático del navegador); por eso se retiran
    # allowedOrigins y el fallback de Host que ponían versiones antiguas.
    # trustedProxies en loopback: el acceso desde el móvil (app pública /
    # puerto compartido de Coder) llega con X-Forwarded-For y se trata como
    # remoto. basePath: Coder redirige "/" (307) en apps cuya URL lleva
    # ?token=, y el WebSocket de la UI va a <basePath>.
    "gateway": {
        "mode": "local",
        "port": int(env("OPENCLAW_PORT", "3333")),
        "auth": {"mode": "token", "token": env("OPENCLAW_GATEWAY_TOKEN")},
        "trustedProxies": ["127.0.0.1", "::1"],
        "controlUi": {
            "basePath": env("OPENCLAW_UI_BASE_PATH", "/openclaw"),
            "allowedOrigins": None,
            "dangerouslyAllowHostHeaderOriginFallback": None,
        },
    },
    # URL del gateway que llevan los QR de emparejamiento del móvil.
    "plugins": {"entries": {"device-pair": {"config": {"publicUrl": env("OPENCLAW_PUBLIC_WS_URL")}}}},
    "ui": {"prefs": {"locale": "es"}},
    # El paso "recomendaciones de apps" del onboarding busca apps instaladas en
    # el dispositivo: en un contenedor siempre sale vacío.
    "wizard": {"appRecommendations": False},
    "agents": {"defaults": {"userTimezone": "Europe/Madrid"}},
}
defaults = patch["agents"]["defaults"]

# Catálogo vivo de Ocabra (sync-llm-models) y modelos permitidos.
provider = load_json(env("PROVIDER_JSON"), {})
ocabra_models = [m for m in provider.get("models", []) if isinstance(m, dict) and isinstance(m.get("id"), str)]
if ocabra_models:
    patch["models"] = {"providers": {"ocabra": provider}}
    allowed = {f"ocabra/{m['id']}": {} for m in ocabra_models}
    # Los objetos se fusionan: retirar los modelos de Ocabra que ya no existen.
    for old in (current_get("agents", "defaults", "models") or {}):
        if old.startswith("ocabra/") and old not in allowed:
            allowed[old] = None
    defaults["models"] = allowed
else:
    ocabra_models = (current_get("models", "providers", "ocabra") or {}).get("models", []) or []

# Modelo por defecto (sin él la Control UI abre "Model Setup").
target = env("TARGET_MODEL")
known_providers = set((current_get("models", "providers") or {}).keys()) | ({"ocabra"} if ocabra_models else set())
if target:
    if target.split("/", 1)[0] in known_providers:
        defaults["model"] = {"primary": target}
    else:
        print(f"WARN: modelo por defecto '{target}' omitido: su proveedor no está configurado.", file=sys.stderr)

if have_ocabra:
    # La clave de Ocabra se lee del entorno (~/.openclaw/.env), no de un perfil
    # de credenciales: así puede cambiar en cada arranque sin migraciones.
    patch.setdefault("models", {}).setdefault("providers", {}).setdefault("ocabra", {})["apiKey"] = {
        "source": "env", "provider": "default", "id": "OPENAI_API_KEY"}
    # Voz: TTS con Ocabra. "${OPENAI_API_KEY}" va literal: OpenClaw lo resuelve
    # desde ~/.openclaw/.env.
    patch["tts"] = {
        "auto": "off",
        "provider": "openai",
        "providers": {"openai": {
            "baseUrl": base_url, "apiKey": "${OPENAI_API_KEY}",
            "model": "recomendado-tts", "speakerVoice": "alloy", "responseFormat": "mp3",
        }},
    }
    # Talk en tiempo real con el WebSocket /v1/realtime de Ocabra (compatible con
    # la Realtime API de OpenAI). El gateway hace de relay: la clave no sale al
    # navegador. brain agent-consult: el modelo de voz delega en el agente de
    # OpenClaw (herramientas, memoria). La voz se elige en la propia UI.
    realtime_url = base_url.rstrip("/").replace("https://", "wss://", 1).replace("http://", "ws://", 1) + "/realtime"
    patch["talk"] = {"provider": "openai", "speechLocale": "es-ES", "realtime": {
        "provider": "openai", "mode": "realtime", "transport": "gateway-relay",
        "brain": "agent-consult", "model": "recomendado-sota",
        "providers": {"openai": {"baseUrl": realtime_url, "apiKey": {
            "source": "env", "provider": "default", "id": "OPENAI_API_KEY"}}},
    }}
    # Transcripción del audio entrante (notas de voz).
    patch["tools"] = {"media": {
        "audio": {"enabled": True, "language": "es"},
        "models": [{"provider": "openai", "model": "recomendado-stt", "baseUrl": base_url, "capabilities": ["audio"]}],
    }}
    # Memoria con embeddings de Ocabra (no usan el auth-profile del proveedor).
    patch["memory"] = {"search": {
        "enabled": True, "provider": "openai-compatible", "model": "recomendado-embedding",
        "remote": {"baseUrl": base_url, "apiKey": "${OPENAI_API_KEY}"},
    }}
    # Generación/edición de imágenes con el router recomendado-imagen. "openai"
    # es el adaptador de protocolo de imágenes de OpenClaw; baseUrl apunta a
    # Ocabra y la clave es una referencia al entorno (no se copia aquí).
    patch.setdefault("models", {}).setdefault("providers", {})["openai"] = {
        "baseUrl": base_url,
        "apiKey": {"source": "env", "provider": "default", "id": "OPENAI_API_KEY"},
        "auth": "api-key",
        "api": "openai-completions",
    }
    defaults["mediaModels"] = {"image": {"primary": "openai/recomendado-imagen", "fallbacks": [], "timeoutMs": 600000}}

    # Comprensión de imágenes: el modelo principal si acepta imágenes; si no,
    # el primero con visión (prioridad a recomendado-ha-chatbots). Sin fallback.
    vision = [m["id"] for m in ocabra_models if "image" in (m.get("input") or [])]
    primary_id = target.split("/", 1)[1] if target.startswith("ocabra/") else ""
    pick = primary_id if primary_id in vision else (
        "recomendado-ha-chatbots" if "recomendado-ha-chatbots" in vision else (vision[0] if vision else ""))
    if pick:
        defaults["imageModel"] = {"primary": f"ocabra/{pick}", "fallbacks": [], "timeoutMs": 600000}

# Compactación explícita, solo si el usuario no tiene una política propia.
if config_readable and current_get("agents", "defaults", "compaction") is None:
    defaults["compaction"] = {
        "enabled": True, "mode": "safeguard", "thinkingLevel": "low", "timeoutSeconds": 600,
        "keepRecentTokens": 20000, "recentTurnsPreserve": 3, "identifierPolicy": "strict",
        "qualityGuard": {"enabled": True, "maxRetries": 1},
        "midTurnPrecheck": {"enabled": True},
        "postIndexSync": "async", "notifyUser": True,
        "memoryFlush": {"enabled": True, "softThresholdTokens": 4000, "forceFlushTranscriptBytes": "2mb"},
    }

# Telegram. Con IDs: allowlist. Sin IDs: emparejamiento por código. En grupos
# solo responde si lo mencionan. El token vive en ~/.openclaw/.env.
if env("TELEGRAM_BOT_TOKEN"):
    ids = [i.strip() for i in env("TELEGRAM_ALLOWED_USERS").split(",") if i.strip()]
    telegram = {"enabled": True, "botToken": "${TELEGRAM_BOT_TOKEN}", "groupPolicy": "allowlist",
                "groups": {"*": {"requireMention": True}}}
    telegram.update({"dmPolicy": "allowlist", "allowFrom": ids} if ids else {"dmPolicy": "pairing", "allowFrom": None})
    patch["channels"] = {"telegram": telegram}
elif current_get("channels", "telegram") is not None:
    patch["channels"] = {"telegram": {"enabled": False}}

# MCP de Joplin: el wrapper arranca la Data API local y el sync al conectar.
if env("JOPLIN_ENABLED") == "true":
    patch["mcp"] = {"servers": {"joplin": {
        "command": str(Path.home() / ".local/share/joplin-svc/mcp.sh"), "connectionTimeoutMs": 30000}}}
elif current_get("mcp", "servers", "joplin") is not None:
    patch["mcp"] = {"servers": {"joplin": None}}

json.dump(patch, sys.stdout, ensure_ascii=False)
