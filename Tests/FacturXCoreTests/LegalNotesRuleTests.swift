import XCTest
import FacturXCore

/// BR-FR-05 (Schematron France CTC, fatal) : les mentions PMT, PMD et AAB sont obligatoires sur
/// une facture qu'on émet. C'était un simple avertissement, alors que SUPER PDP répond
/// is_valid=false dès qu'une mention manque : l'app laissait exporter et déposer. Vérifié le
/// 2026-09-23 sur l'endpoint public de validation, avec des factures fictives 380, 381 et 386 et
/// chaque mention vidée tour à tour. Même endpoint, même date : une note faite d'espaces, écrite
/// telle quelle, donnait `PEPPOL-EN16931-R008` (élément vide) et aussi is_valid=false.
final class LegalNotesRuleTests: XCTestCase {

    // MARK: - Outils

    private func utc(_ s: String) -> Date {
        ISO8601DateFormatter().date(from: s)!
    }

    /// Même facture que `FacturXCoreTests.sampleInvoice()` — sans erreur de règle métier, avec
    /// les mentions légales par défaut.
    private func sampleInvoice() -> Invoice {
        Invoice(
            number: "2026-0001",
            type: .commercialInvoice,
            issueDate: utc("2026-09-01T10:00:00Z"),
            dueDate: utc("2026-09-30T10:00:00Z"),
            seller: InvoiceParty(name: "Mon Entreprise SARL", street: "12 rue du Commerce", postcode: "75001", city: "Paris",
                                 vatNumber: "FR12345678901", siren: "123456789", contactEmail: "contact@exemple.fr",
                                 endpointID: "123456789", endpointSchemeID: "0225"),
            buyer: InvoiceParty(name: "Client Exemple SAS", street: "8 avenue des Champs", postcode: "75008", city: "Paris",
                                siren: "987654321", endpointID: "987654321", endpointSchemeID: "0225"),
            buyerReference: "CLIENT-REF-42",
            lines: [
                InvoiceLine(name: "Prestation de conseil", quantity: 2, unit: "DAY", unitPrice: 600, vatRate: 20),
                InvoiceLine(name: "Frais de déplacement", quantity: 1, unit: "C62", unitPrice: 150, vatRate: 20),
            ],
            paymentIBAN: "FR7630006000011234567890189",
            paymentBIC: "AGRIFRPP",
            paymentTerms: "Paiement à 30 jours",
            billingMode: .m1
        )
    }

    private let mentions: [(code: String, keyPath: WritableKeyPath<Invoice, String>)] = [
        ("PMT", \.legalNotePMT), ("PMD", \.legalNotePMD), ("AAB", \.legalNoteAAB),
    ]

    private func legalNoteRules(_ invoice: Invoice, context: EN16931RuleContext = .issued) -> [BusinessRuleResult] {
        EN16931BusinessRules.evaluate(invoice: invoice, context: context).filter { $0.ruleId == "BR-FR-05" }
    }

    /// Contenu de chaque `IncludedNote` du XML généré, par SubjectCode ("" pour la note libre).
    private func xmlNotes(_ invoice: Invoice) throws -> [String: String] {
        let doc = try XMLDocument(data: CIIXMLGenerator().generate(invoice: invoice))
        var notes: [String: String] = [:]
        for node in try doc.nodes(forXPath: "//*[local-name()='IncludedNote']") {
            let code = try node.nodes(forXPath: "*[local-name()='SubjectCode']").first?.stringValue ?? ""
            notes[code] = try node.nodes(forXPath: "*[local-name()='Content']").first?.stringValue
        }
        return notes
    }

    // MARK: - Règle locale

    func testDefaultNotesPassValidation() {
        let invoice = sampleInvoice()
        XCTAssertTrue(legalNoteRules(invoice).isEmpty)
        XCTAssertTrue(FacturXValidator().validate(invoice: invoice).isValid)
    }

