import SwiftUI
import UIKit

/// Where every line of the standard 245-column, 42-line scroll begins
/// (Resources/scroll.json, built by scripts/tikkun).
final class ScrollLayout {
    static let shared = ScrollLayout()

    struct Key: Comparable, Hashable {
        let book: Int, chapter: Int, verse: Int, word: Int
        static func < (a: Key, b: Key) -> Bool {
            (a.book, a.chapter, a.verse, a.word) < (b.book, b.chapter, b.verse, b.word)
        }
    }

    static let books = ["Genesis", "Exodus", "Leviticus", "Numbers", "Deuteronomy"]
    let linesPerColumn: Int
    /// (line index, first word on that line), for every line that has words, in order.
    private let starts: [(line: Int, key: Key)]

    private init() {
        struct File: Decodable { let linesPerColumn: Int; let lines: [String?] }
        guard let url = Bundle.main.url(forResource: "scroll", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(File.self, from: data) else {
            linesPerColumn = 42; starts = []; return
        }
        linesPerColumn = file.linesPerColumn
        starts = file.lines.enumerated().compactMap { i, s in
            guard let s else { return nil }
            let p = s.split(separator: ".").compactMap { Int($0) }
            guard p.count == 4 else { return nil }
            return (i, Key(book: p[0], chapter: p[1], verse: p[2], word: p[3]))
        }
    }

    var isAvailable: Bool { !starts.isEmpty }

    /// The scroll line a word sits on.
    func line(of key: Key) -> Int? {
        var lo = 0, hi = starts.count - 1, found: Int?
        while lo <= hi {
            let mid = (lo + hi) / 2
            if starts[mid].key <= key { found = mid; lo = mid + 1 } else { hi = mid - 1 }
        }
        return found.map { starts[$0].line }
    }

    /// Lines with no words (the blank lines between books, and the like) between two lines.
    func blankLines(after a: Int, before b: Int) -> Int {
        guard b > a + 1 else { return 0 }
        let withWords = starts.filter { $0.line > a && $0.line < b }.count
        return (b - a - 1) - withWords
    }
}

/// One word as written in the scroll.
struct ScrollWord: Hashable {
    let cv: CV
    let index: Int            // position within its verse
    let text: String
    let inPassage: Bool
    var openBreakAfter = false
    var closedBreakAfter = false
    var verseStart: Bool { index == 0 }
}

enum ScrollWords {
    /// The words of a verse as a scroll writes them: ketiv spellings, maqaf-joined
    /// words written separately, no vowels or te'amim. Must split words exactly
    /// as scripts/export-torah-words.mjs does, since scroll.json counts them.
    static func words(_ v: VerseText, inPassage: Bool) -> [ScrollWord] {
        var out: [ScrollWord] = []
        func add(_ s: String) {
            for w in HebrewText.scroll(s).split(separator: " ") where !w.isEmpty {
                out.append(ScrollWord(cv: v.cv, index: out.count, text: String(w), inPassage: inPassage))
            }
        }
        for piece in HebrewText.pieces(v.hebrewHTML) {
            switch piece {
            case .text(let t): add(t)
            case .kq(let k, _): if let k { add(k) }
            case .petucha: if !out.isEmpty { out[out.count - 1].openBreakAfter = true }
            case .setuma: if !out.isEmpty { out[out.count - 1].closedBreakAfter = true }
            }
        }
        return out
    }
}

/// Lays the passage out line by line as in the scroll, justified, with the
/// rest of the first and last lines shown faintly for context.
struct TikkunView: View {
    let passage: Passage
    let fontName: String
    let maxFontSize: Double
    let showVerseNumbers: Bool

    @State private var lines: [TikkunLine] = []
    @State private var failed = false

    struct TikkunLine: Identifiable {
        let line: Int
        let words: [ScrollWord]
        let blankBefore: Int
        var id: Int { line }
        var column: Int { line / 42 + 1 }
        var lineInColumn: Int { line % 42 + 1 }
        /// The last line of an open paragraph isn't stretched to the margin.
        var justified: Bool { !(words.last?.openBreakAfter ?? false) }
    }

    private let ink = Color(red: 0.08, green: 0.07, blue: 0.06)
    private let parchment = Color(red: 0.96, green: 0.92, blue: 0.83)

