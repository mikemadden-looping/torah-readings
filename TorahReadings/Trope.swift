import SwiftUI

/// Trope groups as they're taught (and as TropeTrainer colors them): each
/// group ends in a major pausing trope, and the conjunctive tropes and the
/// minor pausing trope before it belong to it — so mercha tipcha mercha
/// sof pasuk is one sof pasuk group, mahpach pashta munach zakef katon is
/// one katon group, and so on.
enum TropeGroup: String, CaseIterable, Identifiable {
    case sofPasuk, etnachta, katon, zakefGadol, segol, revia, tevir
    case geresh, pazer, telishaGedolah, shalshelet, legarmeh

    var id: String { rawValue }

    var name: String {
        switch self {
        case .sofPasuk: return "Sof pasuk — mercha tipcha mercha sof pasuk"
        case .etnachta: return "Etnachta — mercha tipcha munach etnachta"
        case .katon: return "Katon — mahpach pashta munach zakef katon"
        case .zakefGadol: return "Zakef gadol"
        case .segol: return "Segol — munach zarka munach segol"
        case .revia: return "Revia — munach revia"
        case .tevir: return "Tevir — darga tevir"
        case .geresh: return "Geresh — kadma v'azla, gershayim"
        case .pazer: return "Pazer"
        case .telishaGedolah: return "Telisha gedolah"
        case .shalshelet: return "Shalshelet"
        case .legarmeh: return "Munach legarmeh"
        }
    }

    /// Pastel highlights matching TropeTrainer where it shows them; black text sits on top.
    var color: Color {
        func c(_ hex: UInt32) -> Color {
            Color(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
        }
        switch self {
        case .sofPasuk: return c(0xE8807F)
        case .etnachta: return c(0x8AB4F8)
        case .katon: return c(0xFFFF99)
        case .zakefGadol: return c(0xF5D45A)
        case .segol: return c(0xCDB4F4)
        case .revia: return c(0xF7BE87)
        case .tevir: return c(0x9CF58F)
        case .geresh: return c(0xF4B4B4)
        case .pazer: return c(0x8EE3E0)
        case .telishaGedolah: return c(0xB8E0A0)
        case .shalshelet: return c(0xD0D0D0)
        case .legarmeh: return c(0xE6CCF2)
        }
    }

    /// A major pausing trope that ends a group.
    static func ending(_ word: String) -> TropeGroup? {
        let m = Set(word.unicodeScalars.map(\.value))
        if m.contains(0x05C3) { return .sofPasuk }               // ׃ (silluq)
        if m.contains(0x0591) { return .etnachta }
        if m.contains(0x0593) { return .shalshelet }
        if m.contains(0x0592) { return .segol }
        if m.contains(0x0594) { return .katon }
        if m.contains(0x0595) { return .zakefGadol }
        if m.contains(0x0597) { return .revia }
        if m.contains(0x059B) { return .tevir }
        if m.contains(0x059C) || m.contains(0x059D) || m.contains(0x059E) { return .geresh }
        if m.contains(0x05A1) || m.contains(0x059F) { return .pazer }
        if m.contains(0x05A0) { return .telishaGedolah }
        if m.contains(0x05A3), word.hasSuffix("׀") { return .legarmeh }  // munach + paseq
        return nil
    }

    /// A minor pausing trope, and the group it belongs to when that group follows.
    static func subordinate(_ word: String) -> (fits: Set<TropeGroup>, alone: TropeGroup)? {
        let m = Set(word.unicodeScalars.map(\.value))
        if m.contains(0x0596) { return ([.sofPasuk, .etnachta], .etnachta) }   // tipcha
        if m.contains(0x0599) || m.contains(0x059A) { return ([.katon], .katon) }   // pashta, yetiv
        if m.contains(0x05AE) || m.contains(0x0598) { return ([.segol], .segol) } // zarka
        return nil
    }
}

/// A displayable word in the vowels view.
struct TropeWord {
    var text: String          // pointed text as chanted (keri where it differs)
    var ketiv: String?        // shown small when the written form differs
    var readOnly: Bool = false // keri with no ketiv
    var notRead: Bool = false  // ketiv with no keri
    var group: TropeGroup? = nil
    var groupIndex: Int = -1   // words with the same index form one highlighted run
}

enum TropeLayout {
    enum Item { case word(TropeWord), petucha, setuma }

    /// Turns a verse's pieces into words and assigns each word its trope group.
    static func items(_ pieces: [Piece]) -> [Item] {
        var items: [Item] = []
        for p in pieces {
            switch p {
            case .text(let t):
                for w in t.split(whereSeparator: { $0 == " " || $0 == "\u{2009}" }) {
                    let word = String(w)
                    // A paseq (׀) stands between words; attach it to the previous one.
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
        // Walk backwards from the end of the verse: a major pausing trope opens
        // a new group; a minor one joins the group after it when it belongs
        // there (tipcha before etnachta or sof pasuk, pashta before zakef,
        // zarka before segol), otherwise opens its own; conjunctives join
        // whatever follows.
        var current: TropeGroup? = nil
        var index = 0
        for i in items.indices.reversed() {
            guard case .word(var w) = items[i], !w.notRead else { continue }
            if let g = TropeGroup.ending(w.text) {
                current = g; index += 1
            } else if let sub = TropeGroup.subordinate(w.text) {
                if current == nil || !sub.fits.contains(current!) { current = sub.alone; index += 1 }
            }
            w.group = current
            w.groupIndex = index
            items[i] = .word(w)
        }
        return items
    }
}
