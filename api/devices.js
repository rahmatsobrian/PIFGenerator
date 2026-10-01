const { get, msg, getLang } = require('./_lib');

// Daftar resmi perangkat Android Beta (developer.android.com/about/versions/17/qpr2/download,
// diperbarui 24 Sep 2026). Dipakai sebagai cadangan dan untuk melengkapi hasil crawl.
// Urutan: terbaru dulu. Product = codename + "_beta".
const KNOWN = [
  ['Pixel 10a', 'stallion'],
  ['Pixel 10 Pro Fold', 'rango'],
  ['Pixel 10 Pro XL', 'mustang'],
  ['Pixel 10 Pro', 'blazer'],
  ['Pixel 10', 'frankel'],
  ['Pixel 9a', 'tegu'],
  ['Pixel 9 Pro Fold', 'comet'],
  ['Pixel 9 Pro XL', 'komodo'],
  ['Pixel 9 Pro', 'caiman'],
  ['Pixel 9', 'tokay'],
  ['Pixel 8a', 'akita'],
  ['Pixel 8 Pro', 'husky'],
  ['Pixel 8', 'shiba'],
  ['Pixel Fold', 'felix'],
  ['Pixel Tablet', 'tangorpro'],
  ['Pixel 7a', 'lynx'],
  ['Pixel 7 Pro', 'cheetah'],
  ['Pixel 7', 'panther'],
  ['Pixel 6a', 'bluejay'],
].map(([model, code]) => ({ model, product: code + '_beta' }));

// STEP 1: crawl daftar Pixel Beta dari developer.android.com
async function crawl(lang) {
  const home = await get('https://developer.android.com/about/versions', {}, lang);
  const urls = [...new Set(
    home.match(/https:\/\/developer\.android\.com\/about\/versions\/[^"'\s<>]*[0-9](?=")/g) || []
  )].sort().reverse();
  if (!urls.length) throw new Error(msg(lang, 'noVersion'));

  const page = await get(urls[0], {}, lang);
  const hrefs = [...page.matchAll(/href="([^"]*download[^"]*)"/g)].map((m) => m[1]);
  const path = hrefs.find((h) => h.includes('qpr')) || hrefs[0];
  if (!path) throw new Error(msg(lang, 'noDlLink'));
  const fiUrl = path.startsWith('http') ? path : 'https://developer.android.com' + path;

  const fi = await get(fiUrl, {}, lang);
  const rows = [...fi.matchAll(/<tr id="([^"]+)">\s*<td>([^<]*)<\/td>/g)];
  if (!rows.length) throw new Error(msg(lang, 'emptyList'));
  return { source: fiUrl, version: urls[0], list: rows.map((m) => ({ model: m[2], product: m[1] + '_beta' })) };
}

// Urutan tampil default: generasi terlama dulu (Pixel 6 di atas, Pixel 10 di bawah), lalu
// base, Pro, Pro XL, Pro Fold, a. Pixel Fold/Tablet ikut di grup Pixel 7. Tak dikenal di paling bawah.
function rank(model) {
  const m = model.match(/Pixel\s+(\d+)\s*(a)?\s*(Pro)?\s*(XL|Fold)?/i);
  if (m) {
    const r = m[2] ? 5 : m[3] ? (m[4] ? (/xl/i.test(m[4]) ? 2 : 3) : 1) : 0;
    return [+m[1], r];
  }
  if (/fold/i.test(model)) return [7, 6];
  if (/tablet/i.test(model)) return [7, 7];
  return [-1, 0];
}
function sortDevices(list) {
  return [...list].sort((a, b) => {
    const [ga, ra] = rank(a.model), [gb, rb] = rank(b.model);
    return ga - gb || ra - rb || a.model.localeCompare(b.model, undefined, { numeric: true });
  });
}

const handler = async (req, res) => {
  const lang = getLang(req);
  let found = [], source = null, warning = null;
  try {
    const c = await crawl(lang);
    found = c.list; source = c.source;
  } catch (e) {
    warning = msg(lang, 'crawlFail') + e.message;
  }
  // Gabung daftar resmi + hasil crawl, buang duplikat (per product dan per nama), lalu urutkan
  const crawled = new Map(found.map((d) => [d.product, d.model]));
  const all = [
    ...KNOWN.map((d) => ({ ...d, model: crawled.get(d.product) || d.model })),
    ...found,
  ];
  const seenP = new Set(), seenM = new Set();
  const devices = sortDevices(all.filter((d) => {
    const mk = d.model.trim().toLowerCase();
    if (seenP.has(d.product) || seenM.has(mk)) return false;
    seenP.add(d.product); seenM.add(mk);
    return true;
  }));
  res.setHeader('Cache-Control', warning ? 'no-store' : 's-maxage=600, stale-while-revalidate=3600');
  res.status(200).json({ source, warning, devices });
};

module.exports = handler;
module.exports.sortDevices = sortDevices;
