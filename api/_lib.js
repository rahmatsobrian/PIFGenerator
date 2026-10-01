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

module.exports = { get, msg, getLang };
