#!/usr/bin/env bash
set -euo pipefail

mkdir -p \
  "$HOME/.cache/mcp-slicer" \
  "$HOME/.codex" \
  "$HOME/.config/Claude" \
  "$HOME/.config/inkscape/extensions" \
  "$HOME/.config/opencode" \
  "$HOME/.local/bin" \
  "$HOME/.local/share/mcp-servers" \
  "$HOME/.opencode" \
  "$HOME/Desktop"

clone_or_update() {
  local repo_url="$1"
  local target_dir="$2"

  if [ -d "$target_dir/.git" ]; then
    git -C "$target_dir" pull --ff-only >/dev/null 2>&1 || true
    return
  fi

  rm -rf "$target_dir"
  git clone --depth 1 "$repo_url" "$target_dir" >/dev/null 2>&1 || {
    echo "WARN: no se pudo clonar $repo_url" >&2
    return 0
  }
}

echo ">> Preparando servidores MCP de Maker..."
uv_python_dir=/opt/uv-python
mcp_python="$(UV_PYTHON_INSTALL_DIR="$uv_python_dir" uv python find 3.13)"
clone_or_update "https://github.com/mixelpixx/KiCAD-MCP-Server.git" "$HOME/.local/share/mcp-servers/kicad-mcp-server"
clone_or_update "https://github.com/quellant/openscad-mcp.git" "$HOME/.local/share/mcp-servers/openscad-mcp"
clone_or_update "https://github.com/maorcc/gimp-mcp.git" "$HOME/.local/share/mcp-servers/gimp-mcp"
clone_or_update "https://github.com/Shriinivas/inkmcp.git" "$HOME/.config/inkscape/extensions/inkmcp"
clone_or_update "https://github.com/neka-nat/freecad-mcp.git" "$HOME/.local/share/mcp-servers/freecad-mcp"

# Sustituir el antiguo add-on comunitario por el oficial de Blender Lab que ya
# viene horneado en la imagen.
legacy_blender_addon=false
for addon in "$HOME"/.config/blender/*/scripts/addons/blender_mcp.py; do
  if [ -f "$addon" ]; then
    legacy_blender_addon=true
    break
  fi
done
if [ "$legacy_blender_addon" = true ]; then
  blender --background --python-expr "import bpy; module='blender_mcp'; enabled=module in bpy.context.preferences.addons; enabled and bpy.ops.preferences.addon_disable(module=module); enabled and bpy.ops.wm.save_userpref()" >/dev/null 2>&1 || true
  for addon in "$HOME"/.config/blender/*/scripts/addons/blender_mcp.py; do
    [ ! -f "$addon" ] || rm -f -- "$addon"
  done
fi

blender_mcp_revision="$(cat /opt/blender-mcp-revision 2>/dev/null || true)"
blender_mcp_marker="$HOME/.config/blender/.mks-blender-mcp-revision"
blender_mm="$(blender --version 2>/dev/null | awk 'NR == 1 { split($2, version, "."); print version[1] "." version[2] }')"
blender_mcp_manifest="$HOME/.config/blender/$blender_mm/extensions/user_default/mcp/blender_manifest.toml"
if [ -n "$blender_mcp_revision" ] && \
   { [ "$(cat "$blender_mcp_marker" 2>/dev/null || true)" != "$blender_mcp_revision" ] || \
     [ ! -f "$blender_mcp_manifest" ]; }; then
  if blender --command extension install-file --repo=user_default --enable /opt/blender-mcp-addon.zip >/dev/null 2>&1; then
    mkdir -p "$(dirname "$blender_mcp_marker")"
    printf '%s\n' "$blender_mcp_revision" > "$blender_mcp_marker"
  else
    echo "WARN: no se pudo instalar el add-on oficial Blender MCP" >&2
  fi
fi

# Add-on de FreeCAD.
mkdir -p "$HOME/.local/share/FreeCAD/Mod" "$HOME/.FreeCAD/Mod"
if [ -d "$HOME/.local/share/mcp-servers/freecad-mcp/addon/FreeCADMCP" ]; then
  rm -rf "$HOME/.local/share/FreeCAD/Mod/FreeCADMCP" "$HOME/.FreeCAD/Mod/FreeCADMCP"
  cp -r "$HOME/.local/share/mcp-servers/freecad-mcp/addon/FreeCADMCP" "$HOME/.local/share/FreeCAD/Mod/FreeCADMCP"
  cp -r "$HOME/.local/share/mcp-servers/freecad-mcp/addon/FreeCADMCP" "$HOME/.FreeCAD/Mod/FreeCADMCP"
