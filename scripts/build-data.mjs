// Builds TorahReadings/Resources/readings.json:
//   every diaspora Shabbat from FIRST_YEAR to LAST_YEAR, with its triennial
//   aliyot (from @hebcal/triennial) and the matching Adas Israel videos.
// Also writes scripts/report.md listing anything that didn't line up.
//
//   node build-data.mjs                 # fetch the five Adas Israel pages
//   node build-data.mjs --html-dir dir  # use saved pages (Genesis.html, …)

import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { HebrewCalendar, HDate } from '@hebcal/core';
import { getTriennialForParshaHaShavua, Triennial } from '@hebcal/triennial';
import { getLeyningForParshaHaShavua } from '@hebcal/leyning';
import { BOOK_PAGES, parseBookPage } from './parse-videos.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const OUT = join(here, '..', 'TorahReadings', 'Resources', 'readings.json');
const VIDEOS_OUT = join(here, '..', 'TorahReadings', 'Resources', 'videos.json');
const REPORT = join(here, 'report.md');

const thisYear = new HDate().getFullYear();
const FIRST_YEAR = Triennial.getCycleStartYear(thisYear); // start of current cycle
const LAST_YEAR = FIRST_YEAR + 11;                          // four full cycles

const BOOKS = ['Genesis', 'Exodus', 'Leviticus', 'Numbers', 'Deuteronomy'];

// ---------- verse helpers (lexicographic chapter:verse, no verse counts needed)
const cv = (s) => s.split(':').map(Number);
const cmp = (a, b) => (a[0] - b[0]) || (a[1] - b[1]);
const overlaps = (a, b) => cmp(a.b, b.e) <= 0 && cmp(b.b, a.e) <= 0;
const covers = (outer, inner) => cmp(outer.b, inner.b) <= 0 && cmp(outer.e, inner.e) >= 0;

// ---------- 1. videos
const htmlDir = process.argv.includes('--html-dir')
  ? process.argv[process.argv.indexOf('--html-dir') + 1] : null;

async function loadPage(book, url) {
  if (htmlDir) return readFile(join(htmlDir, `${book}.html`), 'utf8');
  for (let attempt = 1; ; attempt++) {
    try {
      const res = await fetch(url, { headers: {
        'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15',
        Accept: 'text/html,application/xhtml+xml',
        'Accept-Language': 'en-US,en;q=0.9',
      } });
      if (!res.ok) throw new Error(`HTTP ${res.status} ${res.statusText} (server: ${res.headers.get('server') ?? '?'})`);
      return await res.text();
    } catch (err) {
      if (attempt >= 5) throw new Error(`${url}: ${err.message}`);
      await new Promise((r) => setTimeout(r, 15000 * attempt));
    }
  }
}

const issues = [];

// Typos on the Adas Israel pages whose intended verses are clear from context.
// Keyed by "Book|Parsha|label"; each fix is noted in the report.
const CORRECTIONS = {
  "Genesis|Miketz|Aliyah 5: 41:25 - 40:38": { b: '41:25', e: '41:38' },
  'Genesis|Vayeshev|Maftir: 7:18 – 7:23': { b: '40:18', e: '40:23' },
  'Exodus|Bo|Maftir: 3:14 – 3:16': { b: '13:14', e: '13:16' },
  // Shabbat Rosh Chodesh maftir, filed under Mishpatim with the book left off.
  'Exodus|Mishpatim|Maftir: 28:9 - 28:15': { book: 'Numbers', b: '28:9', e: '28:15' },
};
const videosByBook = Object.fromEntries(BOOKS.map((b) => [b, []]));
const playlists = {};
// The Adas Israel site sometimes refuses automated requests (HTTP 406). If any
// page can't be fetched, keep the video list from the last successful run.
let pages;
try {
  pages = [];
  for (const [book, url] of Object.entries(BOOK_PAGES)) pages.push([book, url, await loadPage(book, url)]);
} catch (err) {
  const previous = JSON.parse(await readFile(VIDEOS_OUT, 'utf8').catch(() => 'null'));
  if (!previous) throw err;
  console.warn(`Couldn't fetch the Adas Israel pages (${err.message}); reusing videos.json from ${previous.generated}.`);
  issues.push(`**Pages not fetched this run** (${err.message}) — kept the video list from ${previous.generated}.`);
  Object.assign(playlists, previous.playlists);
  for (const v of previous.videos) videosByBook[v.book].push({ ...v, b: cv(v.b), e: cv(v.e), chazak: !!v.chazak });
  pages = [];
}
for (const [book, url, html] of pages) {
  const parshiyot = parseBookPage(book, html);
  if (parshiyot.length === 0) throw new Error(`No parsha tables found on ${url} — page layout changed?`);
  for (const p of parshiyot) {
    playlists[p.parsha] = p.playlist;
    // The parsha's span, from its aliyah videos, to catch mistyped maftir chapters.
    const spans = p.videos.filter((v) => v.id && v.range && v.aliyah !== 'M')
      .map((v) => ({ b: cv(v.range.b), e: cv(v.range.e) })).filter((r) => cmp(r.b, r.e) <= 0);
    const lo = spans.reduce((m, r) => (!m || cmp(r.b, m) < 0 ? r.b : m), null);
    const hi = spans.reduce((m, r) => (!m || cmp(r.e, m) > 0 ? r.e : m), null);
    for (const v of p.videos) {
      const fix = CORRECTIONS[`${book}|${p.parsha}|${v.label}`];
      if (fix && v.id) {
        const fixedBook = fix.book || book;
        videosByBook[fixedBook].push({ b: cv(fix.b), e: cv(fix.e), id: v.id, chazak: v.chazak,
          label: `${p.parsha} · ${v.column} · ${v.label.replace(/[\d:.\s–-]+$/, '')} ${fixedBook === book ? '' : fixedBook + ' '}${fix.b}–${fix.e}`, parsha: p.parsha });
        issues.push(`**Corrected** — ${book}, ${p.parsha}, ${v.column}: “${v.label}” read as ${fixedBook} ${fix.b}–${fix.e}`);
        continue;
      }
      if (!v.id) { issues.push(`**Broken link** — ${book}, ${p.parsha}, ${v.column}: “${v.label}” links to \`${v.href}\``); continue; }
      if (!v.range) { issues.push(`**No verse range** — ${book}, ${p.parsha}, ${v.column}: “${v.label}”`); continue; }
      const r = { b: cv(v.range.b), e: cv(v.range.e) };
      if (cmp(r.b, r.e) > 0) {
        issues.push(`**Backwards range** — ${book}, ${p.parsha}, ${v.column}: “${v.label}” (skipped)`);
        continue;
      }
      if (v.aliyah === 'M' && lo && (cmp(r.b, lo) < 0 || cmp(r.e, hi) > 0)) {
        issues.push(`**Maftir outside the parsha** — ${book}, ${p.parsha}: “${v.label}” (the parsha's aliyot run ${lo.join(':')}–${hi.join(':')}; skipped)`);
        continue;
      }
      videosByBook[book].push({ ...r, id: v.id, chazak: v.chazak, label: `${p.parsha} · ${v.column} · ${v.label}`, parsha: p.parsha });
    }
  }
}