    var body: some View {
        Group {
            if failed || !ScrollLayout.shared.isAvailable {
                Text("The scroll layout isn't available for this reading.").font(.footnote).foregroundStyle(.secondary)
            } else if lines.isEmpty {
                ProgressView().frame(maxWidth: .infinity)
            } else {
                GeometryReader { geo in
                    let size = fittedSize(width: geo.size.width - 36)
                    VStack(alignment: .leading, spacing: size * 0.55) {
                        ForEach(Array(lines.enumerated()), id: \.element.id) { i, l in
                            if i == 0 || l.column != lines[i - 1].column {
                                Text("Column \(l.column) · line \(l.lineInColumn)")
                                    .font(.caption2).foregroundStyle(ink.opacity(0.45))
                                    .environment(\.layoutDirection, .leftToRight)
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                            } else if l.blankBefore > 0 {
                                Color.clear.frame(height: CGFloat(l.blankBefore) * size * 1.55)
                            }
                            lineView(l, size: size)
                        }
                    }
                    .padding(.horizontal, 18).padding(.vertical, 20)
                    .background(parchment, in: RoundedRectangle(cornerRadius: 6))
                    .background(GeometryReader { inner in
                        Color.clear.preference(key: HeightKey.self, value: inner.size.height)
                    })
                }
                .frame(height: height)
                .onPreferenceChange(HeightKey.self) { height = $0 }
                .environment(\.layoutDirection, .rightToLeft)
                .environment(\.colorScheme, .light)
            }
        }
        .task(id: passage.id) { await load() }
    }

    @State private var height: CGFloat = 400
    private struct HeightKey: PreferenceKey {
        static var defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
    }

    private func lineView(_ l: TikkunLine, size: Double) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(l.words.enumerated()), id: \.offset) { j, w in
                if j > 0 {
                    if l.words[j - 1].closedBreakAfter {
                        Spacer(minLength: size * 3)          // closed paragraph gap
                    } else if l.justified {
                        Spacer(minLength: size * 0.3)
                    } else {
                        Spacer().frame(width: size * 0.35)
                    }
                }
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    if showVerseNumbers && w.verseStart {
                        Text(HebrewText.numeral(w.cv.verse)).font(.system(size: size * 0.38)).foregroundStyle(ink.opacity(0.4))
                    }
                    Text(w.text)
                        .font(.custom(fontName, size: size))
                        .foregroundStyle(w.inPassage ? ink : ink.opacity(0.22))
                        .fixedSize()
                }
            }
            if !l.justified { Spacer(minLength: 0) }
        }
    }

    /// Largest font size (up to the reader's setting) at which every line fits.
    private func fittedSize(width: CGFloat) -> Double {
        guard width > 0, let base = UIFont(name: fontName, size: 20) ?? UIFont(name: Fonts.hebrew, size: 20) else { return maxFontSize }
        var widest: CGFloat = 1
        for l in lines {
            let text = l.words.map(\.text).joined()
            let w = (text as NSString).size(withAttributes: [.font: base]).width
            let gaps = CGFloat(max(0, l.words.count - 1)) * 20 * 0.3
            widest = max(widest, w + gaps)
        }
        return min(maxFontSize, max(10, Double(20 * width / widest)))
    }

    private func load() async {
        if let out = await TikkunView.buildLines(for: passage), !out.isEmpty { lines = out } else { failed = true }
    }

    /// The scroll lines holding a passage, with the neighboring verses' words
    /// filling out the first and last lines. Shared with the PDF export.
    static func buildLines(for passage: Passage) async -> [TikkunLine]? {
        guard let bookIndex = ScrollLayout.books.firstIndex(of: passage.book),
              let first = passage.ranges.first, let last = passage.ranges.last else { return nil }
        guard let main = try? await SefariaClient.shared.verses(for: passage) else { return nil }
        // One verse either side fills out the first and last scroll lines.
        var before: [VerseText] = [], after: [VerseText] = []
        if first.start.verse > 1 {
            let v = CV(first.start.chapter, first.start.verse - 1)
            before = (try? await SefariaClient.shared.verses(for: Passage(book: passage.book, ranges: [VerseRange(start: v, end: v)]))) ?? []
        }
        let n = CV(last.end.chapter, last.end.verse + 1)
        after = ((try? await SefariaClient.shared.verses(for: Passage(book: passage.book, ranges: [VerseRange(start: n, end: n)]))) ?? [])
            .filter { !$0.hebrewHTML.isEmpty }

        var words: [ScrollWord] = []
        for v in before { words += ScrollWords.words(v, inPassage: false) }
        for v in main { words += ScrollWords.words(v, inPassage: true) }
        for v in after { words += ScrollWords.words(v, inPassage: false) }

        let layout = ScrollLayout.shared
        var byLine: [Int: [ScrollWord]] = [:]
        for w in words {
            let key = ScrollLayout.Key(book: bookIndex, chapter: w.cv.chapter, verse: w.cv.verse, word: w.index)
            if let line = layout.line(of: key) { byLine[line, default: []].append(w) }
        }
        let keep = byLine.filter { $0.value.contains(where: \.inPassage) }.keys.sorted()
        var out: [TikkunLine] = []
        for (i, line) in keep.enumerated() {
            let blank = i == 0 ? 0 : layout.blankLines(after: keep[i - 1], before: line)
            out.append(TikkunLine(line: line, words: byLine[line] ?? [], blankBefore: blank))
        }
        return out
    }
}
