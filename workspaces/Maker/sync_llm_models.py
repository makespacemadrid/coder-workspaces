#!/usr/bin/env python3
"""Synchronize live OpenAI-compatible model catalogs without replacing user config."""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import urllib.request
from pathlib import Path
from typing import Any


RETIRED_TEMPLATE_MODELS = {
    "gemini-2.5-flash",
    "gemini-2.5-pro",
    "gemini-3-flash-preview",
    "gemini-3-pro-preview",
    "antigravity-claude-opus-4-5-thinking",
    "antigravity-claude-sonnet-4-5-thinking",
    "antigravity-gemini-3-flash",
    "antigravity-gemini-3-pro",
}
RETIRED_TEMPLATE_PLUGINS = {
    "opencode-antigravity-auth",
}
BASELINE_PLUGINS = (
    "opencode-gemini-auth@latest",
    "opencode-agent-memory",
    "opencode-mystatus",
    "opencode-handoff",
)
LEGACY_OCABRA_MODELS = {
    "gemma4:12b-vllm-ctx256k",
    "gemma4:26b-vllm-ctx64k",
    "nemotron-3-nano:30b-vllm-ctx256k",
    "qwen3-coder:30b-vllm-ctx56k",
    "qwen3.5:27b-vllm-ctx64k",
    "qwen3.6:35b-vllm-ctx64k",
    "gemma4:12b-ctx256k",
    "gemma4:26b-ctx160k",
    "ministral-3:14b-ctx128k",
    "nemotron-3-nano:30b-ctx256k",
    "nemotron-3-nano:30b-ctx384k",
    "nemotron3:33b-ctx64k",
    "qwen3-coder:30b-ctx256k",
    "qwen3.5:27b-ctx96k",
    "qwen3.6:ctx128k",
    "ravenx-256k",
}


def warn(message: str) -> None:
    print(f"sync-llm-models: {message}", file=sys.stderr)


def load_json(path: Path) -> dict[str, Any]:
    if not path.exists():
        return {}
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
        return value if isinstance(value, dict) else {}
    except (OSError, json.JSONDecodeError) as exc:
        warn(f"no se pudo leer {path}: {exc}")
        return {}


