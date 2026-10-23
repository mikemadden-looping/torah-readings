import SwiftUI
import CoreText
import UIKit

@main
struct TorahReadingsApp: App {
    init() { Fonts.registerBundled() }
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}

enum Fonts {
    /// Pointed text with te'amim. Noto Serif Hebrew covers every cantillation mark.
    static let hebrew = "Noto Serif Hebrew"

    /// The scroll view uses a STaM font when one is bundled (any font file in
    /// TorahReadings/Fonts whose family name contains "Stam"), else Noto.
    static var scroll: String {
        UIFont.familyNames.first { $0.localizedCaseInsensitiveContains("stam") } ?? hebrew
    }

    static func registerBundled() {
        let urls = ["ttf", "otf"].flatMap { Bundle.main.urls(forResourcesWithExtension: $0, subdirectory: nil) ?? [] }
        for url in urls { CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil) }
    }
}
