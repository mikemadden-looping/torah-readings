import Foundation

// MARK: - Bundled data (built by scripts/build-data.mjs)

struct ReadingsFile: Decodable {
    let generated: String
    let firstYear: Int
    let lastYear: Int
    let shabbatot: [Shabbat]
}

struct Shabbat: Decodable, Identifiable, Hashable {
    let date: String          // yyyy-MM-dd (Gregorian Shabbat date)
    let hdate: String         // "13th of Cheshvan, 5787"
    let hyear: Int
    let parsha: String        // Hebcal name, e.g. "Lech-Lecha", "Vayakhel-Pekudei"
    let parshaHe: String
    let cycleYear: Int        // 1, 2 or 3
    let variation: String?
    let playlist: String?
    let aliyot: [Aliyah]

    var id: String { date }
    var day: Date { DateFormatter.isoDay.date(from: date) ?? .distantPast }
    func aliyah(_ n: String) -> Aliyah? { aliyot.first { $0.n == n } }
}

struct Aliyah: Decodable, Hashable {
    let n: String             // "1"…"7" or "M"
    let book: String
    let b: String             // "41:53"
    let e: String             // "41:57"
    let verses: Int?
    let reason: String?       // e.g. "Shabbat Shekalim" for a special maftir

    var range: VerseRange { VerseRange(start: CV(b) ?? CV(1, 1), end: CV(e) ?? CV(1, 1)) }
    var label: String { n == "M" ? "Maftir" : "Aliyah \(n)" }
}

struct VideosFile: Decodable {
    let generated: String
    let playlists: [String: String?]
    let videos: [Video]
}

struct Video: Decodable, Hashable, Identifiable {
    let book: String
    let b: String
    let e: String
    let id: String            // YouTube video ID
    let label: String         // "Miketz · Year 2 · Aliyah 1: 41:53 - 41:57"
    let parsha: String
    let chazak: Bool?

    var range: VerseRange { VerseRange(start: CV(b) ?? CV(1, 1), end: CV(e) ?? CV(1, 1)) }
    var isChazak: Bool { chazak ?? false }
}

// MARK: - Verses

struct CV: Hashable, Comparable, CustomStringConvertible {
    let chapter: Int
    let verse: Int
    init(_ chapter: Int, _ verse: Int) { self.chapter = chapter; self.verse = verse }
    init?(_ s: String) {
        let parts = s.split(separator: ":").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count == 2 else { return nil }
        self.init(parts[0], parts[1])
    }
    static func < (a: CV, b: CV) -> Bool { (a.chapter, a.verse) < (b.chapter, b.verse) }
    var description: String { "\(chapter):\(verse)" }
}

struct VerseRange: Hashable {
    let start: CV
    let end: CV
    func overlaps(_ o: VerseRange) -> Bool { start <= o.end && o.start <= end }
    func covers(_ o: VerseRange) -> Bool { start <= o.start && end >= o.end }
    func contains(_ v: CV) -> Bool { start <= v && v <= end }

    /// "41:53–57" or "32:31–33:5"
    var display: String {
        if start == end { return start.description }
        if start.chapter == end.chapter { return "\(start)–\(end.verse)" }
        return "\(start)–\(end)"
    }
    /// Sefaria ref fragment: "41.53-57" or "32.31-33.5"
    var sefaria: String {
        if start == end { return "\(start.chapter).\(start.verse)" }
        if start.chapter == end.chapter { return "\(start.chapter).\(start.verse)-\(end.verse)" }
        return "\(start.chapter).\(start.verse)-\(end.chapter).\(end.verse)"
    }
}

/// Something to read: one book, one or more verse ranges.
struct Passage: Hashable, Identifiable {
    let book: String
    let ranges: [VerseRange]
    var id: String { "\(book) \(ranges.map(\.display).joined(separator: "; "))" }
    var display: String { "\(book) \(ranges.map(\.display).joined(separator: ", "))" }
    var isTorah: Bool { ["Genesis", "Exodus", "Leviticus", "Numbers", "Deuteronomy"].contains(book) }

    /// Parses refs as written on the sign-up sheet:
    /// "Genesis 41:53-41:57", "Isaiah 54:1-10", "Joshua 5:13-6:5; 6:15-16",
    /// "Numbers 7:54-8:4 | Chanukah Day 8 (on Shabbat)", "II Kings 6:8-23".
    static func parse(_ raw: String) -> Passage? {
        let ref = raw.split(separator: "|").first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
        guard let m = ref.firstMatch(of: #/^(.+?)\s+(\d+\s*:.*)$/#) else { return nil }
        let book = String(m.1).trimmingCharacters(in: .whitespaces)
        var ranges: [VerseRange] = []
        var chapter: Int?
        for piece in m.2.split(whereSeparator: { $0 == ";" || $0 == "," }) {
            let ends = piece.split(whereSeparator: { "-–—".contains($0) }).map { $0.trimmingCharacters(in: .whitespaces) }
            func point(_ s: String) -> CV? {
                if let cv = CV(s) { chapter = cv.chapter; return cv }
                if let v = Int(s), let c = chapter { return CV(c, v) }
                return nil
            }
            guard let first = ends.first, let start = point(first) else { continue }
            let end = ends.count > 1 ? (point(ends[1]) ?? start) : start
            ranges.append(VerseRange(start: start, end: end))
        }
        return ranges.isEmpty ? nil : Passage(book: book, ranges: ranges)
    }
}

extension DateFormatter {
    static let isoDay: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    static let longDay: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .full
        f.timeStyle = .none
        return f
    }()
}
