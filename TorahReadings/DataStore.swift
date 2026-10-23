import Foundation

/// Loads the bundled Hebcal readings and Adas Israel video index.
final class DataStore {
    static let shared = DataStore()

    let readings: ReadingsFile
    let videos: VideosFile
    /// Parsha names in Torah order (combined names like "Vayakhel-Pekudei" sit
    /// right before their first half).
    let parshaOrder: [String]

    private init() {
        readings = Self.load("readings")
        videos = Self.load("videos")
        var firstVerse: [String: (Int, CV)] = [:]
        let books = ["Genesis", "Exodus", "Leviticus", "Numbers", "Deuteronomy"]
        for s in readings.shabbatot {
            guard let a = s.aliyah("1"), let book = books.firstIndex(of: a.book) else { continue }
            let key = (book, a.range.start)
            if let old = firstVerse[s.parsha], (old.0, old.1) <= key { continue }
            firstVerse[s.parsha] = key
        }
        parshaOrder = firstVerse.keys.sorted {
            let a = firstVerse[$0]!, b = firstVerse[$1]!
            if a.0 != b.0 { return a.0 < b.0 }
            if a.1 != b.1 { return a.1 < b.1 }
            return $0.count > $1.count  // combined name first
        }
    }

    private static func load<T: Decodable>(_ name: String) -> T {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json"),
              let data = try? Data(contentsOf: url) else { fatalError("Missing \(name).json in app bundle") }
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { fatalError("Bad \(name).json: \(error)") }
    }

    // MARK: Lookups

    private var today: Date { Calendar.current.startOfDay(for: Date()) }

    /// The next Shabbat on or after today.
    var upcomingShabbat: Shabbat? {
        readings.shabbatot.first { $0.day >= today } ?? readings.shabbatot.last
    }

    func shabbat(on date: Date) -> Shabbat? {
        let key = DateFormatter.isoDay.string(from: date)
        return readings.shabbatot.first { $0.date == key }
    }

    /// The next time this parsha is read, optionally in a specific triennial year.
    func nextReading(of parsha: String, cycleYear: Int? = nil) -> Shabbat? {
        let matches = readings.shabbatot.filter { $0.parsha == parsha && (cycleYear == nil || $0.cycleYear == cycleYear) }
        return matches.first { $0.day >= today } ?? matches.last
    }

    // MARK: Videos

    struct VideoChoice: Hashable, Identifiable {
        let video: Video
        let chazakAlternate: Video?
        /// true when the video's verses are exactly the passage's
        let exact: Bool
        var id: String { video.id }
    }

    struct VideoMatch {
        let choices: [VideoChoice]
        /// true when the chosen videos cover every verse of the passage
        let complete: Bool
    }

    /// Same rules as scripts/build-data.mjs: an exact match if there is one,
    /// otherwise the tightest single video that covers the passage, otherwise
    /// the videos that together cover as much of it as possible.
    func videos(for passage: Passage) -> VideoMatch {
        guard passage.isTorah, let want = passage.ranges.first.map({ r in
            VerseRange(start: r.start, end: passage.ranges.last!.end)
        }) else { return VideoMatch(choices: [], complete: false) }

        let pool = videos.videos.filter { $0.book == passage.book && $0.range.overlaps(want) }
        // Group identical ranges: plain version first, chazak as alternate.
        var groups: [VerseRange: (main: Video?, chazak: Video?)] = [:]
        var order: [VerseRange] = []
        for v in pool {
            if groups[v.range] == nil { order.append(v.range) }
            var g = groups[v.range] ?? (main: nil, chazak: nil)
            if v.isChazak { if g.chazak == nil { g.chazak = v } } else if g.main == nil { g.main = v }
            groups[v.range] = g
        }
        func choice(_ r: VerseRange) -> VideoChoice? {
            guard let g = groups[r], let main = g.main ?? g.chazak else { return nil }
            let alt = (g.main != nil && g.chazak != nil) ? g.chazak : nil
            return VideoChoice(video: main, chazakAlternate: alt, exact: r == want)
        }

        if let c = choice(want) { return VideoMatch(choices: [c], complete: true) }

        let whole = order.filter { $0.covers(want) }.sorted {
            $0.start != $1.start ? $0.start > $1.start : $0.end < $1.end
        }
        if let best = whole.first, let c = choice(best) { return VideoMatch(choices: [c], complete: true) }

        var chosen: [VerseRange] = []
        var end: CV?
        for r in order.sorted(by: { $0.start != $1.start ? $0.start < $1.start : $0.end > $1.end }) {
            if end == nil || r.end > end! { chosen.append(r); end = r.end }
        }
        let complete = (chosen.first.map { $0.start <= want.start } ?? false) && (end.map { $0 >= want.end } ?? false)
        return VideoMatch(choices: chosen.compactMap(choice), complete: complete)
    }

    func playlist(for shabbat: Shabbat) -> URL? {
        shabbat.playlist.flatMap(URL.init(string:))
    }
}