// ---------- 2. choose videos for an aliyah
function videosFor(book, b, e) {
  const want = { b: cv(b), e: cv(e) };
  const pool = (videosByBook[book] || []).filter((v) => overlaps(v, want));
  // Collapse duplicate ranges; keep the plain version first and chazak as an alternate.
  const byRange = new Map();
  for (const v of pool) {
    const key = `${v.b}-${v.e}`;
    const g = byRange.get(key) || { b: v.b, e: v.e, main: null, chazak: null, extra: [] };
    if (v.chazak) g.chazak ??= v; else if (!g.main) g.main = v; else g.extra.push(v);
    byRange.set(key, g);
  }
  const groups = [...byRange.values()].map((g) => ({ ...g, main: g.main || g.chazak }));
  const exact = groups.find((g) => cmp(g.b, want.b) === 0 && cmp(g.e, want.e) === 0);
  let chosen;
  if (exact) chosen = [exact];
  else {
    // Prefer one video that covers the whole aliyah, the tightest one.
    const whole = groups.filter((g) => covers(g, want))
      .sort((x, y) => (cmp(y.b, x.b)) || cmp(x.e, y.e));
    if (whole.length) chosen = [whole[0]];
    else {
      // Otherwise walk forward, adding videos that extend coverage.
      groups.sort((x, y) => cmp(x.b, y.b) || cmp(y.e, x.e));
      chosen = [];
      let end = null;
      for (const g of groups) if (!end || cmp(g.e, end) > 0) { chosen.push(g); end = g.e; }
    }
  }
  const fmt = (p) => `${p[0]}:${p[1]}`;
  const vids = chosen.map((g) => ({
    id: g.main.id,
    b: fmt(g.b), e: fmt(g.e),
    label: g.main.label,
    exact: cmp(g.b, want.b) === 0 && cmp(g.e, want.e) === 0,
    ...(g.chazak && g.chazak.id !== g.main.id ? { chazakId: g.chazak.id } : {}),
  }));
  const coveredStart = chosen.length > 0 && cmp(chosen[0].b, want.b) <= 0;
  const coveredEnd = chosen.length > 0 && cmp(chosen.reduce((m, g) => (cmp(g.e, m) > 0 ? g.e : m), chosen[0].e), want.e) >= 0;
  return { vids, complete: coveredStart && coveredEnd };
}

