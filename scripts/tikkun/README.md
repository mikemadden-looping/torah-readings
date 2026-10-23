# Tikkun line layout

`TorahReadings/Resources/scroll.json` records where each of the 10,290 lines of
the standard 245-column, 42-line Torah scroll begins, as
`book.chapter.verse.word` (book 0–4, word = position within the verse, counting
words the way a scroll writes them). The app uses it to break the Tikkun view
into the scroll's lines.

There's no open dataset of scroll line breaks, so this was fitted from images:

1. **Column images.** The 245 tikkun column images in
   [doronlevy6/young-golomb](https://github.com/doronlevy6/young-golomb)
   (`columns/`), whose layout comes from Ahavat Ivrit.
2. **Measure** (`measure_columns.py`). For each image: fit the 42-line grid,
   then for each line record the gaps between ink runs (positions and widths)
   and the amount of ink. Masks scanner shadows and the blue anchor boxes.
3. **Text** (`../export-torah-words.mjs`, workflow *5. Export Torah text*).
   Sefaria's *Miqra according to the Masorah* as scroll words: ketiv spellings,
   maqaf-joined words split, editorial footnotes removed, with open and closed
   paragraph breaks.
4. **Align** (`align.py`, `build_scroll.py`). A dynamic program assigns
   consecutive words to the 10,290 lines. Hard rule: every open paragraph
   starts a new line. Evidence per line: the measured word gaps, the ink
   per letter, and how well the measured word widths match the words' widths
   in Stam Ashkenaz CLM (`stam_letter_widths.json`). The first pass searches
   ±900 words; later passes refine around the previous result.
5. **Check** (`score.py`, `spot_check.py`). `score.py` reports how well each
   line's word widths fit; `spot_check.py` draws image lines with the fitted
   text underneath.

Result (Oct 2026): all 292 open paragraph breaks fall at line starts, and
9,917 of 10,232 text lines (97%) fit closely. The rest are mostly one-word
slips in a few columns with scan damage (notably column 95), which correct
themselves by the next paragraph break.

The scripts expect the young-golomb checkout at `../ext/yg` and write their
intermediate files to the working directory; adjust the paths to rerun.
