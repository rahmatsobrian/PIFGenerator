const { get, msg, getLang } = require('./_lib');

// STEP 3-4: Flash Station (build canary) + Pixel Bulletin (security patch)
module.exports = async (req, res) => {
  const lang = getLang(req);
  try {
    let product = String(req.query.product || '').trim();
    if (!/^[a-z0-9_]+$/i.test(product)) throw new Error(msg(lang, 'badProduct'));
    if (!product.endsWith('_beta')) product += '_beta';
    const device = product.replace(/_beta$/, '');
    const model = String(req.query.model || device);

    // Flash key dari atribut data-client-config
    const flash = await get('https://flash.android.com', {}, lang);
    const cfg = (flash.match(/<body data-client-config=[^\n]*/) || [''])[0];
    const key = (cfg.split(';')[1] || '').split('&')[0];
    if (!key) throw new Error(msg(lang, 'noFlashKey'));

    const json = await get(
      `https://content-flashstation-pa.googleapis.com/v1/builds?product=${product}&key=${key}`,
      { Referer: 'https://flash.android.com' },
      lang
    );

    // Ambil blok canary terakhir (13 baris sebelum "canary": true)
    const lines = json.split('\n');
    let idx = -1;
    for (let i = lines.length - 1; i >= 0; i--) {
      if (lines[i].includes('"canary": true')) { idx = i; break; }
    }
    if (idx < 0) throw new Error(msg(lang, 'noCanary'));
    const block = lines.slice(Math.max(0, idx - 13), idx + 1);
    const field = (name) => {
      const l = block.find((x) => x.includes(name));
      return l ? l.split('"')[3] : '';
    };
    const id = field('releaseCandidateName');
    const incremental = field('buildId');
    if (!id || !incremental) throw new Error(msg(lang, 'badBuild'));

    // Security patch dari bulletin, fallback estimasi dari ID
    const idLine = block.find((x) => x.includes('"id"')) || '';
    const cm = idLine.match(/canary-([^"]*)"/);
    const canaryId = cm ? cm[1].replace(/^(.{4})/, '$1-') : '';
    let patch = '';
    let estimated = false;
    try {
      if (canaryId) {
        const bulletin = await get('https://source.android.com/docs/security/bulletin/pixel', {}, lang);
        const row = bulletin.split('\n').find((l) => l.includes('<td>' + canaryId));
        if (row) {
          const tds = [...row.matchAll(/<td>(.*?)<\/td>/g)];
          patch = tds.length ? tds[tds.length - 1][1] : '';
        }
      }
    } catch (_) { /* lanjut ke estimasi */ }

    if (!patch) {
      estimated = true;
      const d = (id.match(/\.(\d{6})/) || [])[1];
      patch = d ? `20${d.slice(0, 2)}-${d.slice(2, 4)}-${d.slice(4, 6)}` : `${canaryId}-05`;
    }

    res.setHeader('Cache-Control', 's-maxage=300, stale-while-revalidate=900');
    res.status(200).json({
      model, product, device, id, incremental,
      securityPatch: patch,
      estimated,
      fingerprint: `google/${product}/${device}:CANARY/${id}/${incremental}:user/release-keys`,
    });
  } catch (e) {
    res.status(502).json({ error: e.message });
  }
};
