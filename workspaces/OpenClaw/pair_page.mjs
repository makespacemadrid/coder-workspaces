#!/usr/bin/env node
// Página "Conectar móvil": genera un código de configuración de OpenClaw
// (`openclaw qr --json`) y lo muestra como QR para la app oficial de
// iOS/Android. Cada carga crea un código nuevo, de un solo uso y que caduca.
//
// El QR codifica exactamente el setupCode con corrección de errores "M",
// igual que el QR oficial de `openclaw qr` (verificado módulo a módulo).
// Usa la librería qrcode que ya trae OpenClaw.
//
// Solo escucha en 127.0.0.1; se publica como app de Coder con sharing
// "owner", así que solo la ve el dueño del workspace.
//
// Uso: openclaw-pair-page <puerto>
import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import { execFile } from "node:child_process";
import { createRequire } from "node:module";

const port = Number(process.argv[2]);
if (!port) {
  console.error("uso: openclaw-pair-page <puerto>");
  process.exit(2);
}

function findOpenclawPackage() {
  for (const dir of (process.env.PATH || "").split(":")) {
    const bin = path.join(dir, "openclaw");
    if (fs.existsSync(bin)) return path.dirname(fs.realpathSync(bin));
  }
  throw new Error("openclaw no está en el PATH");
}
const QR = createRequire(path.join(findOpenclawPackage(), "package.json"))("qrcode");

const esc = (s) => String(s).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);

function setupCode() {
  return new Promise((resolve, reject) => {
    execFile("openclaw", ["qr", "--json"], { timeout: 60000, maxBuffer: 1 << 20 }, (err, stdout) => {
      if (err) return reject(new Error("openclaw qr falló: " + (err.message || err)));
      try {
        resolve(JSON.parse(stdout));
      } catch {
        reject(new Error("respuesta inesperada de openclaw qr"));
      }
    });
  });
}

// ¿Llega el móvil al gateway? Sin sesión de Coder, una URL privada redirige al
// login de Coder; una pública llega al gateway.
async function reachable(gatewayUrl) {
  const url = gatewayUrl.replace(/^wss:/, "https:").replace(/^ws:/, "http:").replace(/\/?$/, "/");
  try {
    const r = await fetch(url, { redirect: "manual", signal: AbortSignal.timeout(8000) });
    // Público solo si contesta el propio gateway (HTML de la Control UI). Una
    // URL privada redirige al login de Coder; una app inexistente da 404.
    const text = r.status === 200 ? await r.text() : "";
    return /control-ui|openclaw/i.test(text) && !/coder/i.test(r.headers.get("server") || "") ? "publico" : "privado";
  } catch {
    return "desconocido";
  }
}

function page(body) {
  return `<!doctype html><html lang="es"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>Conectar móvil · OpenClaw</title>
<style>
body{font-family:system-ui,sans-serif;max-width:640px;margin:2rem auto;padding:0 1rem;color:#222;line-height:1.5}
h1{font-size:1.5rem}.qr{background:#fff;padding:12px;border:1px solid #ddd;border-radius:12px;width:320px;margin:1rem auto}
.qr svg{width:100%;height:auto;display:block}.warn{background:#fff4e5;border:1px solid #f0b46c;padding:.75rem 1rem;border-radius:8px}
.ok{background:#eaf7ea;border:1px solid #8bc38b;padding:.75rem 1rem;border-radius:8px}
code,textarea{font-family:ui-monospace,monospace;font-size:.8rem}textarea{width:100%;height:5rem}
a.btn{display:inline-block;background:#c0392b;color:#fff;padding:.5rem 1rem;border-radius:8px;text-decoration:none}
</style></head><body>${body}</body></html>`;
}

const server = http.createServer(async (req, res) => {
  if (req.url !== "/" && !req.url.startsWith("/?")) {
    res.writeHead(404).end();
    return;
  }
  let body;
  try {
    const qr = await setupCode();
    const [svg, estado] = await Promise.all([
      QR.toString(qr.setupCode, { type: "svg", errorCorrectionLevel: "M", margin: 2 }),
      reachable(qr.gatewayUrl),
    ]);
    const aviso =
      estado === "privado"
        ? `<p class="warn"><b>El gateway no es accesible desde Internet.</b> Activa <i>[OpenClaw] Acceso desde el móvil</i> en los parámetros del workspace (Settings → Parameters → Update), o pon el puerto <b>3333</b> en <b>Public</b> desde el panel <i>Ports</i> de Coder. Después recarga esta página.</p>`
        : estado === "publico"
          ? `<p class="ok">El gateway es accesible desde el móvil.</p>`
          : `<p class="warn">No se ha podido comprobar si el gateway es accesible desde Internet.</p>`;
    body = `<h1>Conectar el móvil a OpenClaw</h1>${aviso}
<ol><li>Instala la app oficial de OpenClaw (iOS/Android).</li>
<li>En la app: <i>Settings → Gateway</i> (o <i>Onboarding → Scan QR</i>) y escanea este código.</li>
<li>La app se vincula sola. El código es de un solo uso y caduca en unos minutos.</li></ol>
<div class="qr">${svg}</div>
<p style="text-align:center"><a class="btn" href="./">Generar código nuevo</a></p>
<details><summary>Copiar el código a mano</summary><textarea readonly>${esc(qr.setupCode)}</textarea></details>
<p><small>Gateway: <code>${esc(qr.gatewayUrl)}</code> · acceso: ${esc(qr.access)}</small></p>`;
  } catch (err) {
    body = `<h1>Conectar el móvil a OpenClaw</h1><p class="warn">No se pudo generar el código: ${esc(err.message)}. ¿Está arrancado OpenClaw? Revisa <code>~/.local/state/openclaw/openclaw.log</code>.</p>`;
  }
  res.writeHead(200, { "content-type": "text/html; charset=utf-8", "cache-control": "no-store" });
  res.end(page(body));
});

server.listen(port, "127.0.0.1", () => console.log(`openclaw-pair-page en 127.0.0.1:${port}`));
