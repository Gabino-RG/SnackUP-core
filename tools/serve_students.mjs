import http from 'node:http';
import https from 'node:https';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const argumentsList = process.argv.slice(2);
function option(name, fallback) {
  const at = argumentsList.indexOf(name);
  return at < 0 ? fallback : argumentsList[at + 1];
}
const project = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const webRoot = path.resolve(project, option('--web', 'build/web'));
const port = Number(option('--port', '8000'));
const upstream = new URL(option('--backend', 'http://127.0.0.1:8001'));
if (!Number.isInteger(port) || port < 1024 || port > 65535) throw new Error('Use a local port between 1024 and 65535.');
if (!['http:', 'https:'].includes(upstream.protocol) || !['localhost', '127.0.0.1', '[::1]'].includes(upstream.hostname)
    || upstream.username || upstream.password || upstream.pathname !== '/' || upstream.search || upstream.hash) {
  throw new Error('--backend must be a local HTTP(S) origin without credentials or a path.');
}
const transport = upstream.protocol === 'https:' ? https : http;
const mime = {'.html': 'text/html; charset=utf-8', '.js': 'application/javascript', '.json': 'application/json',
  '.wasm': 'application/wasm', '.css': 'text/css', '.png': 'image/png', '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg',
  '.webp': 'image/webp', '.svg': 'image/svg+xml', '.ico': 'image/x-icon', '.ttf': 'font/ttf', '.otf': 'font/otf'};
const apiRoute = value => /^\/(api|socket\.io|media|health)(\/|$)/.test(value);
const validHost = host => host === `localhost:${port}` || host === `127.0.0.1:${port}`;
function allowed(request) {
  return typeof request.url === 'string' && request.url.startsWith('/') && !request.url.startsWith('//')
    && !request.url.includes('\\') && validHost(request.headers.host)
    && (!request.headers.origin || request.headers.origin === `http://${request.headers.host}`);
}
function headers(request) {
  const result = {...request.headers};
  // Keep the actual browser Host and Origin. Configure the unchanged backend's
  // public origin to match this local entry point; do not bypass its CSRF check.
  delete result.forwarded;
  for (const name of Object.keys(result)) if (name.startsWith('x-forwarded-')) delete result[name];
  return result;
}
const server = http.createServer((request, response) => {
  if (!allowed(request)) { response.writeHead(403); response.end('Origen no autorizado.'); return; }
  const url = new URL(request.url, `http://${request.headers.host}`);
  if (apiRoute(url.pathname)) {
    const forward = transport.request(new URL(request.url, upstream), {
      method: request.method, headers: headers(request),
    }, incoming => {
      response.writeHead(incoming.statusCode, incoming.headers);
      incoming.pipe(response);
    });
    forward.on('error', () => {
      if (!response.headersSent) response.writeHead(502, {'content-type': 'application/json', 'cache-control': 'no-store'});
      response.end(JSON.stringify({error: {code: 'BACKEND_UNAVAILABLE', message: 'No se pudo conectar con el backend local.'}}));
    });
    request.on('aborted', () => forward.destroy());
    request.pipe(forward);
    return;
  }
  if (!['GET', 'HEAD'].includes(request.method)) { response.writeHead(405); response.end(); return; }
  let decoded;
  try { decoded = decodeURIComponent(url.pathname); } catch { response.writeHead(400); response.end(); return; }
  let target = path.resolve(webRoot, '.' + decoded);
  if (target !== webRoot && !target.startsWith(webRoot + path.sep)) { response.writeHead(403); response.end(); return; }
  if (!path.extname(target) || target === webRoot) target = path.join(webRoot, 'index.html');
  if (!fs.existsSync(target) || !fs.statSync(target).isFile()) { response.writeHead(404); response.end('Archivo no encontrado. Compila con flutter build web.'); return; }
  response.writeHead(200, {'content-type': mime[path.extname(target)] || 'application/octet-stream',
    'cache-control': 'no-store', 'x-content-type-options': 'nosniff', 'referrer-policy': 'no-referrer'});
  if (request.method === 'HEAD') response.end(); else fs.createReadStream(target).pipe(response);
});
server.on('upgrade', (request, socket, head) => {
  if (!allowed(request) || !request.url.startsWith('/socket.io/')) { socket.end('HTTP/1.1 403 Forbidden\r\n\r\n'); return; }
  const forward = transport.request(new URL(request.url, upstream), {headers: headers(request)});
  forward.on('upgrade', (response, destination, upstreamHead) => {
    socket.write(`HTTP/1.1 ${response.statusCode} ${response.statusMessage}\r\n`);
    for (const [name, value] of Object.entries(response.headers)) {
      for (const item of Array.isArray(value) ? value : [value]) if (item !== undefined) socket.write(`${name}: ${item}\r\n`);
    }
    socket.write('\r\n');
    if (upstreamHead.length) socket.write(upstreamHead);
    if (head.length) destination.write(head);
    socket.pipe(destination).pipe(socket);
    socket.on('error', () => destination.destroy());
    destination.on('error', () => socket.destroy());
  });
  forward.on('response', response => { socket.end(`HTTP/1.1 ${response.statusCode} Backend rejected upgrade\r\nConnection: close\r\n\r\n`); response.resume(); });
  forward.on('error', () => socket.end('HTTP/1.1 502 Bad Gateway\r\nConnection: close\r\n\r\n'));
  forward.end();
});
server.listen(port, '127.0.0.1', () => console.log(`Alumnos: http://localhost:${port}\nBackend local: ${upstream.origin}\nSolo acceso local. Host y Origin se conservan.`));