fi

# Extensión y launcher de Inkscape.
if [ -f "$HOME/.config/inkscape/extensions/inkmcp/inkscape_mcp.inx" ]; then
  cp -f "$HOME/.config/inkscape/extensions/inkmcp/inkscape_mcp.inx" "$HOME/.config/inkscape/extensions/inkscape_mcp.inx"
fi
cat > "$HOME/.config/inkscape/extensions/inkscape_mcp.py" <<'PY'
#!/usr/bin/env python3
import os
import runpy
import sys

base = os.path.expanduser("~/.config/inkscape/extensions")
repo = os.path.join(base, "inkmcp")
for path in (base, repo):
    if path not in sys.path:
        sys.path.insert(0, path)

target = os.path.join(repo, "inkscape_mcp.py")
if not os.path.isfile(target):
    raise SystemExit(f"inkscape_mcp.py no encontrado en {target}")
runpy.run_path(target, run_name="__main__")
PY
chmod +x "$HOME/.config/inkscape/extensions/inkscape_mcp.py"
chmod +x \
  "$HOME/.config/inkscape/extensions/inkmcp/inkmcp/run_inkscape_mcp.sh" \
  "$HOME/.config/inkscape/extensions/inkmcp/inkmcp/inkmcpcli.py" \
  "$HOME/.config/inkscape/extensions/inkmcp/inkmcp/inkscape_mcp_server.py" \
  "$HOME/.config/inkscape/extensions/inkmcp/inkmcp/main.py" 2>/dev/null || true

if command -v uv >/dev/null 2>&1; then
  [ ! -d "$HOME/.local/share/mcp-servers/openscad-mcp" ] || \
    env -u VIRTUAL_ENV UV_PYTHON_INSTALL_DIR="$uv_python_dir" uv sync --python "$mcp_python" --directory "$HOME/.local/share/mcp-servers/openscad-mcp" >/dev/null 2>&1 || true
  [ ! -d "$HOME/.local/share/mcp-servers/gimp-mcp" ] || \
    env -u VIRTUAL_ENV UV_PYTHON_INSTALL_DIR="$uv_python_dir" uv sync --python "$mcp_python" --directory "$HOME/.local/share/mcp-servers/gimp-mcp" >/dev/null 2>&1 || true
fi

# Compilar KiCad MCP una sola vez y preparar Freerouting.
kicad_mcp_dir="$HOME/.local/share/mcp-servers/kicad-mcp-server"
if [ -d "$kicad_mcp_dir" ] && [ ! -f "$kicad_mcp_dir/dist/index.js" ] && command -v npm >/dev/null 2>&1; then
  ( cd "$kicad_mcp_dir" \
    && npm install --no-fund --no-audit >/dev/null 2>&1 \
    && { [ ! -f requirements.txt ] || python3 -m pip install --user --quiet --break-system-packages -r requirements.txt >/dev/null 2>&1 || true; } \
    && npm run build >/dev/null 2>&1 ) || echo "WARN: no se pudo compilar KiCad MCP" >&2
fi
mkdir -p "$HOME/.kicad-mcp"
if [ ! -e "$HOME/.kicad-mcp/freerouting.jar" ] && [ -f /opt/freerouting/freerouting.jar ]; then
  ln -s /opt/freerouting/freerouting.jar "$HOME/.kicad-mcp/freerouting.jar"
fi

if [ -f "$HOME/.config/inkscape/extensions/inkmcp/inkmcp/requirements.txt" ]; then
  inkscape_mcp_venv="$HOME/.local/share/mcp-servers/inkscape-mcp-venv"
  if [ -x "$inkscape_mcp_venv/bin/python" ] && \
     ! "$inkscape_mcp_venv/bin/python" -c 'import sys; raise SystemExit(sys.version_info[:2] != (3, 13))'; then
    rm -rf "$inkscape_mcp_venv"
  fi
  if [ ! -x "$inkscape_mcp_venv/bin/python" ]; then
    env -u VIRTUAL_ENV UV_PYTHON_INSTALL_DIR="$uv_python_dir" uv venv --python "$mcp_python" "$inkscape_mcp_venv" >/dev/null
  fi
  env -u VIRTUAL_ENV UV_PYTHON_INSTALL_DIR="$uv_python_dir" uv pip install --python "$inkscape_mcp_venv/bin/python" --quiet \
    -r "$HOME/.config/inkscape/extensions/inkmcp/inkmcp/requirements.txt" fastmcp 'mcp<2' >/dev/null
