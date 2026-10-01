// Pesan error dua bahasa (en = default, id). Bahasa dipilih lewat query ?lang=en|id
const M = {
  en: {
    dlFail: (u, s) => `Download failed: ${u} (${s})`,
    slow: (h) => `Connection to ${h} is too slow (timeout). Try again.`,
    noVersion: 'Could not parse the latest version URL',
    noDlLink: 'Could not find the download page link',
    emptyList: 'Device list is empty',
    crawlFail: 'Crawl failed, using the built-in list: ',
    badProduct: 'Invalid product parameter',
    noFlashKey: 'Flash key not found',
    noCanary: 'Canary build not found',
    badBuild: 'Failed to read ID/Incremental from the canary build',
  },
  id: {
    dlFail: (u, s) => `Gagal download: ${u} (${s})`,
    slow: (h) => `Koneksi ke ${h} terlalu lambat (timeout). Coba lagi.`,
    noVersion: 'Tidak bisa parse URL versi terbaru',
    noDlLink: 'Tidak bisa menemukan link halaman download',
    emptyList: 'Daftar device kosong',
    crawlFail: 'Crawl gagal, memakai daftar bawaan: ',
    badProduct: 'Parameter product tidak valid',
    noFlashKey: 'Flash key tidak ditemukan',
    noCanary: 'Build canary tidak ditemukan',
    badBuild: 'Gagal membaca ID/Incremental dari build canary',
  },
};
const getLang = (req) => (req && req.query && req.query.lang === 'id' ? 'id' : 'en');
const msg = (lang, key, ...a) => {
  const v = (M[lang] || M.en)[key];
  return typeof v === 'function' ? v(...a) : v;
};

// Helper fetch: pengganti fungsi download() di pifgenerator.sh
// Timeout 20 detik per percobaan, otomatis coba ulang 1x (koneksi HP/Termux sering lambat).
async function get(url, headers = {}, lang = 'en') {
  let last;
  for (let i = 0; i < 2; i++) {
    try {
      const r = await fetch(url, {
        headers: { 'User-Agent': 'Mozilla/5.0', ...headers },
        redirect: 'follow',
        signal: AbortSignal.timeout(20000),
      });
      if (!r.ok) throw new Error(msg(lang, 'dlFail', url, r.status));
      return await r.text();
    } catch (e) {
      last = e.name === 'TimeoutError' || e.name === 'AbortError'
        ? new Error(msg(lang, 'slow', new URL(url).host))
        : e;
    }
  }
  throw last;
}

// Render views/index.html dengan meta tag (Open Graph / Twitter) berisi URL absolut
// sesuai domain yang dipakai, supaya preview link di Telegram dkk selalu benar.
const fs = require('fs');
const path = require('path');
const META = {
  en: {
    lang: 'en', locale: 'en_US',
    title: 'PIF Generator: Play Integrity Fix for Pixel Canary',
    desc: 'Generate Play Integrity Fix (pif.prop / pif.json) from the latest Pixel Canary build. Fast, free, right in your browser.',
  },
  id: {
    lang: 'id', locale: 'id_ID',
    title: 'PIF Generator: Play Integrity Fix untuk Pixel Canary',
    desc: 'Buat Play Integrity Fix (pif.prop / pif.json) dari build Pixel Canary terbaru dengan mudah, langsung dari browser.',
  },
};
const esc = (x) => String(x).replace(/&/g, '&amp;').replace(/"/g, '&quot;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
let tpl;
function renderIndex(req) {
  tpl = tpl || fs.readFileSync(path.join(__dirname, '..', 'views', 'index.html'), 'utf8');
  const h = req.headers || {};
  let host = String(h['x-forwarded-host'] || h.host || 'localhost').split(',')[0].trim();
  if (!/^[a-z0-9.\-:]+$/i.test(host)) host = 'localhost';
  const local = /^(localhost|127\.|192\.168\.|10\.)/.test(host);
  const proto = String(h['x-forwarded-proto'] || (local ? 'http' : 'https')).split(',')[0].trim();
  const origin = `${proto === 'http' ? 'http' : 'https'}://${host}`;
  const lang = getLang(req);
  const m = META[lang];
  const vars = { LANG: m.lang, LOCALE: m.locale, TITLE: m.title, DESC: m.desc, ORIGIN: origin, URL: origin + (lang === 'id' ? '/?lang=id' : '/') };
  return tpl.replace(/\{\{(\w+)\}\}/g, (_, k) => esc(vars[k] ?? ''));
}

module.exports = { get, msg, getLang, renderIndex };
