import SwiftUI

/// Opens straight to a reading. The menu (top left) switches readings or sets
/// up the sign-up sheet.
struct ContentView: View {
    @AppStorage("sheetURL") private var sheetURL = SignupSheet.defaultURL
    @AppStorage("readerNames") private var readerNames = SignupSheet.defaultName
    @AppStorage("autoOpen") private var autoOpen = true
    @AppStorage("fullParsha") private var fullParsha = false

    @State private var target: ReadingTarget? = ContentView.thisWeeksFirst
    @State private var userPicked = false
    @State private var assignments: [Assignment] = []
    @State private var sheetError: String?
    @State private var sheetFromCache = false
    @State private var showChooser = false
    @State private var showSheetSettings = false

    private let store = DataStore.shared
    private var today: Date { Calendar.current.startOfDay(for: Date()) }
    private var upcoming: [Assignment] { assignments.filter { $0.date >= today } }
    private var sheetConfigured: Bool {
        !sheetURL.trimmingCharacters(in: .whitespaces).isEmpty && !readerNames.trimmingCharacters(in: .whitespaces).isEmpty
    }

    static var thisWeeksFirst: ReadingTarget? {
        let full = UserDefaults.standard.bool(forKey: "fullParsha")
        guard let s = DataStore.shared.upcomingShabbat, let a = s.aliyah("1", fullParsha: full) ?? s.aliyah("1") else { return nil }
        return .from(shabbat: s, aliyah: a, fullParsha: full && s.full?.isEmpty == false)
    }

    var body: some View {
        NavigationStack {
            Group {
                if let target { ReadingView(target: target).id(target.id) }
                else { ContentUnavailableView("No reading", systemImage: "book.closed") }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { menu }
            }
        }
        .task { await loadSheet() }
        .onChange(of: fullParsha) { _, full in
            // Keep the same Shabbat and aliyah, in the newly chosen cycle.
            if let t = target?.switched(toFullParsha: full) { open(t) }
        }
        .sheet(isPresented: $showChooser) {
            ChooserView(current: target, fullParsha: fullParsha) { picked in open(picked) }
        }
        .sheet(isPresented: $showSheetSettings, onDismiss: { Task { await loadSheet() } }) {
            SignupSettingsView(sheetURL: $sheetURL, readerNames: $readerNames, autoOpen: $autoOpen)
        }
    }

    private func open(_ t: ReadingTarget) {
        userPicked = true
        target = t
    }

    // MARK: Menu

    private var menu: some View {
        Menu {
            Button { showChooser = true } label: { Label("Choose parsha and aliyah…", systemImage: "book") }

            if let s = store.upcomingShabbat {
                Menu {
                    ForEach(s.readings(fullParsha: fullParsha), id: \.n) { a in
                        Button("\(a.label) · \(Passage(book: a.book, ranges: [a.range]).display)") {
                            open(.from(shabbat: s, aliyah: a, fullParsha: fullParsha))
                        }
                    }
                } label: { Label("This Shabbat: \(s.parsha)", systemImage: "calendar") }
            }

            if sheetConfigured {
                Section(sheetFromCache ? "My readings (offline copy)" : "My readings") {
                    if let sheetError { Text(sheetError) }
                    if upcoming.isEmpty && sheetError == nil { Text("None upcoming") }
                    ForEach(upcoming) { a in
                        if let t = ReadingTarget.from(assignment: a) {
                            Button("\(a.date.formatted(.dateTime.month(.abbreviated).day())) · \(a.parshaOnSheet) · \(a.slotLabel)") { open(t) }
                        }
                    }
                }
            }

            Section {
                Picker(selection: $fullParsha) {
                    Text("Triennial cycle").tag(false)
                    Text("Full parsha").tag(true)
                } label: {
                    Label("Reading", systemImage: "arrow.triangle.2.circlepath")
                }
                .pickerStyle(.menu)
            }

            Section {
                Button { showSheetSettings = true } label: {
                    Label(sheetConfigured ? "Sign-up sheet…" : "Add sign-up sheet…", systemImage: "tablecells")
                }
            }
        } label: {
            Image(systemName: "line.3.horizontal")
        }
        .accessibilityLabel("Menu")
    }

    // MARK: Sheet

    private func loadSheet() async {
        guard sheetConfigured else { assignments = []; sheetError = nil; return }
        do {
            let result = try await SignupSheet.assignments(sheetURL: sheetURL, names: readerNames)
            assignments = result.rows
            sheetFromCache = result.fromCache
            sheetError = nil
        } catch {
            sheetError = error.localizedDescription
        }
        if autoOpen, !userPicked, let next = upcoming.first, let t = ReadingTarget.from(assignment: next) {
            target = t
        }
    }
}

/// Pick any parsha and aliyah; Hebcal supplies this year's verses.
struct ChooserView: View {
    let fullParsha: Bool
    let onPick: (ReadingTarget) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var parsha: String
    @State private var yearChoice: Int         // triennial cycle year, 1–3
    @State private var aliyah: String
    private let store = DataStore.shared

