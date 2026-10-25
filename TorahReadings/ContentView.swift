import SwiftUI

/// Opens straight to a reading. The menu (top left) switches readings or sets
/// up the sign-up sheet.
struct ContentView: View {
    @AppStorage("sheetURL") private var sheetURL = SignupSheet.defaultURL
    @AppStorage("readerNames") private var readerNames = SignupSheet.defaultName
    @AppStorage("autoOpen") private var autoOpen = true

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
        guard let s = DataStore.shared.upcomingShabbat, let a = s.aliyah("1") else { return nil }
        return .from(shabbat: s, aliyah: a)
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
        .sheet(isPresented: $showChooser) {
            ChooserView(current: target) { picked in open(picked) }
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
                    ForEach(s.aliyot, id: \.n) { a in
                        Button("\(a.label) · \(Passage(book: a.book, ranges: [a.range]).display)") {
                            open(.from(shabbat: s, aliyah: a))
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
    let onPick: (ReadingTarget) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var parsha: String
    @State private var yearChoice: Int         // 0 = this year (from Hebcal), else 1–3
    @State private var aliyah: String
    private let store = DataStore.shared

    /// Starts on the reading being shown, so stepping to the next aliyah of the
    /// same parsha is one tap. Falls back to this Shabbat's first aliyah.
    init(current: ReadingTarget?, onPick: @escaping (ReadingTarget) -> Void) {
        self.onPick = onPick
        let store = DataStore.shared
        if let s = current?.shabbat, store.parshaOrder.contains(s.parsha) {
            _parsha = State(initialValue: s.parsha)
            let key = s.aliyot.first { $0.label == current?.slotLabel }?.n
                ?? (current?.slotLabel == "Maftir" ? "M" : "1")
            _aliyah = State(initialValue: key)
            // Keep "This year" when the shown reading is the one it would pick.
            let thisYear = store.nextReading(of: s.parsha)
            _yearChoice = State(initialValue: thisYear?.date == s.date ? 0 : s.cycleYear)
        } else {
            _parsha = State(initialValue: store.upcomingShabbat?.parsha ?? "Bereshit")
            _aliyah = State(initialValue: "1")
            _yearChoice = State(initialValue: 0)
        }
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
                    Picker("Triennial year", selection: $yearChoice) {
                        Text("This year").tag(0)
                        Text("Year 1").tag(1)
                        Text("Year 2").tag(2)
                        Text("Year 3").tag(3)
                    }
                } footer: {
                    Text("“This year” uses Hebcal's triennial cycle for the next time the parsha is read.")
                }
                Section {
                    if let s = store.nextReading(of: parsha, cycleYear: yearChoice == 0 ? nil : yearChoice),
                       let a = s.aliyah(aliyah) {
                        Button {
                            onPick(.from(shabbat: s, aliyah: a))
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Open \(Passage(book: a.book, ranges: [a.range]).display)").font(.headline)
                                Text("\(s.day.formatted(date: .abbreviated, time: .omitted)) · triennial year \(s.cycleYear)\(a.reason.map { " · \($0)" } ?? "")")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        Text("Hebcal has no reading for that choice.").foregroundStyle(.secondary)
                    }
                }
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
