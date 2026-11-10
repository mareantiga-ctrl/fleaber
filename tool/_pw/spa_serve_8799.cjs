const http = require('http');
const fs = require('fs');
const path = require('path');
const root = path.resolve(__dirname, '../../build/web');
const port = 8799;
http.createServer((req, res) => {
  const urlPath = decodeURIComponent((req.url || '/').split('?')[0]);
  const filePath = path.join(root, urlPath === '/' ? 'index.html' : urlPath);
  if (!filePath.startsWith(root)) { res.writeHead(403); return res.end(); }
  const types = { '.html':'text/html', '.js':'application/javascript', '.css':'text/css', '.png':'image/png', '.woff2':'font/woff2', '.ttf':'font/ttf', '.wasm':'application/wasm', '.json':'application/json', '.svg':'image/svg+xml' };
  fs.stat(filePath, (err, st) => {
    const p = (!err && st.isFile()) ? filePath : path.join(root, 'index.html');
    res.writeHead(200, { 'Content-Type': types[path.extname(p)] || 'application/octet-stream', 'Cache-Control': 'no-cache' });
    fs.createReadStream(p).pipe(res);
  });
}).listen(port, '127.0.0.1', () => console.log('listening', port, root));
