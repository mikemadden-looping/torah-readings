import SwiftUI
import UIKit
import PDFKit

/// Builds a US-letter PDF of one reading: the vowels-and-trope text (optionally
/// colored by trope group) and the Tikkun lines as they fall in the scroll.
enum ReadingPDF {
    struct Options: Equatable {
        enum Mode: String, CaseIterable { case vowels = "Vowels", tikkun = "Tikkun" }
        var mode: Mode = .vowels
        var colors = false
        var vowelSize: CGFloat = 20
        var stamFont = Fonts.stamAshkenaz
    }

    static let page = CGRect(x: 0, y: 0, width: 612, height: 792)   // 8.5 × 11 in
    static let margin: CGFloat = 54                                   // 0.75 in
    static var content: CGRect { page.insetBy(dx: margin, dy: margin) }

    static func make(target: ReadingTarget, verses: [VerseText], tikkun: [TikkunView.TikkunLine]?, options: Options) -> Data {
        let renderer = UIGraphicsPDFRenderer(bounds: page)
        return renderer.pdfData { ctx in
            var pageNumber = 0
            func newPage() {
                ctx.beginPage()
                pageNumber += 1
                let footer = "\(target.shabbat?.parsha ?? target.passage.book) · \(target.slotLabel) · page \(pageNumber)"
                footer.draw(at: CGPoint(x: margin, y: page.height - margin + 18),
                            withAttributes: [.font: UIFont.systemFont(ofSize: 8), .foregroundColor: UIColor.gray])
            }
            newPage()
            var y = drawHeader(target: target, top: content.minY)

            if options.mode == .vowels {
                y = sectionTitle("Vowels and trope", at: y)
                let text = vowelsText(verses, options: options)
                y = drawFlowing(text, from: y, newPage: newPage)
            }
            if options.mode == .tikkun, let tikkun, !tikkun.isEmpty {
                y = sectionTitle("Tikkun", at: y)
                drawTikkun(tikkun, fontName: Fonts.scroll(options.stamFont), from: y, newPage: newPage)
            }
        }
    }

    // MARK: Header

    private static func drawHeader(target: ReadingTarget, top: CGFloat) -> CGFloat {
        var y = top
        let title = "\(target.shabbat?.parsha ?? target.passage.book) — \(target.slotLabel)"
        title.draw(at: CGPoint(x: margin, y: y), withAttributes: [.font: UIFont.systemFont(ofSize: 18, weight: .semibold)])
        if let s = target.shabbat {
            let he = s.parshaHe as NSString
            let f = UIFont(name: Fonts.hebrew, size: 18) ?? .systemFont(ofSize: 18)
            let w = he.size(withAttributes: [.font: f]).width
            he.draw(at: CGPoint(x: content.maxX - w, y: y - 2), withAttributes: [.font: f])
        }
        y += 26
        var sub = target.passage.display
        if let s = target.shabbat {
            sub += " · \(DateFormatter.longDay.string(from: s.day)) · \(s.hdate)"
            if let cycle = target.cycleLabel { sub += " · \(cycle)" }
        }
        if let r = target.reason { sub += " · \(r)" }
        sub.draw(in: CGRect(x: margin, y: y, width: content.width, height: 30),
                 withAttributes: [.font: UIFont.systemFont(ofSize: 10), .foregroundColor: UIColor.darkGray])
        return y + 26
    }

    private static func sectionTitle(_ s: String, at y: CGFloat) -> CGFloat {
        s.draw(at: CGPoint(x: margin, y: y), withAttributes: [.font: UIFont.systemFont(ofSize: 11, weight: .semibold), .foregroundColor: UIColor.gray])
        return y + 20
    }

    // MARK: Vowels

