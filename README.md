# Torah Readings

A small iPhone app for preparing a triennial Torah reading. Pick a parsha and
aliyah (or let it find the ones you're signed up for) and it shows:

- **Trope** — the Hebrew with vowels and te'amim, with an optional toggle that
  colors each trope phrase by the pausing trope that ends it
- **Torah** — the same verses as written in a scroll: letters only, ketiv
  spellings, open/closed paragraph breaks
- **English** — Sefaria's English translation
- **Video** — the matching *Tricks of the Trope – Total Torah* video from
  [Adas Israel](https://www.adasisrael.org/trope), embedded

## Where the data comes from

| What | Source |
|---|---|
| Which verses each aliyah is, by triennial year | [Hebcal](https://www.hebcal.com) `@hebcal/triennial` (diaspora), CC BY 4.0 |
| Hebrew and English text | [Sefaria](https://www.sefaria.org) API — *Miqra according to the Masorah* (CC BY-SA) and Sefaria's default English, fetched on demand and cached for offline use |
| Videos | The five book pages under adasisrael.org/trope |
| Your readings | The shul's Google sign-up sheet (set in the app's Settings; General access must be "Anyone with the link") |

`scripts/build-data.mjs` turns Hebcal and the Adas Israel pages into
`TorahReadings/Resources/readings.json` (every Shabbat for four triennial
cycles) and `videos.json`, and writes **`scripts/report.md`** listing problems
it found on the Adas Israel pages (broken links, mistyped verse ranges) and any
aliyot no video fully covers.

Videos are matched by verse range, not by "Year 2, Aliyah 4", so the app still
finds the right video when a double parsha is read separately or the maftir is
special. When the reading's verses don't line up exactly with a video, the app
lists the videos that cover it and says which verses each one covers.

## Install with TestFlight (GitHub Actions)

Uses the same signing secrets as the Trio Browser Build, set on the
`mikemadden-looping` organization: `TEAMID`, `GH_PAT`, `FASTLANE_KEY_ID`,
`FASTLANE_ISSUER_ID`, `FASTLANE_KEY`, `MATCH_PASSWORD`, plus the existing
`Match-Secrets` repository.

1. **Actions → 1. Add identifier → Run workflow.** Registers
   `com.<TEAMID>.torahreadings` and makes its App Store profile.
2. **App Store Connect → Apps → + → New App.** Platform iOS, any name (e.g.
   "Torah Readings"), bundle ID `com.<TEAMID>.torahreadings`, any SKU.
3. **Actions → 2. Build to TestFlight → Run workflow.** About 10 minutes, then
   Apple takes a few more to process it.
4. In App Store Connect → the app → **TestFlight**, add yourself to an internal
   testing group (once), then install from the TestFlight app.

**0. Check build** compiles on every push without signing.
**3. Update readings and videos** runs weekly (and on demand) and commits new
data if Hebcal or the Adas Israel pages changed; run step 3 of the install
again afterwards to put it in the app. TestFlight builds expire after 90 days.

## Optional: a STaM font for the Torah view

The Torah view uses Noto Serif Hebrew by default. To get scroll-style letters,
add a STaM font file (for example *Stam Ashkenaz CLM* from the
[Culmus project](https://culmus.sourceforge.io)) to `TorahReadings/Fonts/`. Any
bundled font whose family name contains "Stam" is used automatically.

## Build locally instead (Mac with Xcode 26)

`brew install xcodegen`, then `xcodegen generate`, open `TorahReadings.xcodeproj`,
pick your team under Signing & Capabilities, and run.