fi

cat > "$HOME/.local/bin/inkscape-mcp-launcher" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
base="$HOME/.config/inkscape/extensions/inkmcp/inkmcp"
if [ ! -f "$base/main.py" ]; then
  echo "inkmcp no encontrado en $base" >&2
  exit 1
fi
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=${XDG_RUNTIME_DIR}/bus}"
python="$HOME/.local/share/mcp-servers/inkscape-mcp-venv/bin/python"
if [ ! -x "$python" ]; then
  echo "entorno virtual de inkMCP no encontrado en $python" >&2
  exit 1
fi
exec "$python" "$base/main.py"
SH
chmod +x "$HOME/.local/bin/inkscape-mcp-launcher"

# Codex usa TOML. Se conservan el resto de ajustes y servidores del usuario.
touch "$HOME/.codex/config.toml"
/usr/bin/python3 - "$HOME/.codex/config.toml" <<'PY'
import json
import os
import re
import stat
import sys
import tempfile
import tomllib

path = sys.argv[1]
home = os.path.expanduser("~")
with open(path, encoding="utf-8") as handle:
    original = handle.read()

try:
    parsed = tomllib.loads(original)
except tomllib.TOMLDecodeError as exc:
    print(f"WARN: config.toml de Codex no es válido; no se modifica: {exc}", file=sys.stderr)
    raise SystemExit(0)

q = json.dumps
kicad_entry = os.path.join(home, ".local", "share", "mcp-servers", "kicad-mcp-server", "dist", "index.js")
openscad_dir = os.path.join(home, ".local", "share", "mcp-servers", "openscad-mcp")
gimp_dir = os.path.join(home, ".local", "share", "mcp-servers", "gimp-mcp")
ink_launcher = os.path.join(home, ".local", "bin", "inkscape-mcp-launcher")
slicer_cache = os.path.join(home, ".cache", "mcp-slicer")
fragments = {
    "blender": '[mcp_servers.blender]\ncommand = "/usr/local/bin/blender-mcp"',
    "freecad": '[mcp_servers.freecad]\ncommand = "uvx"\nargs = ["freecad-mcp"]',
    "kicad": f'[mcp_servers.kicad]\ncommand = "node"\nargs = [{q(kicad_entry)}]\nenv = {{ NODE_ENV = "production", LOG_LEVEL = "info", KICAD_AUTO_LAUNCH = "false", PYTHONPATH = "/usr/lib/python3/dist-packages:/usr/share/kicad/scripting/plugins:/usr/lib/kicad/lib/python3/dist-packages" }}',
    "openscad": f'[mcp_servers.openscad]\ncommand = "uv"\nargs = ["run", "--directory", {q(openscad_dir)}, "openscad-mcp"]\nenv = {{ OPENSCAD_PATH = "/usr/bin/openscad" }}',
    "gimp": f'[mcp_servers.gimp]\ncommand = "uv"\nargs = ["run", "--directory", {q(gimp_dir)}, "gimp_mcp_server.py"]',
    "slicer": f'[mcp_servers.slicer]\ncommand = "npx"\nargs = ["-y", "mcp-3d-printer-server"]\nenv = {{ SLICER_TYPE = "prusaslicer", SLICER_PATH = "/usr/bin/prusa-slicer", TEMP_DIR = {q(slicer_cache)} }}',
    "inkscape": f'[mcp_servers.inkscape]\ncommand = {q(ink_launcher)}',
}

content = original.rstrip("\n")
existing = parsed.get("mcp_servers", {})
for name, fragment in fragments.items():
    if name == "blender" and name in existing:
        content = re.sub(
            rf"(?ms)^\[mcp_servers\.{name}\]\n.*?(?=^\[|\Z)",
            fragment + "\n\n",
            content,
        ).rstrip("\n")
    elif name not in existing:
        content = ((content + "\n\n") if content else "") + fragment

candidate = content + ("\n" if content else "")
tomllib.loads(candidate)
if candidate != original:
    mode = stat.S_IMODE(os.stat(path).st_mode)
    fd, temporary = tempfile.mkstemp(prefix=".config.toml.", dir=os.path.dirname(path), text=True)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write(candidate)
        os.chmod(temporary, mode)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)
PY

