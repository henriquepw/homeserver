// FileFlows -> nó "Function" (JavaScript)
// Detecta o idioma original via TMDB e seta Variables.OriginalLanguage
// Output 1 = sucesso ; Output 2 = falhou (nao seta a variavel, erro no log)

let apiKey = Variables['TMDB_API_KEY'];
let fileName = Variables['file.NameNoExtension'] || '';
let folderName = Variables['folder.Name'] || '';

if (!apiKey) {
  Logger.ELog('TMDB_API_KEY nao definida nas Variables do flow');
  return 2;
}

// --- ano: primeiro 19xx/20xx no nome, senao na pasta ---
let year = '';
let ym = fileName.match(/(19|20)\d\d/);
if (ym) year = ym[0];
else {
  let fm = folderName.match(/(19|20)\d\d/);
  if (fm) year = fm[0];
}

// --- titulo: troca . _ por espaco, remove (...) [...] e marcadores de episodio, ---
// --- depois corta no ano ou tag de release ---
let raw = fileName.replace(/[._]/g, ' ')
  .replace(/\([^)]*\)/g, '')
  .replace(/\[[^\]]*\]/g, '')
  // episodio (anime/serie): "S01E09", "Ep 09", "E09", " - 09", "- 09v2"
  .replace(/\bS\d{1,2}\s*E\d{1,3}.*$/i, '')
  .replace(/\s[-–—]\s*\d{1,4}(v\d+)?\s*$/i, '')
  .replace(/\s(?:ep?|episode)\s*\.?\s*\d{1,4}\s*$/i, '');
let tags = /^(2160p|1080p|720p|480p|x264|x265|h264|h265|hevc|bluray|blu-ray|webrip|web-dl|webdl|hdtv|bdrip|dvdrip|remux|aac|ac3|dts|hdr|10bit|xvid|proper|repack)$/i;
let out = [];
for (let w of raw.split(/\s+/)) {
  if (/^(19|20)\d\d$/.test(w)) break;
  if (tags.test(w)) break;
  if (w) out.push(w);
}
let title = out.join(' ').trim();
if (!title) {
  Logger.ELog('nao consegui extrair titulo de: ' + fileName);
  return 2;
}

// --- busca no TMDB ---
let url = 'https://api.themoviedb.org/3/search/multi?api_key=' +
  encodeURIComponent(apiKey) + '&query=' + encodeURIComponent(title);
Logger.ILog('TMDB query: ' + title + (year ? ' (' + year + ')' : ''));

let response = http.GetAsync(url).Result;
if (!response.IsSuccessStatusCode) {
  Logger.ELog('TMDB falhou: ' + response.StatusCode);
  return 2;
}
let data = JSON.parse(response.Content.ReadAsStringAsync().Result);

let results = (data.results || []).filter(r => r.media_type === 'movie' || r.media_type === 'tv');
if (results.length === 0) {
  Logger.ELog('TMDB nao encontrou nada para: ' + title + (year ? ' (' + year + ')' : ''));
  return 2;
}

let pick = null;
if (year) pick = results.find(r => (r.release_date || r.first_air_date || '').indexOf(year) === 0);
if (!pick) pick = results[0];

let lang2 = pick.original_language;
if (!lang2) {
  Logger.ELog('TMDB nao retornou original_language para tmdb:' + pick.id);
  return 2;
}

// --- ISO 639-1 (2 letras do TMDB) -> ISO 639-2/T (3 letras dos metadados) ---
let map = { aa: 'aar', ab: 'abk', ae: 'ave', af: 'afr', ak: 'aka', am: 'amh', an: 'arg', ar: 'ara', as: 'asm', av: 'ava', ay: 'aym', az: 'aze', ba: 'bak', be: 'bel', bg: 'bul', bi: 'bis', bm: 'bam', bn: 'ben', bo: 'bod', br: 'bre', bs: 'bos', ca: 'cat', ce: 'che', ch: 'cha', cn: 'zho', co: 'cos', cr: 'cre', cs: 'ces', cu: 'chu', cv: 'chv', cy: 'cym', da: 'dan', de: 'deu', dv: 'div', dz: 'dzo', ee: 'ewe', el: 'ell', en: 'eng', eo: 'epo', es: 'spa', et: 'est', eu: 'eus', fa: 'fas', ff: 'ful', fi: 'fin', fj: 'fij', fo: 'fao', fr: 'fra', fy: 'fry', ga: 'gle', gd: 'gla', gl: 'glg', gn: 'grn', gu: 'guj', gv: 'glv', ha: 'hau', he: 'heb', hi: 'hin', ho: 'hmo', hr: 'hrv', ht: 'hat', hu: 'hun', hy: 'hye', hz: 'her', ia: 'ina', id: 'ind', ie: 'ile', ig: 'ibo', ii: 'iii', ik: 'ipk', io: 'ido', is: 'isl', it: 'ita', iu: 'iku', ja: 'jpn', jv: 'jav', ka: 'kat', kg: 'kon', ki: 'kik', kj: 'kua', kk: 'kaz', kl: 'kal', km: 'khm', kn: 'kan', ko: 'kor', kr: 'kau', ks: 'kas', ku: 'kur', kv: 'kom', kw: 'cor', ky: 'kir', la: 'lat', lb: 'ltz', lg: 'lug', li: 'lim', ln: 'lin', lo: 'lao', lt: 'lit', lu: 'lub', lv: 'lav', mg: 'mlg', mh: 'mah', mi: 'mri', mk: 'mkd', ml: 'mal', mn: 'mon', mr: 'mar', ms: 'msa', mt: 'mlt', my: 'mya', na: 'nau', nb: 'nob', nd: 'nde', ne: 'nep', ng: 'ndo', nl: 'nld', nn: 'nno', no: 'nor', nr: 'nbl', nv: 'nav', ny: 'nya', oc: 'oci', oj: 'oji', om: 'orm', or: 'ori', os: 'oss', pa: 'pan', pi: 'pli', pl: 'pol', ps: 'pus', pt: 'por', qu: 'que', rm: 'roh', rn: 'run', ro: 'ron', ru: 'rus', rw: 'kin', sa: 'san', sc: 'srd', sd: 'snd', se: 'sme', sg: 'sag', si: 'sin', sk: 'slk', sl: 'slv', sm: 'smo', sn: 'sna', so: 'som', sq: 'sqi', sr: 'srp', ss: 'ssw', st: 'sot', su: 'sun', sv: 'swe', sw: 'swa', ta: 'tam', te: 'tel', tg: 'tgk', th: 'tha', ti: 'tir', tk: 'tuk', tl: 'tgl', tn: 'tsn', to: 'ton', tr: 'tur', ts: 'tso', tt: 'tat', tw: 'twi', ty: 'tah', ug: 'uig', uk: 'ukr', ur: 'urd', uz: 'uzb', ve: 'ven', vi: 'vie', vo: 'vol', wa: 'wln', wo: 'wol', xh: 'xho', xx: 'und', yi: 'yid', yo: 'yor', za: 'zha', zh: 'zho', zu: 'zul' };
let lang3 = map[lang2];
if (!lang3) { Logger.WLog("sem mapeamento 639-2 para '" + lang2 + "', usando o codigo 639-1"); lang3 = lang2; }

Variables.OriginalLanguage = lang3;
Logger.ILog('OriginalLanguage=' + lang3 + '  (' + (pick.title || pick.name) + ', tmdb:' + pick.id + ')');
return 1;
