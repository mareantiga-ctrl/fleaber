const http = require('http');
const fs = require('fs');
const path = require('path');
const { fileURLToPath } = require('url');
const root = path.resolve(__dirname, '../../build/web');
const port = 8798;
console.log('Serving', root);
if (!fs.existsSync(path.join(root, 'index.html'))) {
  console.error('MISSING index.html in', root);
  process.exit(1);
}
const types = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'application/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.svg': 'image/svg+xml',
  '.woff2': 'font/woff2',
  '.ttf': 'font/ttf',
  '.wasm': 'application/wasm',
};
http.createServer((req, res) => {
  const urlPath = decodeURIComponent((req.url || '/').split('?')[0]);
  let filePath = path.join(root, urlPath === '/' ? 'index.html' : urlPath);
  if (!filePath.startsWith(root)) { res.writeHead(403); return res.end(); }
  const serve = (p, code = 200) => {
    const ext = path.extname(p).toLowerCase();
    res.writeHead(code, { 'Content-Type': types[ext] || 'application/octet-stream', 'Cache-Control': 'no-cache' });
    fs.createReadStream(p).pipe(res);
  };
  fs.stat(filePath, (err, st) => {
    if (!err && st.isFile()) return serve(filePath);
    serve(path.join(root, 'index.html'));
  });
}).listen(port, '127.0.0.1', () => console.log(`listening http://127.0.0.1:${port}`));
