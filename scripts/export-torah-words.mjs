// Writes scripts/torah-words.json: every Torah verse from Sefaria's
// "Miqra according to the Masorah", as the words written in a scroll
// (ketiv spellings, maqaf-joined words split, no vowels or te'amim), with
// open (P) and closed (S) paragraph breaks. Used to build the Tikkun layout.
import { writeFile } from 'node:fs/promises';

const BOOKS = ['Genesis', 'Exodus', 'Leviticus', 'Numbers', 'Deuteronomy'];
const kq = /<span class="mam-kq">(.*?)<\/span><\/span>/g;
const strip = (s) => [...s].map((c) => {
  const u = c.codePointAt(0);
  if (u === 0x05BE) return ' ';
  if ((u >= 0x0591 && u <= 0x05C7) || u === 0x034F || (u >= 0x200B && u <= 0x200F)) return '';
  return c;
}).join('');

const out = {};
for (const book of BOOKS) {
  const url = `https://www.sefaria.org/api/v3/texts/${book}?version=${encodeURIComponent('hebrew|Miqra according to the Masorah')}`;
  const res = await fetch(url);
  if (!res.ok) throw new Error(`${book}: HTTP ${res.status}`);
  const chapters = (await res.json()).versions[0].text;
  out[book] = chapters.map((verses) => verses.map((html) => {
    const h = html
      .replace(/<sup class="footnote-marker">.*?<\/sup>/g, '').replace(/<i class="footnote">.*?<\/i>/g, '')
      .replace(kq, (_, inner) => { const k = inner.match(/mam-kq-k">\((.*?)\)<\/span>/); return k ? k[1] : ' '; })
      .replace(/<span class="mam-spi-pe">.*?<\/span>/g, ' \u0001P ')
      .replace(/<span class="mam-spi-samekh">.*?<\/span>/g, ' \u0001S ')
      .replace(/<span class="mam-spi-[a-z-]+">.*?<\/span>/g, ' \u0001P ')
      .replace(/<[^>]+>/g, '').replace(/&thinsp;|&nbsp;/g, ' ');
    return strip(h).split(/\s+/).filter(Boolean).map((w) => (w.startsWith('\u0001') ? w.slice(1) : w)).join(' ');
  }));
}
await writeFile(new URL('./torah-words.json', import.meta.url), JSON.stringify(out));
console.log('wrote', Object.values(out).flat(2).join(' ').split(' ').length, 'tokens');
