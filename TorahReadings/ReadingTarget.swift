import Foundation

/// Everything the reading screen needs: which verses, and where they came from.
struct ReadingTarget: Hashable, Identifiable {
    let passage: Passage
    let shabbat: Shabbat?
    let slotLabel: String        // "Aliyah 1", "Maftir", "Haftara"
    let reason: String?          // special maftir, from Hebcal or the sheet
    let note: String?            // e.g. the sheet and Hebcal disagree

    var id: String { "\(shabbat?.date ?? "") \(slotLabel) \(passage.id)" }

    static func from(shabbat: Shabbat, aliyah: Aliyah) -> ReadingTarget {
        ReadingTarget(passage: Passage(book: aliyah.book, ranges: [aliyah.range]),
                      shabbat: shabbat, slotLabel: aliyah.label, reason: aliyah.reason, note: nil)
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
