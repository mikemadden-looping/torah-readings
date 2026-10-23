import Foundation

/// A row on the shul's Google sign-up sheet with the reader's name on it.
struct Assignment: Identifiable, Hashable {
    let date: Date
    let parshaOnSheet: String
    let slot: String            // "1"…"7", "maf", "Haftara", "Alternate Haftara"
    let refOnSheet: String
    let signedUp: String

    var id: String { "\(DateFormatter.isoDay.string(from: date)) \(slot)" }

    /// Aliyah key in readings.json ("1"…"7", "M"), or nil for a haftarah.
    var aliyahKey: String? {
        if let n = Int(slot), (1...7).contains(n) { return String(n) }
        if slot.lowercased().hasPrefix("maf") { return "M" }
        return nil
    }
    var slotLabel: String {
        if let n = Int(slot) { return "Aliyah \(n)" }
        if slot.lowercased().hasPrefix("maf") { return "Maftir" }
        return slot
    }
}

enum SignupError: LocalizedError {
    case badURL, notShared, http(Int), noRows
    var errorDescription: String? {
        switch self {
        case .badURL: return "That doesn't look like a Google Sheets link."
        case .notShared: return "Google asked for a sign-in. The sheet needs General access set to “Anyone with the link.”"
        case .http(let c): return "Google Sheets returned an error (HTTP \(c))."
        case .noRows: return "The sheet doesn't have Date, Aliyah and Sign Up columns."
        }
    }
}

enum SignupSheet {
    static let defaultURL = ""
    static let defaultName = ""

    private static var cacheFile: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("signup.csv")
    }

    /// Reads the sheet as CSV (works for sheets shared with "Anyone with the link").
    /// Falls back to the last copy fetched if the network fails.
    static func assignments(sheetURL: String, names: String) async throws -> (rows: [Assignment], fromCache: Bool) {
        guard let csvURL = exportURL(sheetURL) else { throw SignupError.badURL }
        var fromCache = false
        let text: String
        do {
            let (data, response) = try await URLSession.shared.data(from: csvURL)
            let http = response as? HTTPURLResponse
            if let code = http?.statusCode, code != 200 { throw SignupError.http(code) }
            let body = String(decoding: data, as: UTF8.self)
            let type = http?.value(forHTTPHeaderField: "Content-Type") ?? ""
            if type.contains("text/html") || body.prefix(200).lowercased().contains("<!doctype html") { throw SignupError.notShared }
            text = body
            try? data.write(to: cacheFile)
        } catch let e as SignupError {
            throw e
        } catch {
            guard let cached = try? String(contentsOf: cacheFile, encoding: .utf8) else { throw error }
            text = cached
            fromCache = true
        }
        return (try parse(csv: text, names: names), fromCache)
    }

    /// ".../spreadsheets/d/<id>/edit#gid=123" → ".../spreadsheets/d/<id>/export?format=csv&gid=123"
    static func exportURL(_ s: String) -> URL? {
        guard let m = s.firstMatch(of: #/spreadsheets/d/([A-Za-z0-9_-]+)/#) else { return nil }
        var url = "https://docs.google.com/spreadsheets/d/\(m.1)/export?format=csv"
        if let g = s.firstMatch(of: #/[#?&]gid=(\d+)/#) { url += "&gid=\(g.1)" }
        return URL(string: url)
    }

    static func parse(csv: String, names: String) throws -> [Assignment] {
        let rows = parseCSV(csv)
        guard let headerIndex = rows.firstIndex(where: { row in
            let lower = row.map { $0.lowercased() }
            return lower.contains("date") && lower.contains(where: { $0.hasPrefix("sign") })
        }) else { throw SignupError.noRows }
        let header = rows[headerIndex].map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
        func col(_ pred: (String) -> Bool) -> Int? { header.firstIndex(where: pred) }
        guard let dateCol = col({ $0 == "date" }),
              let slotCol = col({ $0.hasPrefix("aliyah") }),
              let signCol = col({ $0.hasPrefix("sign") }) else { throw SignupError.noRows }
        let parshaCol = col { $0.hasPrefix("parash") || $0.hasPrefix("parsh") }
        let refCol = col { $0.contains("reading") }

        let wanted = names.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty }
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.calendar = Calendar(identifier: .gregorian)

        var out: [Assignment] = []
        for row in rows.dropFirst(headerIndex + 1) {
            func cell(_ i: Int?) -> String { i.flatMap { $0 < row.count ? row[$0] : nil }?.trimmingCharacters(in: .whitespaces) ?? "" }
            let who = cell(signCol)
            guard !who.isEmpty, wanted.contains(where: { who.lowercased().contains($0) }) else { continue }
            guard let date = parseDate(cell(dateCol), df) else { continue }
            let a = Assignment(date: date, parshaOnSheet: cell(parshaCol), slot: cell(slotCol),
                               refOnSheet: cell(refCol), signedUp: who)
            guard a.aliyahKey != nil else { continue }   // Torah readings only; skip haftarah rows
            out.append(a)
        }
        return out.sorted { $0.date < $1.date }
    }

    private static func parseDate(_ s: String, _ df: DateFormatter) -> Date? {
        for f in ["dd-MMM-yyyy", "d-MMM-yyyy", "M/d/yyyy", "yyyy-MM-dd", "MMMM d, yyyy", "MMM d, yyyy"] {
            df.dateFormat = f
            if let d = df.date(from: s) { return Calendar.current.startOfDay(for: d) }
        }
        return nil
    }

    /// Minimal RFC 4180 CSV parser (quoted fields, doubled quotes, newlines in quotes).
    static func parseCSV(_ text: String) -> [[String]] {
        var rows: [[String]] = [], row: [String] = [], field = ""
        var inQuotes = false
        var it = text.makeIterator()
        var pending: Character? = nil
        while let c = pending ?? it.next() {
            pending = nil
            if inQuotes {
                if c == "\"" {
                    if let n = it.next() { if n == "\"" { field.append("\"") } else { inQuotes = false; pending = n } }
                    else { inQuotes = false }
                } else { field.append(c) }
            } else {
                switch c {
                case "\"": inQuotes = true
                case ",": row.append(field); field = ""
                case "\n", "\r\n": row.append(field); rows.append(row); row = []; field = ""
                case "\r": break
                default: field.append(c)
                }
            }
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        return rows
    }
}
