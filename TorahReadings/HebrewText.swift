import Foundation

/// A verse broken into what matters for display.
enum Piece: Hashable {
    case text(String)
    /// Written (ketiv, unpointed) vs. read (keri, pointed). Either may be missing:
    /// keri-without-ketiv is read but not written; ketiv-without-keri is written but not read.
    case kq(ketiv: String?, keri: String?)
    case petucha     // open paragraph break {פ}
    case setuma      // closed paragraph break {ס}
}

enum HebrewText {
    private static let kqBlock = #/<span class="mam-kq">(.*?)</span></span>/#
    private static let ketivRx = #/mam-kq-k">\((.*?)\)</span>/#
    private static let keriRx = #/mam-kq-q">\[(.*?)\]</span>/#
    private static let breakRx = #/<span class="mam-spi-([a-z-]+)">\{.*?\}</span>/#

    /// Splits Sefaria's Miqra-according-to-the-Masorah HTML into pieces.
    static func pieces(_ html: String) -> [Piece] {
        var out: [Piece] = []
        // Drop Sefaria's editorial footnotes (e.g. notes on Yemenite scroll spellings).
        let cleaned = html.replacing(#/<sup class="footnote-marker">.*?</sup>/#, with: "")
            .replacing(#/<i class="footnote">.*?</i>/#, with: "")
        var rest = Substring(cleaned)
        while !rest.isEmpty {
            let kq = rest.firstMatch(of: kqBlock)
            let br = rest.firstMatch(of: breakRx)
            let next = [kq?.range, br?.range].compactMap { $0 }.min { $0.lowerBound < $1.lowerBound }
            guard let range = next else { appendText(String(rest), to: &out); break }
            appendText(String(rest[..<range.lowerBound]), to: &out)
            if let kq, kq.range == range {
                let inner = kq.1
                let k = inner.firstMatch(of: ketivRx).map { plain(String($0.1)) }
                let q = inner.firstMatch(of: keriRx).map { plain(String($0.1)) }
                out.append(.kq(ketiv: k, keri: q))
            } else if let br {
                out.append(br.1.contains("samekh") ? .setuma : .petucha)
            }
            rest = rest[range.upperBound...]
        }
        return out
    }

    private static func appendText(_ html: String, to out: inout [Piece]) {
        let t = plain(html)
        if !t.trimmingCharacters(in: .whitespaces).isEmpty { out.append(.text(t)) }
        else if !t.isEmpty, case .text = out.last { out.append(.text(" ")) }
    }

    /// Strips tags and decodes the entities Sefaria uses.
    static func plain(_ html: String) -> String {
        var s = html.replacing(#/<br\s*/?>/#, with: " ")
        s = s.replacing(#/<[^>]+>/#, with: "")
        for (entity, char) in [("&thinsp;", "\u{2009}"), ("&nbsp;", " "), ("&amp;", "&"), ("&lt;", "<"),
                               ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&#x27;", "'")] {
            s = s.replacingOccurrences(of: entity, with: char)
        }
        return s.replacing(#/[ \u{00A0}]{2,}/#, with: " ")
    }

    /// Letters only, as written in a Torah scroll: no vowels, te'amim, maqaf,
    /// paseq or sof pasuq.
    static func scroll(_ s: String) -> String {
        var out = String.UnicodeScalarView()
        for u in s.unicodeScalars {
            switch u.value {
            case 0x05BE: out.append(" ")                                  // maqaf → word space
            case 0x2009: out.append(" ")                                  // thin space (around a paseq)
            case 0x0591...0x05C7, 0x034F, 0x200B...0x200F: continue          // marks, CGJ, joiners
            default: out.append(u)
            }
        }
        return String(out).replacing(#/\s+/#, with: " ").trimmingCharacters(in: .whitespaces)
    }

    /// English with Sefaria's footnotes removed.
    static func english(_ html: String) -> String {
        var s = html.replacing(#/<sup class="footnote-marker">.*?</sup>/#, with: "")
        s = s.replacing(#/<i class="footnote">.*?</i>/#, with: "")
        return plain(s).trimmingCharacters(in: .whitespaces)
    }

    /// Hebrew numerals for verse numbers (1 → א, 15 → טו, 16 → טז).
    static func numeral(_ n: Int) -> String {
        let hundreds = ["", "ק", "ר", "ש", "ת"], tens = ["", "י", "כ", "ל", "מ", "נ", "ס", "ע", "פ", "צ"]
        let ones = ["", "א", "ב", "ג", "ד", "ה", "ו", "ז", "ח", "ט"]
        var s = n >= 100 ? hundreds[min(n / 100, 4)] : ""
        let r = n % 100
        if r == 15 { return s + "טו" }
        if r == 16 { return s + "טז" }
        s += tens[r / 10] + ones[r % 10]
        return s
    }
}
