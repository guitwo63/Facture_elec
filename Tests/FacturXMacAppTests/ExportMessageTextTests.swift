import XCTest
import SwiftUI
@testable import FacturXMacApp

/// Message de fin des exports lancés depuis les listes : un export groupé peut lister des
/// dizaines de documents non exportés. Le texte garde sa hauteur naturelle tant qu'il est
/// court, et défile au-delà de 120 points au lieu de repousser la liste hors de l'écran.
final class ExportMessageTextTests: XCTestCase {
    private final class Box { var height: CGFloat = -1 }

    private var window: NSWindow?

    override func tearDown() {
        window?.contentView = nil
        window?.close()
        window = nil
        super.tearDown()
    }

    func testShortMessageKeepsItsNaturalHeight() {
        let height = renderedHeight(of: "3 fichier(s) généré(s).")
        XCTAssertGreaterThan(height, 8)
        XCTAssertLessThan(height, 30, "une ligne ne doit pas occuper toute la hauteur permise")
    }

    func testFewRejectionsAreShownInFull() {
        let height = renderedHeight(of: message(rejected: 3))
        XCTAssertGreaterThan(height, 50, "cinq lignes")
        XCTAssertLessThan(height, 119, "cinq lignes tiennent sans défilement")
    }

    func testLongListScrollsWithinABoundedHeight() throws {
        let height = renderedHeight(of: message(rejected: 40))
        XCTAssertEqual(height, 120, accuracy: 0.5)
        let scrollView = try XCTUnwrap(scrollViews(in: try XCTUnwrap(window?.contentView)).first)
        let contentHeight = try XCTUnwrap(scrollView.documentView).frame.height
        XCTAssertGreaterThan(contentHeight, 400, "toute la liste reste accessible en défilant")
    }

    /// Hauteur du message dans une pile comme l'en-tête des listes, au-dessus d'une liste qui
    /// prend toute la place restante.
    private func renderedHeight(of message: String) -> CGFloat {
        let box = Box()
        let root = VStack(spacing: 8) {
            Text("Factures").font(.title2.bold())
            ExportMessageText(message: message)
                .background(GeometryReader { proxy in
                    Color.clear.preference(key: HeightKey.self, value: proxy.size.height)
                })
                .onPreferenceChange(HeightKey.self) { box.height = $0 }
            List(0..<50, id: \.self) { Text("Facture \($0)") }
        }
        .frame(width: 520, height: 700)
        let window = NSWindow(contentRect: NSRect(x: -5000, y: -5000, width: 520, height: 700),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = NSHostingView(rootView: root)
        window.orderFront(nil)
        self.window = window
        let deadline = Date().addingTimeInterval(3)
        while box.height < 0 && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        return box.height
    }

    private func message(rejected count: Int) -> String {
        (["0 fichier(s) généré(s).", "\(count) facture(s) non exportée(s), erreurs bloquantes à corriger :"]
            + (1...count).map { "• 2026-\(String(format: "%04d", $0)) — BR-FR-05 : La mention sur l'escompte (SubjectCode AAB) est obligatoire en France." })
            .joined(separator: "\n")
    }

    private func scrollViews(in view: NSView) -> [NSScrollView] {
        (view as? NSScrollView).map { [$0] } ?? view.subviews.flatMap(scrollViews)
    }

    private struct HeightKey: PreferenceKey {
        static var defaultValue: CGFloat = -1
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
    }
}
