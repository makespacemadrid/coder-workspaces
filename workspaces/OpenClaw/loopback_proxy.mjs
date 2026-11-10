#!/usr/bin/env node
// Proxy HTTP/WebSocket mínimo para apps web que solo aceptan tráfico "local".
//
// El proxy de apps de Coder entrega el tráfico en 127.0.0.1 dentro del
// contenedor, pero con Host/Origin del dominio público y cabeceras
// X-Forwarded-*. OpenClaw y Hermes tratan eso como acceso remoto (piden
// pairing de dispositivo, rechazan el Host o el Origin). Este proxy escucha en
// loopback, reescribe Host/Origin al destino local y elimina las cabeceras de
// proxy, de forma que la app ve una conexión local normal.
//
// Solo es alcanzable vía el proxy autenticado de Coder (app con sharing
// "owner") o desde procesos del propio workspace, que ya pueden leer el token
// de la app. El token/sesión propio de cada app se sigue exigiendo.
//
// Uso: loopback-proxy <puerto-escucha> <puerto-destino> [redirigir-raíz-a]
//
// Con el tercer argumento (p. ej. "/openclaw/"), una petición a "/" responde
// 302 a esa ruta conservando la query. Sirve para apps con basePath: Coder
// siempre abre la app en "/" y la UI necesita aterrizar en su basePath con
// el ?token= intacto.
import http from "node:http";
import net from "node:net";

const [listenPort, targetPort] = process.argv.slice(2, 4).map(Number);
const rootRedirect = process.argv[4] || "";
if (!listenPort || !targetPort) {
  console.error("uso: loopback-proxy <puerto-escucha> <puerto-destino> [redirigir-raíz-a]");
  process.exit(2);
}
const TARGET_HOST = "127.0.0.1";
const LOCAL_ORIGIN = `http://${TARGET_HOST}:${targetPort}`;
const DROP = new Set(["forwarded", "x-real-ip", "via"]);

function rewriteHeaders(rawHeaders) {
  const out = [];
  for (let i = 0; i < rawHeaders.length; i += 2) {
    const name = rawHeaders[i];
    const lower = name.toLowerCase();
    if (DROP.has(lower) || lower.startsWith("x-forwarded-")) continue;
    if (lower === "host") {
      out.push(name, `${TARGET_HOST}:${targetPort}`);
    } else if (lower === "origin") {
      out.push(name, LOCAL_ORIGIN);
    } else if (lower === "referer") {
      try {
        const u = new URL(rawHeaders[i + 1]);
        out.push(name, LOCAL_ORIGIN + u.pathname + u.search);
      } catch {
        // Referer inválido: se descarta.
      }
    } else {
      out.push(name, rawHeaders[i + 1]);
    }
  }
  return out;
}

const server = http.createServer((req, res) => {
  if (rootRedirect) {
    const q = req.url.indexOf("?");
    const path = q === -1 ? req.url : req.url.slice(0, q);
    if (path === "/") {
      res.writeHead(302, { location: rootRedirect + (q === -1 ? "" : req.url.slice(q)), "cache-control": "no-store" });
      res.end();
      return;
    }
  }
  const upstream = http.request(
    {
      host: TARGET_HOST,
      port: targetPort,
      method: req.method,
      path: req.url,
      headers: rewriteHeaders(req.rawHeaders),
    },
    (up) => {
      res.writeHead(up.statusCode || 502, up.statusMessage, up.rawHeaders);
      up.pipe(res);
    },
  );
  upstream.on("error", () => {
    if (!res.headersSent) res.writeHead(502, { "content-type": "text/plain" });
    res.end("upstream no disponible\n");
  });
  req.pipe(upstream);
});

server.on("upgrade", (req, socket, head) => {
  const upstream = net.connect(targetPort, TARGET_HOST, () => {
    const headers = rewriteHeaders(req.rawHeaders);
    let raw = `${req.method} ${req.url} HTTP/1.1\r\n`;
    for (let i = 0; i < headers.length; i += 2) raw += `${headers[i]}: ${headers[i + 1]}\r\n`;
    upstream.write(raw + "\r\n");
    if (head && head.length) upstream.write(head);
    upstream.pipe(socket);
    socket.pipe(upstream);
  });
  const close = () => {
    socket.destroy();
    upstream.destroy();
  };
  upstream.on("error", close);
  socket.on("error", close);
  upstream.on("close", close);
  socket.on("close", close);
});

server.keepAliveTimeout = 65000;
server.requestTimeout = 0;
server.listen(listenPort, TARGET_HOST, () => {
  console.log(`loopback-proxy :${listenPort} -> ${TARGET_HOST}:${targetPort}`);
});