    /// Starts on the reading being shown, so stepping to the next aliyah of the
    /// same parsha is one tap. Falls back to this Shabbat's first aliyah.
    init(current: ReadingTarget?, fullParsha: Bool, onPick: @escaping (ReadingTarget) -> Void) {
        self.fullParsha = fullParsha
        self.onPick = onPick
        let store = DataStore.shared
        if let s = current?.shabbat, store.parshaOrder.contains(s.parsha) {
            _parsha = State(initialValue: s.parsha)
            let key = s.readings(fullParsha: current?.fullParsha ?? false).first { $0.label == current?.slotLabel }?.n
                ?? (current?.slotLabel == "Maftir" ? "M" : "1")
            _aliyah = State(initialValue: key)
            _yearChoice = State(initialValue: s.cycleYear)
        } else {
            _parsha = State(initialValue: store.upcomingShabbat?.parsha ?? "Bereshit")
            _aliyah = State(initialValue: "1")
            let p = store.upcomingShabbat?.parsha ?? "Bereshit"
            _yearChoice = State(initialValue: store.nextReading(of: p)?.cycleYear ?? 1)
        }
    }

    /// The three triennial years in the order they come up for this parsha,
    /// labeled "This year", "Next year", then the calendar year (e.g. "2028").
    private var yearOptions: [(cycleYear: Int, label: String)] {
        let today = Calendar.current.startOfDay(for: Date())
        var seen = Set<Int>()
        let upcoming = store.readings.shabbatot
            .filter { $0.parsha == parsha && $0.day >= today && seen.insert($0.cycleYear).inserted }
        var options = upcoming.enumerated().map { i, s -> (cycleYear: Int, label: String) in
            let label = i == 0 ? "This year" : i == 1 ? "Next year"
                : String(Calendar.current.component(.year, from: s.day))
            return (s.cycleYear, label)
        }
        // Years past the end of the bundled calendar still get a choice.
        for y in 1...3 where !options.contains(where: { $0.cycleYear == y }) {
            options.append((y, "Triennial year \(y)"))
        }
        return options
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Parsha", selection: $parsha) {
                        ForEach(store.parshaOrder, id: \.self) { Text($0).tag($0) }
                    }
                    Picker("Aliyah", selection: $aliyah) {
                        ForEach(["1", "2", "3", "4", "5", "6", "7"], id: \.self) { Text("Aliyah \($0)").tag($0) }
                        Text("Maftir").tag("M")
                    }
                    if !fullParsha {
                        Picker("When", selection: $yearChoice) {
                            ForEach(yearOptions, id: \.cycleYear) { Text($0.label).tag($0.cycleYear) }
                        }
                    }
                } footer: {
                    Text(fullParsha
                         ? "Full parsha: the whole parsha's aliyot, as read the next time it comes up. No videos, since they follow the triennial aliyot. Switch cycles in the menu."
                         : "“This year” is the next time the parsha is read. Each year reads a different third of it (Hebcal's triennial cycle).")
                }
                Section {
                    if let s = store.nextReading(of: parsha, cycleYear: fullParsha ? nil : yearChoice),
                       let a = s.aliyah(aliyah, fullParsha: fullParsha) {
                        Button {
                            onPick(.from(shabbat: s, aliyah: a, fullParsha: fullParsha))
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Open \(Passage(book: a.book, ranges: [a.range]).display)").font(.headline)
                                Text("\(s.day.formatted(date: .abbreviated, time: .omitted)) · \(fullParsha ? "full parsha" : "triennial year \(s.cycleYear)")\(a.reason.map { " · \($0)" } ?? "")")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        Text("Hebcal has no reading for that choice.").foregroundStyle(.secondary)
                    }
                }
            }
            .onChange(of: parsha) { _, p in
                yearChoice = store.nextReading(of: p)?.cycleYear ?? yearChoice
            }
            .navigationTitle("Choose a reading")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Cancel") { dismiss() } }
        }
    }
}

struct SignupSettingsView: View {
    @Binding var sheetURL: String
    @Binding var readerNames: String
    @Binding var autoOpen: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $readerNames).autocorrectionDisabled()
                } header: {
                    Text("Your name on the sheet")
                } footer: {
                    Text("Separate several spellings with commas, e.g. “Sam Cohen, Samuel Cohen”.")
                }
                Section {
                    TextField("Google Sheets link", text: $sheetURL, axis: .vertical)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                } header: {
                    Text("Sign-up sheet")
                } footer: {
                    Text("The sheet's General access must be “Anyone with the link.” It needs Date, Aliyah and Sign Up columns. Your readings then appear in the menu.")
                }
                Section {
                    Toggle("Open my next reading at launch", isOn: $autoOpen)
                } footer: {
                    Text("Otherwise the app opens to this Shabbat's first aliyah.")
                }
            }
            .navigationTitle("Sign-up sheet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Done") { dismiss() } }
        }
    }
}
