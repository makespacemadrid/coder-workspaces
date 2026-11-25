#!/usr/bin/env node
// Página "Completar configuración": pasos manuales que quedan tras crear el
// workspace (hoy, la contraseña de Joplin) con un formulario para hacerlos sin
// terminal.
//
// Solo escucha en 127.0.0.1; Coder la publica como app con sharing "owner".
// Los POST exigen que Origin coincida con Host (sin CSRF desde otros sitios).
//
// Uso: openclaw-setup-page <puerto>
import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import { spawn } from "node:child_process";

const port = Number(process.argv[2]);
if (!port) {
  console.error("uso: openclaw-setup-page <puerto>");
  process.exit(2);
}
const HOME = process.env.HOME;
const PATH = `${HOME}/.npm-global/bin:${HOME}/.local/bin:${process.env.PATH}`;
const env = { ...process.env, PATH };
const joplinEnabled = process.env.JOPLIN_ENABLED === "true";
const joplinMarker = path.join(HOME, ".local/state/openclaw/joplin-setup.ok");

const esc = (s) => String(s).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);
const has = (bin) => PATH.split(":").some((d) => fs.existsSync(path.join(d, bin)));

function readJoplinConfig() {
  try {
    const out = {};
    for (const line of fs.readFileSync(path.join(HOME, ".joplin-server-config"), "utf8").split("\n")) {
      const i = line.indexOf("=");
      if (i > 0) out[line.slice(0, i)] = line.slice(i + 1);
    }
    return out;
  } catch {
    return {};
  }
}

function runJoplinSetup(password, url, email) {
  return new Promise((resolve) => {
    const childEnv = { ...env, JOPLIN_SETUP_URL: url, JOPLIN_SETUP_EMAIL: email };
    const child = spawn("openclaw-joplin-setup", ["--stdin"], { env: childEnv, stdio: ["pipe", "pipe", "pipe"] });
    let out = "";
    child.stdout.on("data", (d) => (out += d));
    child.stderr.on("data", (d) => (out += d));
    const timer = setTimeout(() => child.kill("SIGTERM"), 300000);
    child.on("close", (code) => {
      clearTimeout(timer);
      resolve({ ok: code === 0, out: out.trim().split("\n").slice(-15).join("\n") });
    });
    child.stdin.end(password + "\n");
  });
}

function page(body) {
  return `<!doctype html><html lang="es"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>Completar configuración · OpenClaw</title>
<style>
body{font-family:system-ui,sans-serif;max-width:680px;margin:2rem auto;padding:0 1rem;color:#222;line-height:1.5}
h1{font-size:1.5rem}section{border:1px solid #ddd;border-radius:10px;padding:1rem 1.2rem;margin:1rem 0}
h2{font-size:1.1rem;margin:.2rem 0 .6rem}.ok{color:#1d7a1d}.todo{color:#b25d00}
input[type=password],input[type=url],input[type=email]{width:100%;padding:.5rem;font-size:1rem;box-sizing:border-box;margin-bottom:.4rem}
button{background:#c0392b;color:#fff;border:0;padding:.55rem 1.1rem;border-radius:8px;font-size:1rem;margin-top:.6rem;cursor:pointer}
pre{background:#f6f6f6;padding:.6rem;border-radius:6px;white-space:pre-wrap;font-size:.8rem}code{font-size:.85rem}
</style></head><body><h1>Completar configuración</h1>${body}</body></html>`;
}

async function render(result) {
  let body = "";
  if (joplinEnabled) {
    const cfg = readJoplinConfig();
    const done = fs.existsSync(joplinMarker);
    const installed = has("joplin");
    body += `<section><h2>📓 Joplin ${done ? '<span class="ok">✅ configurado</span>' : '<span class="todo">⏳ pendiente</span>'}</h2>`;
    const url = cfg.JOPLIN_SERVER_URL || process.env.JOPLIN_SERVER_URL || "";
    const email = cfg.JOPLIN_EMAIL || process.env.JOPLIN_EMAIL || "";
    const hasPassword = Boolean(cfg.JOPLIN_PASSWORD);
    if (!installed) {
      body += `<p class="todo">Joplin CLI se está instalando (script <i>Joplin</i> del workspace). Recarga esta página en un par de minutos.</p>`;
    } else {
      body += `<form method="post" action="./joplin">
<label>Servidor de Joplin<br><input type="url" name="url" value="${esc(url)}" placeholder="https://joplin.ejemplo.org" required></label><br>
<label>Usuario (email)<br><input type="email" name="email" value="${esc(email)}" placeholder="tu@email" required></label><br>
<label>Contraseña${hasPassword ? " <small>(déjala vacía para conservar la guardada)</small>" : ""}<br>
<input type="password" name="password" autocomplete="current-password"${hasPassword ? "" : " required"}></label><br>
<button type="submit">${done ? "Guardar y sincronizar" : "Guardar y hacer el primer sync"}</button></form>
<p><small>Se guarda solo en este workspace (<code>~/.joplin-server-config</code>, permisos 600); la contraseña no pasa por Coder.
Si cambias de servidor o de cuenta, las notas locales se subirán a la nueva. Cambiar <b>Servidor</b> o <b>Usuario</b> en los parámetros del workspace también se aplica, en el siguiente arranque.</small></p>`;
    }
    if (result) body += `<p class="${result.ok ? "ok" : "todo"}">${result.ok ? "✅ Listo." : "❌ No se pudo completar:"}</p><pre>${esc(result.out)}</pre>`;
    body += `</section>`;
  }
  if (!body) body = `<p class="ok">✅ No hay pasos pendientes.</p>`;
  return page(body);
}

function readBody(req) {
  return new Promise((resolve) => {
    let data = "";
    req.on("data", (d) => { data += d; if (data.length > 10000) req.destroy(); });
    req.on("end", () => resolve(new URLSearchParams(data)));
  });
}

const server = http.createServer(async (req, res) => {
  const send = (html, status = 200) => {
    res.writeHead(status, { "content-type": "text/html; charset=utf-8", "cache-control": "no-store" });
    res.end(html);
  };
  try {
    const url = new URL(req.url, "http://x");
    if (req.method === "GET" && url.pathname === "/") return send(await render());
    if (req.method === "POST" && url.pathname === "/joplin" && joplinEnabled) {
      const origin = req.headers.origin || "";
      if (!origin || new URL(origin).host !== req.headers.host) return send(page("<p>Origen no permitido.</p>"), 403);
      const form = await readBody(req);
      const url = (form.get("url") || "").trim();
      const email = (form.get("email") || "").trim();
      if (!/^https?:\/\//.test(url) || !email) return send(await render({ ok: false, out: "Indica un servidor (https://…) y un usuario." }));
      return send(await render(await runJoplinSetup(form.get("password") || "", url, email)));
    }
    send(page("<p>No encontrado.</p>"), 404);
  } catch (err) {
    send(page(`<p>Error: ${esc(err.message)}</p>`), 500);
  }
});

server.listen(port, "127.0.0.1", () => console.log(`openclaw-setup-page en 127.0.0.1:${port}`));