    private static func vowelsText(_ verses: [VerseText], options: Options) -> NSAttributedString {
        let font = UIFont(name: Fonts.hebrew, size: options.vowelSize) ?? .systemFont(ofSize: options.vowelSize)
        let small = UIFont.systemFont(ofSize: options.vowelSize * 0.45, weight: .semibold)
        let para = NSMutableParagraphStyle()
        para.baseWritingDirection = .rightToLeft
        para.alignment = .natural
        para.lineSpacing = options.vowelSize * 0.55
        let base: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.black, .paragraphStyle: para]
        let out = NSMutableAttributedString()
        for (i, v) in verses.enumerated() {
            let n = (i == 0 || v.cv.verse == 1)
                ? "\(HebrewText.numeral(v.cv.chapter)):\(HebrewText.numeral(v.cv.verse))" : HebrewText.numeral(v.cv.verse)
            out.append(NSAttributedString(string: n + "\u{00A0}", attributes: base.merging([.font: small, .foregroundColor: UIColor.gray]) { $1 }))
            let items = TropeLayout.items(HebrewText.pieces(v.hebrewHTML))
            for (j, item) in items.enumerated() {
                switch item {
                case .petucha: out.append(NSAttributedString(string: "\n", attributes: base))
                case .setuma: out.append(NSAttributedString(string: "\u{2003}\u{2003}\u{2003}", attributes: base))
                case .word(let w):
                    var a = base
                    let hl: UIColor? = options.colors && !w.notRead ? w.group.map { UIColor($0.color) } : nil
                    if w.notRead { a[.foregroundColor] = UIColor.gray }
                    if let hl { a[.backgroundColor] = hl }
                    if w.ketiv != nil || w.readOnly { a[.underlineStyle] = NSUnderlineStyle.single.rawValue }
                    out.append(NSAttributedString(string: w.notRead ? "(\(w.text))" : w.text, attributes: a))
                    if let k = w.ketiv {
                        var na = base; na[.font] = UIFont.systemFont(ofSize: options.vowelSize * 0.45); na[.foregroundColor] = UIColor.darkGray
                        if let hl { na[.backgroundColor] = hl }
                        out.append(NSAttributedString(string: "\u{00A0}(\(k))", attributes: na))
                    }
                    var sa = base
                    if let hl, j + 1 < items.count, case .word(let next) = items[j + 1], !next.notRead, next.groupIndex == w.groupIndex {
                        sa[.backgroundColor] = hl
                    }
                    out.append(NSAttributedString(string: " ", attributes: sa))
                }
            }
        }
        return out
    }

    /// Lays text out across as many pages as it needs.
    private static func drawFlowing(_ text: NSAttributedString, from top: CGFloat, newPage: () -> Void) -> CGFloat {
        let storage = NSTextStorage(attributedString: text)
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        var y = top
        var glyphStart = 0
        let totalGlyphs = { layout.numberOfGlyphs }
        while true {
            let container = NSTextContainer(size: CGSize(width: content.width, height: content.maxY - y))
            container.lineFragmentPadding = 0
            layout.addTextContainer(container)
            let range = layout.glyphRange(for: container)
            let origin = CGPoint(x: content.minX, y: y)
            layout.drawBackground(forGlyphRange: range, at: origin)
            layout.drawGlyphs(forGlyphRange: range, at: origin)
            let used = layout.usedRect(for: container)
            glyphStart = NSMaxRange(range)
            if glyphStart >= totalGlyphs() || range.length == 0 { return y + used.height }
            newPage(); y = content.minY
        }
    }

    private static func drawLegend(groupsIn verses: [VerseText], at top: CGFloat, newPage: () -> Void) -> CGFloat {
        var used = Set<TropeGroup>()
        for v in verses {
            for case .word(let w) in TropeLayout.items(HebrewText.pieces(v.hebrewHTML)) { if let g = w.group { used.insert(g) } }
        }
        let groups = TropeGroup.allCases.filter(used.contains)
        var y = top
        if y + CGFloat(groups.count) * 14 > content.maxY { newPage(); y = content.minY }
        for g in groups {
            UIColor(g.color).setFill()
            UIBezierPath(roundedRect: CGRect(x: content.minX, y: y + 2, width: 18, height: 9), cornerRadius: 2).fill()
            g.name.draw(at: CGPoint(x: content.minX + 24, y: y), withAttributes: [.font: UIFont.systemFont(ofSize: 9), .foregroundColor: UIColor.darkGray])
            y += 14
        }
        return y
    }

    // MARK: Tikkun

    private static func drawTikkun(_ lines: [TikkunView.TikkunLine], fontName: String, from top: CGFloat, newPage: () -> Void) {
        let probe = UIFont(name: fontName, size: 20) ?? .systemFont(ofSize: 20)
        var widest: CGFloat = 1
        for l in lines {
            let w = l.words.reduce(CGFloat(0)) { $0 + ($1.text as NSString).size(withAttributes: [.font: probe]).width }
            widest = max(widest, w + CGFloat(max(0, l.words.count - 1)) * 6)
        }
        let size = min(30, 20 * content.width / widest)
        let font = UIFont(name: fontName, size: size) ?? .systemFont(ofSize: size)
        let lineHeight = size * 1.75
        let ink = UIColor(red: 0.08, green: 0.07, blue: 0.06, alpha: 1)
        var y = top
        for (i, l) in lines.enumerated() {
            if i > 0, l.blankBefore > 0 { y += CGFloat(l.blankBefore) * lineHeight }
            let newColumn = i == 0 || l.column != lines[i - 1].column
            if y + lineHeight + (newColumn ? 14 : 0) > content.maxY { newPage(); y = content.minY }
            if newColumn {
                let label = "Column \(l.column) · line \(l.lineInColumn)" as NSString
                let a: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 8), .foregroundColor: UIColor.gray]
                label.draw(at: CGPoint(x: content.maxX - label.size(withAttributes: a).width, y: y), withAttributes: a)
                y += 14
            }
            let widths = l.words.map { ($0.text as NSString).size(withAttributes: [.font: font]).width }
            let gapsCount = max(0, l.words.count - 1)
            let normalGap = size * 0.35
            let setumaIndex = l.words.dropLast().firstIndex(where: \.closedBreakAfter)
            let slack = content.width - widths.reduce(0, +) - CGFloat(gapsCount) * normalGap
            var x = content.maxX
            for (j, w) in l.words.enumerated() {
                let color = w.inPassage ? ink : ink.withAlphaComponent(0.25)
                (w.text as NSString).draw(at: CGPoint(x: x - widths[j], y: y), withAttributes: [.font: font, .foregroundColor: color])
                x -= widths[j]
                if j < gapsCount {
                    var gap = normalGap
                    if let setumaIndex { if j == setumaIndex { gap += max(slack, size * 2) } }
                    else if l.justified { gap += max(0, slack) / CGFloat(gapsCount) }
                    x -= gap
                }
            }
            y += lineHeight
        }
    }
}

