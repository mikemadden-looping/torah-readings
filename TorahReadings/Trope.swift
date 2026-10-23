import SwiftUI

/// Torah te'amim grouped the way they're taught: each disjunctive (pausal)
/// trope ends a phrase, and the conjunctive tropes before it belong to it.
/// Coloring a phrase by its ending disjunctive makes the units you chant
/// (mercha-tipcha, munach-etnachta, mahpach-pashta-munach-zakef…) stand out.
enum TropeFamily: String, CaseIterable, Identifiable {
    case sofPasuq, etnachta, segol, shalshelet, zakef, tipcha, revia
    case pashta, zarka, tevir, geresh, pazer

    var id: String { rawValue }

    var name: String {
        switch self {
        case .sofPasuq: return "Sof pasuk"
        case .etnachta: return "Etnachta"
        case .segol: return "Segol"
        case .shalshelet: return "Shalshelet"
        case .zakef: return "Zakef katon / gadol"
        case .tipcha: return "Tipcha"
        case .revia: return "Revia"
        case .pashta: return "Pashta / yetiv"
        case .zarka: return "Zarka"
        case .tevir: return "Tevir"
        case .geresh: return "Geresh / gershayim"
        case .pazer: return "Pazer, telisha gedolah, legarmeh"
        }
    }

    var color: Color {
        switch self {
        case .sofPasuq: return .blue
        case .etnachta: return .purple
        case .segol: return .pink
        case .shalshelet: return .red
        case .zakef: return .orange
        case .tipcha: return .teal
        case .revia: return .green
        case .pashta: return .brown
        case .zarka: return .indigo
        case .tevir: return .mint
        case .geresh: return .cyan
        case .pazer: return Color(red: 0.75, green: 0.6, blue: 0.0)
        }
    }

    /// Which disjunctive a word carries, if any.
    static func of(word: String) -> TropeFamily? {
        let marks = Set(word.unicodeScalars.map(\.value))
        if marks.contains(0x05C3) { return .sofPasuq }          // ׃ (with silluq)
        if marks.contains(0x0591) { return .etnachta }
        if marks.contains(0x0593) { return .shalshelet }
        if marks.contains(0x0592) { return .segol }
        if marks.contains(0x0594) || marks.contains(0x0595) { return .zakef }
        if marks.contains(0x0596) { return .tipcha }
        if marks.contains(0x0597) { return .revia }
        if marks.contains(0x0599) || marks.contains(0x059A) { return .pashta }
        if marks.contains(0x05AE) || marks.contains(0x0598) { return .zarka }
        if marks.contains(0x059B) { return .tevir }
        if marks.contains(0x059C) || marks.contains(0x059D) || marks.contains(0x059E) { return .geresh }
        if marks.contains(0x05A1) || marks.contains(0x059F) || marks.contains(0x05A0) { return .pazer }
        return nil
    }
}

/// A displayable word in the trope view.
struct TropeWord {
    var text: String          // pointed text as chanted (keri where it differs)
    var ketiv: String?        // shown small when the written form differs
    var readOnly: Bool = false // keri with no ketiv
    var notRead: Bool = false  // ketiv with no keri
    var family: TropeFamily? = nil
}

enum TropeLayout {
    enum Item { case word(TropeWord), petucha, setuma }

    /// Turns a verse's pieces into words, then gives every word the family of
    /// the disjunctive that ends its phrase.
    static func items(_ pieces: [Piece]) -> [Item] {
        var items: [Item] = []
        for p in pieces {
            switch p {
            case .text(let t):
                for w in t.split(whereSeparator: { $0 == " " || $0 == "\u{2009}" }) {
                    let word = String(w)
                    // A paseq (׀) stands between words; attach it to the previous one
                    // so munach + paseq reads as legarmeh.
                    if word == "׀", case .word(var prev)? = items.last {
                        prev.text += " ׀"
                        items[items.count - 1] = .word(prev)
                    } else {
                        items.append(.word(TropeWord(text: word)))
                    }
                }
            case .kq(let k, let q):
                if let q { items.append(.word(TropeWord(text: q, ketiv: k, readOnly: k == nil))) }
                else if let k { items.append(.word(TropeWord(text: k, notRead: true))) }
            case .petucha: items.append(.petucha)
            case .setuma: items.append(.setuma)
            }
        }
        // Walk backwards: each disjunctive starts a new phrase that the
        // conjunctives before it inherit.
        var current: TropeFamily? = nil
        for i in items.indices.reversed() {
            guard case .word(var w) = items[i] else { continue }
            if w.notRead { continue }
            if let f = TropeFamily.of(word: w.text) {
                current = f
            } else if w.text.hasSuffix("׀"), w.text.unicodeScalars.contains(where: { $0.value == 0x05A3 }) {
                current = .pazer                                    // legarmeh
            }
            w.family = current
            items[i] = .word(w)
        }
        return items
    }
}
