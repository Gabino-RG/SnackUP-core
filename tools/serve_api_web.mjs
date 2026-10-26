// Local development proxy: one origin for Flutter, API, cookies and Socket.IO.
import http from 'node:http';
import https from 'node:https';
import fs from 'node:fs';
import path from 'node:path';
const opts = Object.fromEntries(process.argv.slice(2).map(s => { const i=s.indexOf('='); return [s.slice(2,i),s.slice(i+1)]; }));
const backend = new URL(opts.backend || 'http://127.0.0.1:8000');
const port = Number(opts.port || 8080);
const root = path.resolve(opts.root || 'build/web');
if (!fs.existsSync(path.join(root,'index.html'))) throw new Error('Primero genera build/web con flutter build web --pwa-strategy=none.');
if (!['http:','https:'].includes(backend.protocol) || backend.username || backend.password) throw new Error('URL de backend inválida.');
const transport = backend.protocol === 'https:' ? https : http;
const apiPath = url => ['/api/','/media/','/socket.io/','/health/'].some(prefix => url.startsWith(prefix));
const headers = req => ({...req.headers});
const fail = res => { if (!res.headersSent) { res.writeHead(502,{'content-type':'application/json','cache-control':'no-store'}); res.end(JSON.stringify({error:{code:'API_UNAVAILABLE',message:'El backend no está disponible.'}})); } else res.destroy(); };
const mime = {'.html':'text/html; charset=utf-8','.js':'application/javascript','.json':'application/json','.wasm':'application/wasm','.css':'text/css','.png':'image/png','.svg':'image/svg+xml','.woff2':'font/woff2','.ttf':'font/ttf','.otf':'font/otf'};
const server = http.createServer((req,res) => {
  if (apiPath(req.url)) {
    const upstream = transport.request(new URL(req.url,backend),{method:req.method,headers:headers(req)}, r => {
      res.writeHead(r.statusCode,{...r.headers,'cache-control':'no-store'}); r.pipe(res);
    });
    upstream.on('error',()=>fail(res)); req.on('aborted',()=>upstream.destroy()); req.pipe(upstream); return;
  }
  if (!['GET','HEAD'].includes(req.method)) { res.writeHead(405); res.end(); return; }
  let filename;
  try { filename=path.resolve(root,'.'+decodeURIComponent(new URL(req.url,'http://localhost').pathname)); } catch { res.writeHead(400);res.end();return; }
  if (filename !== root && !filename.startsWith(root+path.sep)) {res.writeHead(403);res.end();return;}
  if (!fs.existsSync(filename) || fs.statSync(filename).isDirectory()) filename=path.join(root,'index.html');
  res.writeHead(200,{'content-type':mime[path.extname(filename)] || 'application/octet-stream','cache-control':'no-store'});
  if (req.method === 'HEAD') res.end(); else fs.createReadStream(filename).pipe(res);
});
server.on('upgrade',(req,socket,head) => {
  if (!req.url.startsWith('/socket.io/')) {socket.destroy();return;}
  const upstream = transport.request(new URL(req.url,backend),{headers:headers(req)});
  upstream.on('upgrade',(reply,peer,rest) => {
    socket.write(`HTTP/1.1 ${reply.statusCode} ${reply.statusMessage}\r\n`+Object.entries(reply.headers).map(([k,v])=>`${k}: ${v}`).join('\r\n')+'\r\n\r\n');
    if (rest.length) socket.write(rest); if (head.length) peer.write(head);
    socket.on('error',()=>peer.destroy()); peer.on('error',()=>socket.destroy()); socket.pipe(peer).pipe(socket);
  });
  upstream.on('error',()=>socket.destroy()); upstream.on('response',()=>socket.destroy()); upstream.end();
});
server.listen(port,'127.0.0.1',()=>console.log(`SnackUP: http://localhost:${port} · backend: ${backend.origin}. Configura SNACKUP_PUBLIC_ORIGIN=http://localhost:${port}`));