/// Preview of the PDF with options, Print and Share.
struct PrintSheet: View {
    let target: ReadingTarget
    let initialColors: Bool
    let stamFont: String

    @Environment(\.dismiss) private var dismiss
    @State private var options = ReadingPDF.Options()
    @State private var data: Data?
    @State private var fileURL: URL?
    @State private var verses: [VerseText] = []
    @State private var tikkun: [TikkunView.TikkunLine]?
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Form {
                    if target.passage.isTorah {
                        Picker("Print", selection: $options.mode) {
                            ForEach(ReadingPDF.Options.Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                    }
                    if options.mode == .vowels { Toggle("Color trope groups", isOn: $options.colors) }
                }
                .frame(height: 150)
                if let data { PDFPreview(data: data) } else { ProgressView().frame(maxHeight: .infinity) }
            }
            .navigationTitle("Print")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItemGroup(placement: .primaryAction) {
                    if let fileURL { ShareLink(item: fileURL) { Image(systemName: "square.and.arrow.up") } }
                    Button { printPDF() } label: { Image(systemName: "printer") }.disabled(data == nil)
                }
            }
        }
        .task {
            options.colors = initialColors
            options.stamFont = stamFont
            verses = (try? await SefariaClient.shared.verses(for: target.passage)) ?? []
            if target.passage.isTorah { tikkun = await TikkunView.buildLines(for: target.passage) }
            loaded = true
            render()
        }
        .onChange(of: options) { if loaded { render() } }
    }

    private func render() {
        let d = ReadingPDF.make(target: target, verses: verses, tikkun: tikkun, options: options)
        data = d
        let name = "\(target.shabbat?.parsha ?? target.passage.book) \(target.slotLabel).pdf"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try? d.write(to: url)
        fileURL = url
    }

    private func printPDF() {
        guard let data else { return }
        let info = UIPrintInfo(dictionary: nil)
        info.outputType = .general
        info.jobName = "\(target.shabbat?.parsha ?? target.passage.book) \(target.slotLabel)"
        let controller = UIPrintInteractionController.shared
        controller.printInfo = info
        controller.printingItem = data
        controller.present(animated: true)
    }
}

private struct PDFPreview: UIViewRepresentable {
    let data: Data
    func makeUIView(context: Context) -> PDFView {
        let v = PDFView()
        v.autoScales = true
        v.displayMode = .singlePageContinuous
        v.backgroundColor = .secondarySystemBackground
        return v
    }
    func updateUIView(_ v: PDFView, context: Context) {
        v.document = PDFDocument(data: data)
    }
}
