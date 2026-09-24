import XCTest

/// Garde (règle de #135) : aucune action d'`onChange` de l'app n'envoie un statut à SUPER PDP ni
/// une alerte email. Un `onChange` se déclenche aussi quand le programme change la valeur : statut
/// reçu de SUPER PDP, restauration d'une sauvegarde, changement de sélection. Un envoi voulu par
/// l'utilisateur va dans l'action du bouton ou dans le setter d'un `Binding(get:set:)`. Le
/// comportement lui-même est vérifié sur les vrais éditeurs par `StatusEchoTests`.
final class StatusEchoOnChangeGuardTests: XCTestCase {
    func testNoOnChangeSendsAStatusOrAnAlert() throws {
        let appDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/FacturXMacApp")
        let files = (FileManager.default.enumerator(at: appDir, includingPropertiesForKeys: nil)?.allObjects as? [URL] ?? [])
            .filter { $0.pathExtension == "swift" }
        XCTAssertFalse(files.isEmpty, "aucun source trouvé dans \(appDir.path)")
        let outgoing = ["notifyPDPStatusChange", "sendInvoiceStatusAlertIfNeeded", "setStatusChosenByUser",
                        "sendInvoiceEvent", "SuperPDPService", "SMTPService"]
        var offenders: [String] = []
        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            for handler in Self.onChangeHandlers(in: source) {
                for name in outgoing where handler.text.contains(name) {
                    offenders.append("\(file.lastPathComponent):\(handler.line) : \(name)")
                }
            }
        }
        XCTAssertEqual(offenders, [], "envoi dans un onChange : le déplacer dans l'action de l'utilisateur")
    }

    func testHandlerExtraction() {
        let source = """
        Text("a")
            .onChange(of: items.map { $0.id }) { ids in
                if ids.isEmpty { reset() }
            }
            .onChange(of: x, perform: handle)
        """
        let handlers = Self.onChangeHandlers(in: source)
        XCTAssertEqual(handlers.map(\.line), [2, 5])
        XCTAssertTrue(handlers[0].text.hasSuffix("reset() }\n    }"))
        XCTAssertEqual(handlers[1].text, ".onChange(of: x, perform: handle)")
    }

    /// Texte de chaque `.onChange(…)`, arguments et action en fin d'appel compris, avec sa ligne.
    /// Comptage simple des parenthèses et accolades : suffisant pour les sources de l'app.
    static func onChangeHandlers(in source: String) -> [(line: Int, text: String)] {
        var handlers: [(line: Int, text: String)] = []
        var searchStart = source.startIndex
        while let call = source.range(of: ".onChange(", range: searchStart..<source.endIndex) {
            var end = call.upperBound
            var depth = 1
            while end < source.endIndex, depth > 0 {
                if source[end] == "(" { depth += 1 } else if source[end] == ")" { depth -= 1 }
                end = source.index(after: end)
            }
            var next = end
            while next < source.endIndex, source[next].isWhitespace { next = source.index(after: next) }
            if next < source.endIndex, source[next] == "{" {
                var braces = 0
                repeat {
                    if source[next] == "{" { braces += 1 } else if source[next] == "}" { braces -= 1 }
                    next = source.index(after: next)
                } while next < source.endIndex && braces > 0
                end = next
            }
            let line = source[..<call.lowerBound].filter { $0 == "\n" }.count + 1
            handlers.append((line, String(source[call.lowerBound..<end])))
            searchStart = call.upperBound
        }
        return handlers
    }
}
