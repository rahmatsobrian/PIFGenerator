const { renderIndex } = require('./_lib');

// Melayani halaman utama dengan meta tag dinamis (di Vercel: rewrite "/" -> /api/index)
module.exports = (req, res) => {
  try {
    res.setHeader('Content-Type', 'text/html; charset=utf-8');
    res.setHeader('Cache-Control', 'public, s-maxage=3600, stale-while-revalidate=86400');
    res.status(200).end(renderIndex(req));
  } catch (e) {
    res.status(500).end('Server error');
  }
};
