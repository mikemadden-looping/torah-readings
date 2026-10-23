import Foundation

/// One verse as Sefaria returns it (HTML strings).
struct VerseText: Hashable, Identifiable {
    let book: String
    let cv: CV
    let hebrewHTML: String
    let englishHTML: String
    var id: String { "\(book) \(cv)" }
}

enum SefariaError: LocalizedError {
    case badResponse(String)
    var errorDescription: String? {
        switch self { case .badResponse(let s): return "Couldn't load the text from Sefaria (\(s))." }
    }
}

/// Fetches Hebrew (Miqra according to the Masorah: vowels, te'amim, ketiv/keri)
/// and English from Sefaria's v3 texts API, caching responses on disk so a
/// reading opened once works offline.
actor SefariaClient {
    static let shared = SefariaClient()

    private let hebrewVersion = "Miqra according to the Masorah"
    private let cacheDir: URL = {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("sefaria", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    func verses(for passage: Passage) async throws -> [VerseText] {
        var out: [VerseText] = []
        for range in passage.ranges {
            out += try await verses(book: passage.book, range: range)
        }
        return out
    }

    private func verses(book: String, range: VerseRange) async throws -> [VerseText] {
        let ref = "\(book.replacingOccurrences(of: " ", with: "_")).\(range.sefaria)"
        let json = try await fetch(ref: ref)
        guard let versions = json["versions"] as? [[String: Any]] else { throw SefariaError.badResponse("no versions") }
        let he = versions.first { ($0["language"] as? String) == "he" }
        let en = versions.first { ($0["language"] as? String) == "en" }
        let heVerses = Self.flatten(he?["text"], start: range.start)
        let enVerses = Self.flatten(en?["text"], start: range.start)
        let enByCV = Dictionary(enVerses.map { ($0.0, $0.1) }, uniquingKeysWith: { a, _ in a })
        return heVerses.map { VerseText(book: book, cv: $0.0, hebrewHTML: $0.1, englishHTML: enByCV[$0.0] ?? "") }
    }

    /// Sefaria returns a string (one verse), [String] (one chapter) or
    /// [[String]] (several chapters, the first starting at `start`).
    private static func flatten(_ text: Any?, start: CV) -> [(CV, String)] {
        if let s = text as? String { return [(start, s)] }
        if let chapters = text as? [[String]] {
            var out: [(CV, String)] = []
            for (i, verses) in chapters.enumerated() {
                let chapter = start.chapter + i
                let first = i == 0 ? start.verse : 1
                for (j, v) in verses.enumerated() { out.append((CV(chapter, first + j), v)) }
            }
            return out
        }
        if let verses = text as? [String] {
            return verses.enumerated().map { (CV(start.chapter, start.verse + $0.offset), $0.element) }
        }
        return []
    }

    private func fetch(ref: String) async throws -> [String: Any] {
        let cacheFile = cacheDir.appendingPathComponent(ref.replacingOccurrences(of: "/", with: "_") + ".json")
        if let data = try? Data(contentsOf: cacheFile),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return json
        }
        var comps = URLComponents(string: "https://www.sefaria.org/api/v3/texts/\(ref)")!
        comps.queryItems = [
            URLQueryItem(name: "version", value: "hebrew|\(hebrewVersion)"),
            URLQueryItem(name: "version", value: "english"),
        ]
        let (data, response) = try await URLSession.shared.data(from: comps.url!)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw SefariaError.badResponse("HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SefariaError.badResponse("unreadable response")
        }
        let versions = json["versions"] as? [[String: Any]] ?? []
        if !versions.contains(where: { ($0["language"] as? String) == "he" }) {
            throw SefariaError.badResponse("no Hebrew text for \(ref)")
        }
        try? data.write(to: cacheFile)
        return json
    }
}
