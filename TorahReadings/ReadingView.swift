import SwiftUI

enum TextMode: String, CaseIterable, Identifiable {
    case trope = "Vowels", scroll = "Tikkun", english = "English"
    var id: String { rawValue }
}

struct ReadingView: View {
    let target: ReadingTarget

    @AppStorage("textMode") private var modeRaw = TextMode.trope.rawValue
    @AppStorage("fontSize") private var fontSize = 26.0
    @AppStorage("tropeColors") private var tropeColors = false
    @AppStorage("scrollVerseNumbers") private var scrollVerseNumbers = false
    @AppStorage("stamStyle") private var stamStyle = Fonts.stamAshkenaz

    @State private var verses: [VerseText] = []
    @State private var loadError: String?
    @State private var selectedVideo: String?
    @State private var showLegend = false

    private var mode: TextMode { TextMode(rawValue: modeRaw) ?? .trope }
    private var videoMatch: DataStore.VideoMatch { DataStore.shared.videos(for: target.passage) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if target.passage.isTorah { videoSection }
                Picker("Text", selection: $modeRaw) {
                    ForEach(availableModes) { Text($0.rawValue).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
                if mode == .trope { tropeToggle }
                textSection
                credits
            }
            .padding()
        }
        .navigationTitle(target.shabbat?.parsha ?? target.passage.book)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { fontSize = max(16, fontSize - 2) } label: { Image(systemName: "textformat.size.smaller") }
                    .accessibilityLabel("Smaller text")
                Button { fontSize = min(56, fontSize + 2) } label: { Image(systemName: "textformat.size.larger") }
                    .accessibilityLabel("Larger text")
            }
        }
        .task(id: target.id) { await load() }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .sheet(isPresented: $showLegend) { TropeLegend() }
    }

    private var availableModes: [TextMode] {
        target.passage.isTorah ? TextMode.allCases : [.trope, .english]
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let s = target.shabbat {
                HStack(alignment: .firstTextBaseline) {
                    Text(s.parsha).font(.title2.bold())
                    Spacer()
                    Text(s.parshaHe).font(.custom(Fonts.hebrew, size: 24))
                }
                Text("\(DateFormatter.longDay.string(from: s.day)) · \(s.hdate)")
                    .font(.subheadline).foregroundStyle(.secondary)
                if target.passage.isTorah {
                    Text("Triennial year \(s.cycleYear)").font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Text("\(target.slotLabel): \(target.passage.display)").font(.headline).padding(.top, 2)
            if let reason = target.reason {
                Label(reason, systemImage: "star").font(.subheadline).foregroundStyle(.orange)
            }
            if let note = target.note {
                Label(note, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(.orange)
            }
        }
    }

    // MARK: Video

    @ViewBuilder private var videoSection: some View {
        let match = videoMatch
        if match.choices.isEmpty {
            Label("No Tricks of the Trope video covers these verses.", systemImage: "video.slash")
                .font(.footnote).foregroundStyle(.secondary)
        } else {
            let current = selectedVideo ?? match.choices[0].video.id
            VStack(alignment: .leading, spacing: 8) {
                YouTubePlayer(videoID: current)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                if match.choices.count > 1 || match.choices.contains(where: { !$0.exact || $0.chazakAlternate != nil }) || !match.complete {
                    ForEach(match.choices) { c in
                        videoRow(c.video, current: current, note: c.exact ? nil : "covers \(c.video.range.display)")
                        if let alt = c.chazakAlternate { videoRow(alt, current: current, note: "with Chazak") }
                    }
                    if !match.complete {
                        Text("These videos don't cover every verse of this reading.")
                            .font(.footnote).foregroundStyle(.orange)
                    }
                }
                Link(destination: URL(string: "https://youtu.be/\(current)")!) {
                    Label("Open in YouTube", systemImage: "arrow.up.right.square")
                }.font(.footnote)
            }
            .onChange(of: target.id) { selectedVideo = nil }
        }
    }

    private func videoRow(_ v: Video, current: String, note: String?) -> some View {
        Button { selectedVideo = v.id } label: {
            HStack {
                Image(systemName: v.id == current ? "play.circle.fill" : "play.circle")
                VStack(alignment: .leading) {
                    Text(v.label).font(.subheadline)
                    if let note { Text(note).font(.caption).foregroundStyle(.secondary) }
                }
                Spacer()
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: Text

    private var tropeToggle: some View {
        HStack {
            Toggle("Color trope groups", isOn: $tropeColors)
            Button { showLegend = true } label: { Image(systemName: "info.circle") }
                .accessibilityLabel("Trope color key")
        }
        .font(.subheadline)
    }

    @ViewBuilder private var textSection: some View {
        if let loadError {
            VStack(alignment: .leading, spacing: 8) {
                Label(loadError, systemImage: "wifi.exclamationmark").foregroundStyle(.secondary)
                Button("Try again") { Task { await load() } }
            }
        } else if verses.isEmpty {
            ProgressView().frame(maxWidth: .infinity)
        } else {
            switch mode {
            case .trope:
                hebrew(Text(tropeString()), font: Fonts.hebrew)
            case .scroll:
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Picker("Script", selection: $stamStyle) {
                            Text("Ashkenazi").tag(Fonts.stamAshkenaz)
                            Text("Sefardi").tag(Fonts.stamSefarad)
                        }
                        .pickerStyle(.segmented)
                        .fixedSize()
                        Spacer()
                        Toggle("Verse numbers", isOn: $scrollVerseNumbers).fixedSize()
                    }
                    .font(.subheadline)
                    if target.passage.isTorah && ScrollLayout.shared.isAvailable {
                        TikkunView(passage: target.passage, fontName: Fonts.scroll(stamStyle),
                                   maxFontSize: fontSize, showVerseNumbers: scrollVerseNumbers)
                    } else {
                        hebrew(Text(scrollString()), font: Fonts.scroll(stamStyle))
                            .foregroundStyle(Color(red: 0.08, green: 0.07, blue: 0.06))
                            .padding(.horizontal, 18)
                            .padding(.vertical, 22)
                            .background(Color(red: 0.96, green: 0.92, blue: 0.83), in: RoundedRectangle(cornerRadius: 6))
                            .environment(\.colorScheme, .light)
                    }
                }
            case .english:
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(verses) { v in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("\(v.cv.chapter):\(v.cv.verse)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            Text(HebrewText.english(v.englishHTML)).font(.system(size: fontSize * 0.7))
                        }
                    }
                }
            }
        }
    }

    private func hebrew(_ text: Text, font: String) -> some View {
        text
            .font(.custom(font, size: fontSize))
            .lineSpacing(fontSize * 0.45)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .environment(\.layoutDirection, .rightToLeft)
            .textSelection(.enabled)
    }

    private func verseNumber(_ v: VerseText, first: Bool) -> AttributedString {
        let label = (first || v.cv.verse == 1)
            ? "\(HebrewText.numeral(v.cv.chapter)):\(HebrewText.numeral(v.cv.verse))"
            : HebrewText.numeral(v.cv.verse)
        var a = AttributedString(label + "\u{00A0}")
        a.font = Font.system(size: fontSize * 0.5, weight: .semibold)
        a.foregroundColor = Color.secondary
        return a
    }

    private func tropeString() -> AttributedString {
        var out = AttributedString()
        for (i, v) in verses.enumerated() {
            out += verseNumber(v, first: i == 0)
            let items = TropeLayout.items(HebrewText.pieces(v.hebrewHTML))
            for (j, item) in items.enumerated() {
                switch item {
                case .petucha: out += AttributedString("\n")
                case .setuma: out += AttributedString("\u{2003}\u{2003}\u{2003}")
                case .word(let w):
                    let highlight = tropeColors && !w.notRead ? w.group?.color : nil
                    var word = AttributedString(w.notRead ? "(\(w.text))" : w.text)
                    if w.notRead {
                        word.foregroundColor = Color.secondary
                    } else if let highlight {
                        word.backgroundColor = highlight
                        word.foregroundColor = Color.black
                    }
                    if w.ketiv != nil || w.readOnly { word.underlineStyle = Text.LineStyle.single }
                    out += word
                    if let k = w.ketiv {
                        var note = AttributedString("\u{00A0}(\(k))")
                        note.font = Font.system(size: fontSize * 0.5)
                        note.foregroundColor = highlight == nil ? Color.secondary : Color.black.opacity(0.6)
                        if let highlight { note.backgroundColor = highlight }
                        out += note
                    }
                    // The space joins the highlight only inside a group, so groups
                    // read as separate blocks.
                    var space = AttributedString(" ")
                    if let highlight, j + 1 < items.count, case .word(let next) = items[j + 1],
                       !next.notRead, next.groupIndex == w.groupIndex {
                        space.backgroundColor = highlight
                    }
                    out += space
                }
            }
        }
        return out
    }

    private func scrollString() -> AttributedString {
        var out = AttributedString()
        for (i, v) in verses.enumerated() {
            if scrollVerseNumbers { out += verseNumber(v, first: i == 0) }
            for piece in HebrewText.pieces(v.hebrewHTML) {
                switch piece {
                case .text(let t):
                    let s = HebrewText.scroll(t)
                    if !s.isEmpty { out += AttributedString(s + " ") }
                case .kq(let k, _):
                    if let k { out += AttributedString(HebrewText.scroll(k) + " ") }
                case .petucha: out += AttributedString("\n")
                case .setuma: out += AttributedString("\u{2003}\u{2003}\u{2003}")
                }
            }
        }
        return out
    }

    private var credits: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Text: Sefaria — Miqra according to the Masorah (CC BY-SA) and its English translation.")
            if target.passage.isTorah {
                Text("Readings: Hebcal.com triennial (CC BY 4.0). Videos: Tricks of the Trope – Total Torah, Cantor Arianne Brown, Adas Israel.")
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .padding(.top, 12)
    }

    private func load() async {
        loadError = nil
        do { verses = try await SefariaClient.shared.verses(for: target.passage) }
        catch { loadError = error.localizedDescription }
    }
}

struct TropeLegend: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Each trope group is highlighted as one block, the way it's taught and chanted. A group ends in a major pausing trope; the connecting tropes and the minor pausing trope before it (tipcha, pashta, zarka) belong to it.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(TropeGroup.allCases) { g in
                    HStack {
                        RoundedRectangle(cornerRadius: 3).fill(g.color).frame(width: 22, height: 14)
                        Text(g.name)
                    }
                }
                Section {
                    Text("Underlined words are read differently from how they're written (keri/ketiv); the written form is shown small after them.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Trope colors")
            .toolbar { Button("Done") { dismiss() } }
        }
    }
}
