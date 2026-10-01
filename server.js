// Server lokal sederhana (tanpa dependency) untuk Termux / tes lokal.
// Di Vercel file ini tidak dipakai; Vercel otomatis memakai folder api/ dan public/.
const http = require('http');
const fs = require('fs');
const path = require('path');
const { URL } = require('url');

const PORT = process.env.PORT || 3000;
const PUB = path.join(__dirname, 'public');
const TYPES = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript', '.css': 'text/css', '.json': 'application/json', '.svg': 'image/svg+xml', '.ico': 'image/x-icon' };

http.createServer(async (req, res) => {
  const u = new URL(req.url, 'http://localhost');
  if (u.pathname.startsWith('/api/')) {
    const name = u.pathname.slice(5).replace(/[^a-z0-9_-]/gi, '');
    const file = path.join(__dirname, 'api', name + '.js');
    if (name.startsWith('_') || !fs.existsSync(file)) { res.statusCode = 404; return res.end('{"error":"Not found"}'); }
    req.query = Object.fromEntries(u.searchParams);
    res.status = (c) => { res.statusCode = c; return res; };
    res.json = (o) => { res.setHeader('Content-Type', 'application/json'); res.end(JSON.stringify(o)); };
    return require(file)(req, res);
  }
  let p = path.join(PUB, u.pathname === '/' ? 'index.html' : u.pathname);
  if (!p.startsWith(PUB) || !fs.existsSync(p) || fs.statSync(p).isDirectory()) { res.statusCode = 404; return res.end('Not found'); }
  res.setHeader('Content-Type', TYPES[path.extname(p)] || 'application/octet-stream');
  fs.createReadStream(p).pipe(res);
}).listen(PORT, () => console.log(`PIF Generator jalan di http://localhost:${PORT}`));
