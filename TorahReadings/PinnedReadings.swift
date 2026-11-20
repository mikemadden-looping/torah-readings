import Foundation

/// A reading the user pinned to "My readings" by hand: one assigned to them
/// that isn't on the sign-up sheet. Stored on the device, not on the sheet.
struct PinnedReading: Codable, Hashable, Identifiable {
    let date: String          // Shabbat date, yyyy-MM-dd (matches readings.json)
    let n: String             // "1"…"7" or "M"
    var fullParsha = false

    var id: String { "\(date) \(n) \(fullParsha ? "full" : "tri")" }
    var day: Date { DateFormatter.isoDay.date(from: date) ?? .distantPast }
    var slotLabel: String { n == "M" ? "Maftir" : "Aliyah \(n)" }

    init(date: String, n: String, fullParsha: Bool) {
        self.date = date; self.n = n; self.fullParsha = fullParsha
    }

    /// The pin for what's on screen, if it's a Shabbat aliyah.
    init?(target: ReadingTarget) {
        guard let s = target.shabbat, target.passage.isTorah else { return nil }
        let n = s.readings(fullParsha: target.fullParsha).first { $0.label == target.slotLabel }?.n
            ?? (target.slotLabel == "Maftir" ? "M" : nil)
        guard let n else { return nil }
        self.init(date: s.date, n: n, fullParsha: target.fullParsha)
    }

    func target(store: DataStore = .shared) -> ReadingTarget? {
        guard let s = store.shabbat(on: day), let a = s.aliyah(n, fullParsha: fullParsha) else { return nil }
        return .from(shabbat: s, aliyah: a, fullParsha: fullParsha)
    }
}

enum PinnedReadings {
    static let key = "pinnedReadings"

    static func decode(_ raw: String) -> [PinnedReading] {
        guard let data = raw.data(using: .utf8),
              let pins = try? JSONDecoder().decode([PinnedReading].self, from: data) else { return [] }
        return pins
    }

    static func encode(_ pins: [PinnedReading]) -> String {
        let sorted = pins.sorted { ($0.date, $0.n) < ($1.date, $1.n) }
        guard let data = try? JSONEncoder().encode(sorted) else { return "[]" }
        return String(decoding: data, as: UTF8.self)
    }
}

/// One row in "My readings": from the sign-up sheet, or pinned by hand.
enum MyReading: Identifiable {
    case sheet(Assignment)
    case pinned(PinnedReading)

    var id: String {
        switch self {
        case .sheet(let a): return "sheet \(a.id)"
        case .pinned(let p): return "pin \(p.id)"
        }
    }
    var date: Date {
        switch self {
        case .sheet(let a): return a.date
        case .pinned(let p): return p.day
        }
    }
    var target: ReadingTarget? {
        switch self {
        case .sheet(let a): return .from(assignment: a)
        case .pinned(let p): return p.target()
        }
    }
    var title: String {
        let day = date.formatted(.dateTime.month(.abbreviated).day())
        switch self {
        case .sheet(let a):
            return "\(day) · \(a.parshaOnSheet) · \(a.slotLabel)"
        case .pinned(let p):
            let parsha = DataStore.shared.shabbat(on: p.day)?.parsha ?? ""
            return "\(day) · \(parsha) · \(p.slotLabel)\(p.fullParsha ? " (full)" : "")"
        }
    }
    var isPinned: Bool { if case .pinned = self { return true } else { return false } }
}