def write_json(path: Path, value: Any, mode: int = 0o600) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(
        json.dumps(value, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    temporary.chmod(mode)
    temporary.replace(path)


def normalize_model_id(raw: Any) -> str:
    if not isinstance(raw, str):
        return ""
    model_id = raw.strip()
    if "//" in model_id:
        model_id = model_id.split("//", 1)[1]
    return model_id


def request_json(base_url: str, api_key: str, suffix: str) -> Any:
    headers = {"Accept": "application/json"}
    if api_key:
        headers["Authorization"] = f"Bearer {api_key}"
    request = urllib.request.Request(f"{base_url}{suffix}", headers=headers)
    with urllib.request.urlopen(request, timeout=12) as response:
        return json.loads(response.read().decode("utf-8", "replace"))


def rows(payload: Any) -> list[dict[str, Any]]:
    if isinstance(payload, dict):
        payload = payload.get("data", [])
    if not isinstance(payload, list):
        return []
    return [item for item in payload if isinstance(item, dict)]


def positive_int(*values: Any) -> int:
    for value in values:
        if isinstance(value, int) and value > 0:
            return value
    return 0


def discover(base_url: str, api_key: str, required_suffix: str = "") -> list[dict[str, Any]]:
    base_url = base_url.strip().rstrip("/")
    if not base_url:
        return []

    discovered: dict[str, dict[str, Any]] = {}
    model_paths = ("/models",) if base_url.endswith("/v1") else ("/v1/models", "/models")
    for suffix in model_paths:
        try:
            for item in rows(request_json(base_url, api_key, suffix)):
                model_id = normalize_model_id(item.get("id"))
                if not model_id or (required_suffix and not model_id.endswith(required_suffix)):
                    continue
                discovered.setdefault(model_id, {"id": model_id, "raw": item})
            if discovered:
                break
        except Exception as exc:  # endpoints vary and startup must remain resilient
            warn(f"{base_url}{suffix} no disponible: {exc}")

    info_by_id: dict[str, dict[str, Any]] = {}
    info_paths = ("/model/info",) if base_url.endswith("/v1") else ("/v1/model/info", "/model/info")
    for suffix in info_paths:
        try:
            for item in rows(request_json(base_url, api_key, suffix)):
                model_id = normalize_model_id(item.get("model_name") or item.get("id"))
                if model_id in discovered:
                    info_by_id[model_id] = item
            if info_by_id:
                break
        except Exception:
            pass

    result: list[dict[str, Any]] = []
    for model_id, item in discovered.items():
        raw = item.get("raw", {})
        info = info_by_id.get(model_id, {})
        model_info = info.get("model_info", {})
        litellm = info.get("litellm_params", {})
        if not isinstance(model_info, dict):
            model_info = {}
        if not isinstance(litellm, dict):
            litellm = {}
        tags = {tag for tag in litellm.get("tags", []) if isinstance(tag, str)}
        context_window = positive_int(
            model_info.get("context_window"),
            model_info.get("max_model_len"),
            raw.get("context_window"),
            raw.get("context_length"),
            raw.get("max_model_len"),
        )
        output = positive_int(
            model_info.get("max_output_tokens"),
            model_info.get("max_completion_tokens"),
            raw.get("max_output_tokens"),
            raw.get("max_completion_tokens"),
        )
        input_limit = positive_int(
            model_info.get("max_input_tokens"),
            raw.get("max_input_tokens"),
        )
        if not input_limit and context_window:
            input_limit = max(context_window - output, 1) if output else context_window
        lowered = model_id.lower()
        reasoning = bool(model_info.get("supports_reasoning")) or bool(
            litellm.get("merge_reasoning_content_in_choices")
        ) or "capability:thinking" in tags or any(
            token in lowered for token in ("reason", "thinking", "qwen3", "nemotron")
        )
        inputs = {"text"}
        if model_info.get("supports_vision") or tags.intersection(
            {"capability:vision", "capability:image"}
        ):
            inputs.add("image")
        if model_info.get("supports_audio_input") or "capability:audio" in tags:
            inputs.add("audio")
        result.append(
            {
                "id": model_id,
                "name": raw.get("name") or model_id,
                "context_window": context_window,
                "input_limit": input_limit,
                "output": output,
                "reasoning": reasoning,
                "input": sorted(inputs),
                "cost": {
                    "input": litellm.get("input_cost_per_token") or 0,
                    "output": litellm.get("output_cost_per_token") or 0,
                    "cacheRead": litellm.get("cache_read_input_token_cost") or 0,
                    "cacheWrite": litellm.get("cache_creation_input_token_cost") or 0,
                },
            }
        )
    return result


def plugin_name(value: str) -> str:
    if value.startswith("@"):
        separator = value.find("@", 1)
        return value if separator < 0 else value[:separator]
    return value.split("@", 1)[0]


def clean_legacy_config(data: dict[str, Any]) -> None:
    if data.get("enabled_providers") in (
        ["opencode", "ocabra", "freeapi"],
        ["opencode", "ocabra", "freeapi", "google"],
    ):
        data.pop("enabled_providers", None)

    had_plugin_config = "plugin" in data
    plugins = data.get("plugin", [])
    if not isinstance(plugins, list):
        plugins = []
    had_retired_template_plugin = any(
        isinstance(value, str) and plugin_name(value) in RETIRED_TEMPLATE_PLUGINS
        for value in plugins
    )
    plugins = [
        value
        for value in plugins
        if isinstance(value, str) and plugin_name(value) not in RETIRED_TEMPLATE_PLUGINS
    ]
    if not had_plugin_config or had_retired_template_plugin:
        installed = {plugin_name(value) for value in plugins}
        for value in BASELINE_PLUGINS:
            if plugin_name(value) not in installed:
                plugins.append(value)
    if plugins or had_plugin_config:
        data["plugin"] = plugins

    providers = data.setdefault("provider", {})
    if not isinstance(providers, dict):
        providers = {}
        data["provider"] = providers

    ocabra = providers.get("ocabra")
    if isinstance(ocabra, dict):
        models = ocabra.get("models")
        if isinstance(models, dict):
            for model_id in LEGACY_OCABRA_MODELS:
                models.pop(model_id, None)
            if not models:
                ocabra.pop("models", None)

    opencode = providers.get("opencode")
    if isinstance(opencode, dict):
        opencode.pop("whitelist", None)
        if not opencode:
            providers.pop("opencode", None)

    openai = providers.get("openai")
    if isinstance(openai, dict):
        removed_legacy_models = False
        models = openai.get("models")
        if isinstance(models, dict):
            for model_id in list(models):
                if model_id.startswith("gpt-5.1"):
                    models.pop(model_id, None)
                    removed_legacy_models = True
            if not models:
                openai.pop("models", None)
        old_template_options = {
            "reasoningEffort": "medium",
            "reasoningSummary": "auto",
            "textVerbosity": "medium",
            "include": ["reasoning.encrypted_content"],
            "store": False,
        }
        if (
            removed_legacy_models
            and set(openai).issubset({"options"})
            and openai.get("options") == old_template_options
        ):
            providers.pop("openai", None)

    google = providers.get("google")
    if isinstance(google, dict):
        models = google.get("models")
        if isinstance(models, dict):
            for model_id in RETIRED_TEMPLATE_MODELS:
                models.pop(model_id, None)
            if not models:
                google.pop("models", None)
        whitelist = google.get("whitelist")
        if isinstance(whitelist, list):
            google["whitelist"] = [
                model_id for model_id in whitelist if model_id not in RETIRED_TEMPLATE_MODELS
            ]
            if not google["whitelist"]:
                google.pop("whitelist", None)
        if not google:
            providers.pop("google", None)


def opencode_models(models: list[dict[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for model in models:
        entry: dict[str, Any] = {"name": model["name"]}
        limit = {}
        if model["input_limit"]:
            limit["context"] = model["input_limit"]
        if model["output"]:
            limit["output"] = model["output"]
        if limit:
            entry["limit"] = limit
        result[model["id"]] = entry
    return result


def quality_score(model_id: str) -> tuple[int, tuple[int, ...], int, str]:
    lowered = model_id.lower()
    score = 0
    priorities = (
        ("gpt-6-astra", 1000),
        ("claude-fable-5-1", 990),
        ("claude-opus-5-5", 980),
        ("gemini-3.1-pro", 970),
        ("gpt-6.1-sol", 960),
        ("claude-sonnet-5-5", 950),
        ("gemini-3.8-flash", 940),
        ("qwen3.6", 900),
        ("qwen3-coder", 890),
        ("glm-5", 880),
        ("nemotron-3", 870),
    )
    for token, value in priorities:
        if token in lowered:
            score = value
            break
    if any(token in lowered for token in ("coder", "code", "reason", "thinking")):
        score += 12
    if any(token in lowered for token in ("mini", "nano", "lite", "tiny")):
        score -= 25
    versions = tuple(int(part) for part in re.findall(r"\d+", lowered)[:4])
    sizes = [int(value) for value in re.findall(r"(\d+)b(?:\W|$)", lowered)]
    return score, versions, max(sizes, default=0), lowered


def choose_default(catalogs: dict[str, list[dict[str, Any]]], requested: str) -> str:
    if requested and requested != "auto":
        return requested
    candidates: list[str] = []
    for provider, models in catalogs.items():
        preferred = os.environ.get(f"{provider.upper()}_DEFAULT_MODEL", "").strip()
        live_ids = {model["id"] for model in models}
        if preferred in live_ids:
            candidates.append(f"{provider}/{preferred}")
        candidates.extend(f"{provider}/{model['id']}" for model in models)
    if not candidates:
        return ""
    return max(candidates, key=lambda value: quality_score(value.split("/", 1)[1]))


def sync_opencode(
    path: Path,
    catalogs: dict[str, list[dict[str, Any]]],
    connections: dict[str, tuple[str, str]],
) -> None:
    data = load_json(path)
    data.setdefault("$schema", "https://opencode.ai/config.json")
    data.setdefault(
        "compaction",
        {
            "auto": True,
            "prune": True,
            "tail_turns": 8,
            "preserve_recent_tokens": 32000,
            "reserved": 40000,
        },
    )
    clean_legacy_config(data)
    providers = data.setdefault("provider", {})
    for provider_id, (base_url, api_key) in connections.items():
        if not base_url:
            continue
        provider = providers.setdefault(provider_id, {})
        provider["npm"] = "@ai-sdk/openai-compatible"
        provider["name"] = "FreeAPI" if provider_id == "freeapi" else "Ocabra"
        options = provider.setdefault("options", {})
        options["baseURL"] = base_url
        if api_key:
            options["apiKey"] = api_key
        if catalogs.get(provider_id):
            provider["models"] = opencode_models(catalogs[provider_id])

    requested = os.environ.get("OPENCODE_DEFAULT_MODEL", "").strip()
    selected = choose_default(catalogs, requested)
    if selected:
        data["model"] = selected
    elif data.get("model") in RETIRED_TEMPLATE_MODELS:
        data.pop("model", None)
    write_json(path, data)


def continue_roles(model_id: str) -> list[str]:
    lowered = model_id.lower()
    if "embed" in lowered or lowered.startswith(("bge-", "nomic-")):
        return ["embed"]
    if "fim" in lowered or (
        "coder" in lowered and re.search(r"(?:0[.]5|1[.]5|3|7)b(?:\W|$)", lowered)
    ):
        return ["autocomplete"]
    return ["chat", "edit", "apply"]


def sync_continue(
    path: Path,
    catalogs: dict[str, list[dict[str, Any]]],
    connections: dict[str, tuple[str, str]],
) -> None:
    if path.exists():
        try:
            existing = path.read_text(encoding="utf-8")
        except OSError:
            return
        if "mks-config" not in existing[:512]:
            warn(f"se conserva la configuración personalizada de Continue en {path}")
            return

    models = []
    for provider_id, provider_models in catalogs.items():
        base_url, api_key = connections[provider_id]
        for model in provider_models:
            roles = continue_roles(model["id"])
            entry: dict[str, Any] = {
                "name": f"[{provider_id.capitalize()}] {model['name']}",
                "provider": "openai",
                "model": model["id"],
                "apiBase": base_url,
                "apiKey": api_key,
                "roles": roles,
            }
            if roles == ["autocomplete"]:
                entry["autocompleteOptions"] = {
                    "debounceDelay": 200,
                    "maxPromptTokens": 600,
                }
            models.append(entry)
    if not models:
        return
    config = {
        "name": "mks-config",
        "version": "2.0.0",
        "schema": "v1",
        "models": models,
        "context": [
            {"provider": value}
            for value in ("diff", "open", "terminal", "problems", "codebase", "code", "docs")
        ],
        "prompts": [
            {
                "name": "write-tests",
                "description": "Write unit tests for highlighted code",
                "prompt": (
                    "Write a comprehensive set of unit tests for the selected code.\n"
                    "Include setup, meaningful edge cases, and teardown if needed.\n"
                    "Output only the test code. Do not modify files automatically."
                ),
            }
        ],
        "docs": [],
    }
    write_json(path, config)


def openclaw_provider(
    provider_id: str,
    catalogs: dict[str, list[dict[str, Any]]],
    connections: dict[str, tuple[str, str]],
) -> dict[str, Any]:
    base_url, _ = connections[provider_id]
    models = []
    for model in catalogs.get(provider_id, []):
        entry = {
            "id": model["id"],
            "name": model["name"],
            "reasoning": model["reasoning"],
            "input": model["input"],
            "cost": model["cost"],
        }
        effective_window = model["context_window"] or model["input_limit"]
        if effective_window:
            entry["contextWindow"] = effective_window
        if model["context_window"] and model["input_limit"] and model["input_limit"] != model["context_window"]:
            entry["contextTokens"] = model["input_limit"]
        if model["output"]:
            entry["maxTokens"] = model["output"]
        models.append(entry)
    return {
        "baseUrl": base_url,
        "auth": "api-key",
        "api": "openai-completions",
        "models": models,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--opencode", type=Path)
    parser.add_argument("--continue-config", type=Path)
    parser.add_argument("--openclaw-provider", choices=("ocabra", "freeapi"))
    parser.add_argument("--best-model", action="store_true")
    args = parser.parse_args()

    existing = load_json(args.opencode) if args.opencode else {}
    existing_providers = existing.get("provider", {})
    if not isinstance(existing_providers, dict):
        existing_providers = {}

    def existing_option(provider_id: str, option: str) -> str:
        provider = existing_providers.get(provider_id, {})
        if not isinstance(provider, dict):
            return ""
        options = provider.get("options", {})
        if not isinstance(options, dict):
            return ""
        value = options.get(option)
        return value.strip() if isinstance(value, str) else ""

    def saved_key(filename: str) -> str:
        path = Path.home() / ".opencode" / filename
        if not path.exists():
            return ""
        try:
            path.chmod(0o600)
            return path.read_text(encoding="utf-8").strip()
        except OSError:
            return ""

    connections = {
        "ocabra": (
            (
                os.environ.get("OCABRA_BASE_URL")
                or os.environ.get("OPENCODE_PROVIDER_URL")
                or existing_option("ocabra", "baseURL")
            ).strip().rstrip("/"),
            (
                os.environ.get("OCABRA_API_KEY")
                or os.environ.get("OPENCODE_API_KEY")
                or saved_key(".latest_ocabra_key")
                or existing_option("ocabra", "apiKey")
            ).strip(),
        ),
        "freeapi": (
            (
                os.environ.get("FREEAPI_BASE_URL")
                or existing_option("freeapi", "baseURL")
            ).strip().rstrip("/"),
            (
                os.environ.get("FREEAPI_API_KEY")
                or saved_key(".latest_freeapi_key")
                or existing_option("freeapi", "apiKey")
            ).strip(),
        ),
    }
    catalogs = {
        "ocabra": discover(*connections["ocabra"]),
        "freeapi": discover(*connections["freeapi"], required_suffix="-ha"),
    }
    if args.opencode:
        sync_opencode(args.opencode, catalogs, connections)
    if args.continue_config:
        sync_continue(args.continue_config, catalogs, connections)
    if args.openclaw_provider:
        print(
            json.dumps(
                openclaw_provider(args.openclaw_provider, catalogs, connections),
                separators=(",", ":"),
            )
        )
    if args.best_model:
        print(choose_default(catalogs, "auto"))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
