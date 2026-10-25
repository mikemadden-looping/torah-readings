import Foundation

/// Everything the reading screen needs: which verses, and where they came from.
struct ReadingTarget: Hashable, Identifiable {
    let passage: Passage
    let shabbat: Shabbat?
    let slotLabel: String        // "Aliyah 1", "Maftir", "Haftara"
    let reason: String?          // special maftir, from Hebcal or the sheet
    let note: String?            // e.g. the sheet and Hebcal disagree
    var fullParsha = false       // full-parsha aliyah rather than triennial

    var id: String { "\(shabbat?.date ?? "") \(slotLabel) \(passage.id)" }

    /// "Full parsha" or "Triennial year 2", for headers.
    var cycleLabel: String? {
        guard let s = shabbat, passage.isTorah else { return nil }
        return fullParsha ? "Full parsha" : "Triennial year \(s.cycleYear)"
    }

    static func from(shabbat: Shabbat, aliyah: Aliyah, fullParsha: Bool = false) -> ReadingTarget {
        ReadingTarget(passage: Passage(book: aliyah.book, ranges: [aliyah.range]),
                      shabbat: shabbat, slotLabel: aliyah.label, reason: aliyah.reason, note: nil,
                      fullParsha: fullParsha)
    }

    /// The same slot (e.g. Aliyah 4) of the same Shabbat, in the other cycle.
    func switched(toFullParsha full: Bool) -> ReadingTarget? {
        guard let s = shabbat, full != fullParsha else { return nil }
        let n = s.readings(fullParsha: fullParsha).first { $0.label == slotLabel }?.n
            ?? (slotLabel == "Maftir" ? "M" : nil)
        guard let n, let a = s.aliyah(n, fullParsha: full) else { return nil }
        return .from(shabbat: s, aliyah: a, fullParsha: full)
    }

    static func from(assignment a: Assignment, store: DataStore = .shared) -> ReadingTarget? {
        let shabbat = store.shabbat(on: a.date)
        let sheetPassage = Passage.parse(a.refOnSheet)
        let sheetReason = a.refOnSheet.split(separator: "|").dropFirst().first.map {
            $0.trimmingCharacters(in: .whitespaces)
        }

        if let key = a.aliyahKey, let shabbat, let aliyah = shabbat.aliyah(key) {
            let hebcal = Passage(book: aliyah.book, ranges: [aliyah.range])
            if let sheetPassage, sheetPassage != hebcal {
                return ReadingTarget(passage: sheetPassage, shabbat: shabbat, slotLabel: a.slotLabel,
                                     reason: sheetReason ?? aliyah.reason,
                                     note: "The sign-up sheet lists \(sheetPassage.display); Hebcal's triennial reading is \(hebcal.display). Showing the sheet's verses.")
            }
            return ReadingTarget(passage: hebcal, shabbat: shabbat, slotLabel: a.slotLabel,
                                 reason: aliyah.reason ?? sheetReason, note: nil)
        }
        guard let sheetPassage else { return nil }
        return ReadingTarget(passage: sheetPassage, shabbat: shabbat, slotLabel: a.slotLabel,
                             reason: sheetReason, note: nil)
    }
}