    /// Vide, espaces ou retour à la ligne : le générateur n'écrit pas la note, donc elle manque.
    func testEachMissingMentionBlocksExportAndDeposit() {
        for (code, keyPath) in mentions {
            for blank in ["", "   ", "\n"] {
                var invoice = sampleInvoice()
                invoice[keyPath: keyPath] = blank
                let label = "\(code) = \(blank.debugDescription)"

                let rules = legalNoteRules(invoice)
                XCTAssertEqual(rules.map(\.severity), [.error], label)
                XCTAssertTrue(rules.first?.message.contains("SubjectCode \(code)") == true, "le message nomme la mention : \(label)")

                let validation = FacturXValidator().validate(invoice: invoice)
                XCTAssertFalse(validation.isValid, "export, validation et dépôt SUPER PDP refusés : \(label)")
                XCTAssertEqual(validation.totalErrorCount, 1, label)
                XCTAssertFalse(validation.warnings.contains { $0.contains("BR-FR-05") },
                               "plus d'avertissement en double de l'erreur : \(label)")
            }
        }
    }

    func testAllMentionsMissingGiveOneErrorEach() {
        var invoice = sampleInvoice()
        for (_, keyPath) in mentions { invoice[keyPath: keyPath] = "" }

        XCTAssertEqual(legalNoteRules(invoice).map(\.severity), [.error, .error, .error])
        XCTAssertEqual(FacturXValidator().validate(invoice: invoice).totalErrorCount, 3)
    }

    /// SUPER PDP rejette aussi un avoir (381) et un acompte (386) : aucun type émis n'y échappe.
    func testEveryIssuedInvoiceTypeIsBlocked() {
        for type in InvoiceTypeCode.allCases {
            var invoice = sampleInvoice()
            invoice.type = type
            invoice.legalNotePMT = ""
            XCTAssertEqual(legalNoteRules(invoice).map(\.severity), [.error], type.rawValue)
        }
    }

    func testReceivedInvoiceIsNotChecked() {
        var invoice = sampleInvoice()
        for (_, keyPath) in mentions { invoice[keyPath: keyPath] = "" }
        XCTAssertTrue(legalNoteRules(invoice, context: .received).isEmpty,
                      "rien à corriger sur des mentions qu'on n'a pas rédigées")
    }

    // MARK: - XML

    func testBlankNotesAreNotWritten() throws {
        var invoice = sampleInvoice()
        invoice.notes = "   "
        invoice.legalNotePMT = " \n "

        let notes = try xmlNotes(invoice)
        XCTAssertNil(notes[""], "note libre faite d'espaces : aucune IncludedNote")
        XCTAssertNil(notes["PMT"], "mention faite d'espaces : aucune IncludedNote")
        XCTAssertEqual(notes["PMD"], invoice.legalNotePMD)
        XCTAssertEqual(notes["AAB"], invoice.legalNoteAAB)

        // PEPPOL-EN16931-R008 : aucun élément sans enfant ni texte dans tout le document.
        let doc = try XMLDocument(data: CIIXMLGenerator().generate(invoice: invoice))
        let empty = try doc.nodes(forXPath: "//*[not(*) and normalize-space(.) = '']").map { $0.name ?? "?" }
        XCTAssertEqual(empty, [], "éléments vides : \(empty)")
    }

    /// Comme sur le PDF, qui imprime les mentions sans leurs espaces de début et de fin.
    func testNotesAreWrittenWithoutSurroundingSpaces() throws {
        var invoice = sampleInvoice()
        invoice.notes = "  Merci pour votre confiance  "
        invoice.legalNotePMT = " Indemnité forfaitaire pour frais de recouvrement : 40 EUR "

        let notes = try xmlNotes(invoice)
        XCTAssertEqual(notes[""], "Merci pour votre confiance")
        XCTAssertEqual(notes["PMT"], "Indemnité forfaitaire pour frais de recouvrement : 40 EUR")
    }
}
