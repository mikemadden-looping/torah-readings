// Parses the Adas Israel "Tricks of the Trope – Total Torah" book pages.
// Pure string parsing (no DOM) so it runs the same in Node and in a browser.

export const BOOK_PAGES = {
  Genesis: 'https://www.adasisrael.org/trope-breishit',
  Exodus: 'https://www.adasisrael.org/trope-shmot',
  Leviticus: 'https://www.adasisrael.org/trope-vayikra',
  Numbers: 'https://www.adasisrael.org/trope-bamidbar',
  Deuteronomy: 'https://www.adasisrael.org/trope-dvarim',
};

const decode = (s) => s
  .replace(/<[^>]+>/g, ' ')
  .replace(/&nbsp;|&#160;/g, ' ')
  .replace(/&ndash;|&#8211;/g, '–')
  .replace(/&mdash;|&#8212;/g, '—')
  .replace(/&rsquo;|&#8217;|&#039;|&#39;|&apos;/g, "'")
  .replace(/&amp;/g, '&')
  .replace(/\s+/g, ' ')
  .trim();

/** YouTube video ID from any youtu.be / youtube.com link, or null. */
export function youtubeId(href) {
  if (!href) return null;
  let m = href.match(/youtu\.be\/([A-Za-z0-9_-]{11})/);
  if (m) return m[1];
  m = href.match(/[?&]v=([A-Za-z0-9_-]{11})/);
  return m ? m[1] : null;
}

/**
 * Pull chapter:verse ranges out of a cell label like
 * "Aliyah 4: 39: 19 -39:23" or "Maftir, Behar w/Chazak: 25:55-26:2".
 */
export function parseRange(text) {
  // Drop the "Aliyah 1:" / "Maftir, X:" label: everything up to the first colon
  // that is followed by whitespace and that isn't part of a chapter:verse.
  let body = text.replace(/^\s*(Year\s*\d\s*,\s*)?(Aliyah\s*\d|Maftir[^:\d]*)\s*:\s*/i, '');
  // "27.34" was used once in place of "27:34"; "19:1 19:6" once lacks a dash.
  const m = body.match(/(\d+)\s*[:.]\s*(\d+)\s*(?:[-–—]|\s)\s*(\d+)\s*[:.]\s*(\d+)/);
  if (!m) return null;
  return { b: `${+m[1]}:${+m[2]}`, e: `${+m[3]}:${+m[4]}` };
}

function labelKind(text) {
  const chazak = /chazak/i.test(text);
  let m = text.match(/Aliyah\s*(\d)/i);
  if (/^\s*(Year\s*\d\s*,\s*)?Maftir/i.test(text)) return { aliyah: 'M', chazak };
  if (m) return { aliyah: m[1], chazak };
  return { aliyah: null, chazak };
}

/** Returns [{book, parsha, playlist, videos:[{column, aliyah, label, range, id, href, chazak}]}] */
export function parseBookPage(book, html) {
  const out = [];
  // Split at each <h3> (parsha headings), then read the table that follows.
  const parts = html.split(/<h3[^>]*>/i).slice(1);
  for (const part of parts) {
    const headEnd = part.search(/<\/h3>/i);
    if (headEnd < 0) continue;
    const headHtml = part.slice(0, headEnd);
    const title = decode(headHtml);
    if (!/^Parsh[ao]t\b/i.test(title)) continue;
    const parsha = title.replace(/^Parsh[ao]t\s*/i, '').trim();
    const pl = headHtml.match(/href="([^"]+)"/i);
    const entry = { book, parsha, playlist: pl ? pl[1] : null, videos: [] };
    const tableMatch = part.slice(headEnd).match(/<table[\s\S]*?<\/table>/i);
    if (tableMatch) {
      const rows = tableMatch[0].match(/<tr[\s\S]*?<\/tr>/gi) || [];
      let headers = [];
      rows.forEach((row, i) => {
        const cells = row.match(/<t[dh][^>]*>[\s\S]*?<\/t[dh]>/gi) || [];
        if (i === 0) { headers = cells.map(decode); return; }
        cells.forEach((cell, j) => {
          const text = decode(cell);
          if (!text) return;
          const hrefs = [...cell.matchAll(/href="([^"]+)"/gi)].map((x) => x[1]);
          const href = hrefs[0] || null;
          const { aliyah, chazak } = labelKind(text);
          entry.videos.push({
            column: headers[j] || `col${j + 1}`,
            aliyah,
            label: text,
            range: parseRange(text),
            id: youtubeId(href),
            href,
            chazak,
          });
        });
      });
    }
    out.push(entry);
  }
  return out;
}