# Claude Code, Claude Desktop y OpenCode usan JSON; fusionar sin borrar ajustes.
/usr/bin/python3 <<'PY'
import json
import os

home = os.path.expanduser("~")
mcp_root = os.path.join(home, ".local", "share", "mcp-servers")
kicad_entry = os.path.join(mcp_root, "kicad-mcp-server", "dist", "index.js")
openscad_dir = os.path.join(mcp_root, "openscad-mcp")
gimp_dir = os.path.join(mcp_root, "gimp-mcp")
ink_launcher = os.path.join(home, ".local", "bin", "inkscape-mcp-launcher")
kicad_env = {
    "NODE_ENV": "production",
    "LOG_LEVEL": "info",
    "KICAD_AUTO_LAUNCH": "false",
    "PYTHONPATH": "/usr/lib/python3/dist-packages:/usr/share/kicad/scripting/plugins:/usr/lib/kicad/lib/python3/dist-packages",
}
openscad_env = {"OPENSCAD_PATH": "/usr/bin/openscad"}
slicer_env = {
    "SLICER_TYPE": "prusaslicer",
    "SLICER_PATH": "/usr/bin/prusa-slicer",
    "TEMP_DIR": os.path.join(home, ".cache", "mcp-slicer"),
}
claude_servers = {
    "blender": {"command": "/usr/local/bin/blender-mcp", "args": []},
    "freecad": {"command": "uvx", "args": ["freecad-mcp"]},
    "kicad": {"command": "node", "args": [kicad_entry], "env": kicad_env},
    "openscad": {"command": "uv", "args": ["run", "--directory", openscad_dir, "openscad-mcp"], "env": openscad_env},
    "gimp": {"command": "uv", "args": ["run", "--directory", gimp_dir, "gimp_mcp_server.py"]},
    "slicer": {"command": "npx", "args": ["-y", "mcp-3d-printer-server"], "env": slicer_env},
    "inkscape": {"command": ink_launcher},
}
opencode_servers = {
    name: {
        "type": "local",
        "enabled": True,
        "command": [server["command"], *server.get("args", [])],
        **({"environment": server["env"]} if "env" in server else {}),
    }
    for name, server in claude_servers.items()
}

def load(path):
    if not os.path.exists(path):
        return {}
    try:
        with open(path, encoding="utf-8") as handle:
            return json.load(handle)
    except (OSError, ValueError):
        return {}

def save(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    temporary = path + ".tmp"
    with open(temporary, "w", encoding="utf-8") as handle:
        json.dump(data, handle, indent=2)
        handle.write("\n")
    os.replace(temporary, path)

for path in (
    os.path.join(home, ".claude.json"),
    os.path.join(home, ".config", "Claude", "claude_desktop_config.json"),
):
    config = load(path)
    config.setdefault("mcpServers", {}).update(claude_servers)
    save(path, config)

opencode_path = os.path.join(home, ".config", "opencode", "opencode.json")
config = load(opencode_path)
config.setdefault("mcp", {}).update(opencode_servers)
save(opencode_path, config)
PY
ln -sfn "$HOME/.config/opencode/opencode.json" "$HOME/.opencode/opencode.json"
ln -sfn "$HOME/.config/opencode/opencode.json" "$HOME/.opencode/config.json"

cat > "$HOME/Desktop/MCPS-README.md" <<'EOF'
# MCPs en Maker Selkies

Configurados para Codex, Claude Code, Claude Desktop y OpenCode:

- Blender
- FreeCAD
- KiCad
- OpenSCAD
- Inkscape
- GIMP
- Slicer (PrusaSlicer mediante `mcp-3d-printer-server`)

Comprobación rápida:

```bash
codex mcp list
claude mcp list
opencode mcp list
```

Blender y FreeCAD necesitan que abras la aplicación y arranques su servidor
desde el add-on. Inkscape necesita estar abierto. Para GIMP, copia una vez el
plugin y arranca el servidor desde `Tools`:

```bash
mkdir -p ~/.config/GIMP/3.0/plug-ins/gimp-mcp-plugin
cp ~/.local/share/mcp-servers/gimp-mcp/gimp-mcp-plugin.py ~/.config/GIMP/3.0/plug-ins/gimp-mcp-plugin/
chmod +x ~/.config/GIMP/3.0/plug-ins/gimp-mcp-plugin/gimp-mcp-plugin.py
```
EOF

echo ">> MCPs de Maker configurados. Consulta ~/Desktop/MCPS-README.md."
