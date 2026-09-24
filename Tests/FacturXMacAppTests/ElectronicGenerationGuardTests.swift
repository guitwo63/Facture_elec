import XCTest

/// Garde : l'app ne génère un Factur-X ou un Order-X que dans une fonction qui valide d'abord
/// le document (`FacturXValidator().validate(invoice:)`, `OrderXValidator().validate(order:)`),
/// comme l'export, le dépôt SUPER PDP et la validation PDP de l'éditeur. L'export groupé des
/// listes passe par `ElectronicBulkExport`, qui valide dans FacturXCore (`ElectronicBulkExportTests`) ;
/// avant, il générait tout sans contrôle et contournait toutes les erreurs bloquantes.
final class ElectronicGenerationGuardTests: XCTestCase {
    func testEveryGenerationOfTheAppIsValidatedFirst() throws {
        let appDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/FacturXMacApp")
        let files = (FileManager.default.enumerator(at: appDir, includingPropertiesForKeys: nil)?.allObjects as? [URL] ?? [])
            .filter { $0.pathExtension == "swift" }
        XCTAssertFalse(files.isEmpty, "aucun source trouvé dans \(appDir.path)")
        var offenders: [String] = []
        var generations = 0
        for file in files {
            let result = Self.unvalidatedGenerations(in: try String(contentsOf: file, encoding: .utf8))
            offenders += result.offenders.map { "\(file.lastPathComponent):\($0)" }
            generations += result.generations
        }
        XCTAssertEqual(offenders, [], "valider avant de générer, ou passer par ElectronicBulkExport")
        XCTAssertGreaterThanOrEqual(generations, 4, "l'expression doit reconnaître les générations des éditeurs")
    }

    /// L'ancien export groupé (générateur rangé dans une constante, aucune validation) est repéré ;
    /// une génération précédée de sa validation, même dans une `Task`, ne l'est pas.
    func testDetection() {
        let source = """
        private static func exportElectronicInvoices(_ invoices: [Invoice]) -> String {
            let gen = FacturXGenerator()
            for inv in invoices {
                let data = try gen.generate(invoice: inv)
            }
        }

        private func export() {
            let preCheck = FacturXValidator().validate(invoice: invoice)
            guard preCheck.isValid else { return }
            Task { let data = try FacturXGenerator().generate(invoice: invoice, logo: logo) }
        }

        private func exportOrder() {
            let data = try OrderXGenerator().generate(order: order)
        }

        var body: some View {
            Button("Générer") { _ = try? FacturXGenerator().generate(invoice: invoice) }
        }
        """
        let result = Self.unvalidatedGenerations(in: source)
        XCTAssertEqual(result.generations, 4)
        XCTAssertEqual(result.offenders, [
            "4 : FacturXGenerator sans FacturXValidator().validate(invoice:",
            "15 : OrderXGenerator sans OrderXValidator().validate(order:",
            "19 : FacturXGenerator sans FacturXValidator().validate(invoice:",
        ])
    }

    private static let kinds = [
        (generator: "FacturXGenerator", call: "generate(invoice:", validation: "FacturXValidator().validate(invoice:"),
        (generator: "OrderXGenerator", call: "generate(order:", validation: "OrderXValidator().validate(order:"),
    ]

    /// Générations (« Générateur().generate(… », ou générateur rangé dans une constante) qu'aucune
    /// fonction englobante ne fait précéder de la validation du document, par ligne.
    static func unvalidatedGenerations(in source: String) -> (offenders: [String], generations: Int) {
        let bodies = functionBodies(in: source)
        var offenders: [(line: Int, text: String)] = []
        var generations = 0
        for kind in kinds {
            var receivers = ["\(kind.generator)\\(\\)\\s*"]
            for match in matches(of: "(?:let|var)\\s+(\\w+)\\s*=\\s*\(kind.generator)\\(\\)", in: source) {
                receivers.append(NSRegularExpression.escapedPattern(for: String(source[match[1]])))
            }
            let call = NSRegularExpression.escapedPattern(for: kind.call)
            for receiver in receivers {
                for match in matches(of: "\\b\(receiver)\\.\(call)", in: source) {
                    generations += 1
                    let validated = bodies.contains { body in
                        body.contains(match[0].lowerBound) && source[body].contains(kind.validation)
                    }
                    if !validated {
                        let line = source[..<match[0].lowerBound].filter { $0 == "\n" }.count + 1
                        offenders.append((line, "\(line) : \(kind.generator) sans \(kind.validation)"))
                    }
                }
            }
        }
        return (offenders.sorted { $0.line < $1.line }.map(\.text), generations)
    }

    /// Corps de chaque `func`, accolades comprises. Comptage simple des parenthèses (signature)
    /// et des accolades : suffisant pour les sources de l'app.
    static func functionBodies(in source: String) -> [Range<String.Index>] {
        var bodies: [Range<String.Index>] = []
        for match in matches(of: "\\bfunc\\s+\\w+", in: source) {
            var index = match[0].upperBound
            var parentheses = 0
            while index < source.endIndex, !(source[index] == "{" && parentheses == 0) {
                if source[index] == "(" { parentheses += 1 } else if source[index] == ")" { parentheses -= 1 }
                index = source.index(after: index)
            }
            guard index < source.endIndex else { continue }
            let start = index
            var braces = 0
            repeat {
                if source[index] == "{" { braces += 1 } else if source[index] == "}" { braces -= 1 }
                index = source.index(after: index)
            } while index < source.endIndex && braces > 0
            bodies.append(start..<index)
        }
        return bodies
    }

    /// Plages de chaque correspondance : l'ensemble, puis chaque groupe.
    private static func matches(of pattern: String, in source: String) -> [[Range<String.Index>]] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: source, range: NSRange(source.startIndex..., in: source)).map { result in
            (0..<result.numberOfRanges).compactMap { Range(result.range(at: $0), in: source) }
        }
    }
}