// ---------- 3. readings for every Shabbat
const shabbatot = [];
let exactCount = 0, totalAliyot = 0;
const gaps = new Map();
for (let y = FIRST_YEAR; y <= LAST_YEAR; y++) {
  const events = HebrewCalendar.calendar({ year: y, isHebrewYear: true, sedrot: true, noHolidays: true, il: false });
  for (const ev of events) {
    const tri = getTriennialForParshaHaShavua(ev, false);
    if (!tri?.aliyot) { issues.push(`**No triennial aliyot** — ${ev.getDesc()} ${ev.getDate().greg().toISOString().slice(0, 10)}`); continue; }
    const name = ev.parsha.join('-');
    const aliyot = [];
    for (const n of ['1', '2', '3', '4', '5', '6', '7', 'M']) {
      const a = tri.aliyot[n];
      if (!a) continue;
      const { vids, complete } = videosFor(a.k, a.b, a.e);
      if (!complete) {
        const key = `${name} ${n} ${a.k} ${a.b}–${a.e}`;
        gaps.set(key, (gaps.get(key) || 0) + 1);
      }
      aliyot.push({
        n, book: a.k, b: a.b, e: a.e, verses: a.v,
        ...(a.reason ? { reason: a.reason } : {}),
      });
      if (vids.length === 1 && vids[0].exact) exactCount++;
      totalAliyot++;
    }
    // Full-parsha (annual) aliyot, for readers who read the whole parsha.
    const full = [];
    const fk = getLeyningForParshaHaShavua(ev, false)?.fullkriyah;
    for (const n of ['1', '2', '3', '4', '5', '6', '7', 'M']) {
      const a = fk?.[n];
      if (!a?.k || !a.b || !a.e) continue;
      full.push({ n, book: a.k, b: a.b, e: a.e, verses: a.v, ...(a.reason ? { reason: a.reason } : {}) });
    }
    if (!full.length) issues.push(`**No full-parsha aliyot** — ${ev.getDesc()} ${ev.getDate().greg().toISOString().slice(0, 10)}`);
    const d = ev.getDate();
    shabbatot.push({
      date: d.greg().toISOString().slice(0, 10),
      hdate: d.render('en'),
      hyear: d.getFullYear(),
      parsha: name,
      parshaHe: ev.render('he').replace(/^פָּרָשַׁת\s*|^פרשת\s*/, ''),
      cycleYear: (tri.yearNum ?? 0) + 1,
      variation: tri.variation,
      playlist: playlistFor(ev.parsha),
      aliyot,
      full,
    });
  }
}

function playlistFor(names) {
  // Adas Israel spells parshiyot differently than Hebcal; compare loosely.
  const norm = (s) => s.toLowerCase().replace(/^b'/, 'be').replace(/[^a-z]/g, '').replace(/ch/g, 'kh').replace(/[aeiouy]/g, '').replace(/(.)\1+/g, '$1');
  const want = norm(names.join(''));
  const first = norm(names[0]);
  let best = null;
  for (const [title, url] of Object.entries(playlists)) {
    const t = norm(title);
    if (t === want) return url;
    if (!best && t.includes(first)) best = url;
  }
  return best;
}

// ---------- 4. write
await mkdir(dirname(OUT), { recursive: true });
await writeFile(OUT, JSON.stringify({
  generated: new Date().toISOString().slice(0, 10),
  firstYear: FIRST_YEAR, lastYear: LAST_YEAR,
  sources: {
    readings: 'Hebcal triennial (@hebcal/triennial) and full kriyah (@hebcal/leyning), diaspora, CC BY 4.0 — hebcal.com',
    videos: 'Tricks of the Trope – Total Torah, Cantor Arianne Brown, Adas Israel Congregation — adasisrael.org/trope',
  },
  shabbatot,
}));

// The app matches videos to verses itself (so it can handle any range, such as a
// special maftir from the sign-up sheet); it gets the raw video list.
const fmtCV = (p) => `${p[0]}:${p[1]}`;
await writeFile(VIDEOS_OUT, JSON.stringify({
  generated: new Date().toISOString().slice(0, 10),
  playlists,
  videos: Object.entries(videosByBook).flatMap(([book, list]) => list.map((v) => ({
    book, b: fmtCV(v.b), e: fmtCV(v.e), id: v.id, label: v.label, parsha: v.parsha, ...(v.chazak ? { chazak: true } : {}),
  }))),
}));

const report = [
  `# Data report (${new Date().toISOString().slice(0, 10)})`,
  '',
  `Hebrew years ${FIRST_YEAR}–${LAST_YEAR}: ${shabbatot.length} Shabbatot, ${totalAliyot} aliyot.`,
  `Videos parsed: ${Object.values(videosByBook).reduce((n, v) => n + v.length, 0)}.`,
  `Aliyot matched to a single video with the exact same verses: ${exactCount} (${Math.round(100 * exactCount / totalAliyot)}%).`,
  'The rest use one or more videos that cover the aliyah but start or end at different verses (for example when a double parsha is read separately, or a special maftir).',
  '',
  '## Problems on the Adas Israel pages',
  '',
  ...(issues.length ? issues.map((i) => `- ${i}`) : ['None.']),
  '',
  '## Aliyot no video fully covers',
  '',
  ...(gaps.size ? [...gaps].map(([k, n]) => `- ${k} (${n}×)`) : ['None.']),
  '',
].join('\n');
await writeFile(REPORT, report);
console.log(report);
