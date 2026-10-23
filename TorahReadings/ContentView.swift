import SwiftUI

struct ContentView: View {
    @AppStorage("sheetURL") private var sheetURL = SignupSheet.defaultURL
    @AppStorage("readerNames") private var readerNames = SignupSheet.defaultName
    @AppStorage("autoOpen") private var autoOpen = true

    @State private var path: [ReadingTarget] = []
    @State private var assignments: [Assignment] = []
    @State private var sheetError: String?
    @State private var sheetFromCache = false
    @State private var loadingSheet = false
    @State private var didAutoOpen = false
    @State private var showSettings = false

    // Manual picker
    @State private var parsha: String = DataStore.shared.upcomingShabbat?.parsha ?? "Bereshit"
    @State private var yearChoice = 0          // 0 = this year (from Hebcal), else 1–3
    @State private var aliyah = "1"

    private let store = DataStore.shared
    private var today: Date { Calendar.current.startOfDay(for: Date()) }
    private var upcoming: [Assignment] { assignments.filter { $0.date >= today } }
    private var past: [Assignment] { assignments.filter { $0.date < today }.reversed() }
    private var sheetConfigured: Bool {
        !sheetURL.trimmingCharacters(in: .whitespaces).isEmpty && !readerNames.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                myReadings
                thisShabbat
                chooser
            }
            .navigationTitle("Torah Readings")
            .toolbar {
                Button { showSettings = true } label: { Image(systemName: "gearshape") }
                    .accessibilityLabel("Settings")
            }
            .navigationDestination(for: ReadingTarget.self) { ReadingView(target: $0) }
            .refreshable { await loadSheet() }
            .task { await loadSheet() }
            .sheet(isPresented: $showSettings, onDismiss: { Task { await loadSheet() } }) {
                SettingsView(sheetURL: $sheetURL, readerNames: $readerNames, autoOpen: $autoOpen)
            }
        }
    }

    // MARK: Sections

    @ViewBuilder private var myReadings: some View {
        Section {
            if !sheetConfigured {
                Button { showSettings = true } label: {
                    Label("Add your shul's sign-up sheet and your name to see your readings here", systemImage: "tablecells")
                }
            }
            if loadingSheet && assignments.isEmpty {
                HStack { ProgressView(); Text("Checking the sign-up sheet…").foregroundStyle(.secondary) }
            }
            if let sheetError {
                Label(sheetError, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(.orange)
            }
            if sheetConfigured && !loadingSheet && sheetError == nil && upcoming.isEmpty {
                Text("You're not signed up for any upcoming readings.").foregroundStyle(.secondary)
            }
            ForEach(upcoming) { assignmentRow($0) }
            if !past.isEmpty {
                DisclosureGroup("Past readings (\(past.count))") {
                    ForEach(past) { assignmentRow($0) }
                }
            }
        } header: {
            Text("My readings")
        } footer: {
            if sheetFromCache { Text("Offline — showing the sign-up sheet as of the last check.") }
        }
    }

    private func assignmentRow(_ a: Assignment) -> some View {
        let target = ReadingTarget.from(assignment: a)
        return NavigationLink(value: target) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(a.date.formatted(.dateTime.weekday(.abbreviated).month().day().year())) · \(a.parshaOnSheet)")
                    .font(.headline)
                Text("\(a.slotLabel)\(target.map { ": \($0.passage.display)" } ?? "")")
                    .font(.subheadline)
                if target == nil {
                    Text("Couldn't work out the verses for this row.").font(.caption).foregroundStyle(.orange)
                }
            }
        }
        .disabled(target == nil)
    }

    @ViewBuilder private var thisShabbat: some View {
        if let s = store.upcomingShabbat {
            Section("This Shabbat — \(s.parsha), year \(s.cycleYear)") {
                ForEach(s.aliyot, id: \.n) { a in
                    NavigationLink(value: ReadingTarget.from(shabbat: s, aliyah: a)) {
                        HStack {
                            Text(a.label)
                            Spacer()
                            Text(Passage(book: a.book, ranges: [a.range]).display)
                                .foregroundStyle(.secondary).font(.subheadline)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private var chooser: some View {
        Section {
            Picker("Parsha", selection: $parsha) {
                ForEach(store.parshaOrder, id: \.self) { Text($0).tag($0) }
            }
            Picker("Triennial year", selection: $yearChoice) {
                Text("This year").tag(0)
                Text("Year 1").tag(1)
                Text("Year 2").tag(2)
                Text("Year 3").tag(3)
            }
            Picker("Aliyah", selection: $aliyah) {
                ForEach(["1", "2", "3", "4", "5", "6", "7"], id: \.self) { Text("Aliyah \($0)").tag($0) }
                Text("Maftir").tag("M")
            }
            if let s = store.nextReading(of: parsha, cycleYear: yearChoice == 0 ? nil : yearChoice),
               let a = s.aliyah(aliyah) {
                NavigationLink(value: ReadingTarget.from(shabbat: s, aliyah: a)) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Open \(Passage(book: a.book, ranges: [a.range]).display)").font(.headline)
                        Text("\(s.day.formatted(date: .abbreviated, time: .omitted)) · triennial year \(s.cycleYear)\(a.reason.map { " · \($0)" } ?? "")")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("Hebcal has no reading for that choice.").foregroundStyle(.secondary)
            }
        } header: {
            Text("Choose a reading")
        } footer: {
            Text("“This year” uses Hebcal's triennial cycle for the next time the parsha is read.")
        }
    }

    // MARK: Sheet

    private func loadSheet() async {
        guard sheetConfigured else { assignments = []; sheetError = nil; return }
        loadingSheet = true
        defer { loadingSheet = false }
        do {
            let result = try await SignupSheet.assignments(sheetURL: sheetURL, names: readerNames)
            assignments = result.rows
            sheetFromCache = result.fromCache
            sheetError = nil
        } catch {
            sheetError = error.localizedDescription
        }
        if autoOpen, !didAutoOpen, path.isEmpty, let next = upcoming.first, let target = ReadingTarget.from(assignment: next) {
            didAutoOpen = true
            path = [target]
        }
    }
}

struct SettingsView: View {
    @Binding var sheetURL: String
    @Binding var readerNames: String
    @Binding var autoOpen: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Google Sheets link", text: $sheetURL, axis: .vertical)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                } header: {
                    Text("Sign-up sheet")
                } footer: {
                    Text("The sheet's General access must be “Anyone with the link.” It needs Date, Aliyah and Sign Up columns.")
                }
                Section {
                    TextField("Name", text: $readerNames).autocorrectionDisabled()
                } header: {
                    Text("Your name on the sheet")
                } footer: {
                    Text("Separate several spellings with commas, e.g. “Sam Cohen, Samuel Cohen”.")
                }
                Section {
                    Toggle("Open my next reading at launch", isOn: $autoOpen)
                }
            }
            .navigationTitle("Settings")
            .toolbar { Button("Done") { dismiss() } }
        }
    }
}
