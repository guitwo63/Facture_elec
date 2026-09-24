import XCTest
import FacturXCore

/// Export groupé Factur-X / Order-X (menu « Exporter » des listes) : même contrôle qu'à
/// l'unité. L'éditeur refuse de générer un document en erreur bloquante ; l'export groupé
/// générait tout, et la PDP aurait rejeté ces fichiers. Choix de Guillaume (2026-09-24) :
/// les documents en erreur sont ignorés et listés dans le message de fin, les autres exportés.
final class ElectronicBulkExportTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ElectronicBulkExportTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: - Factures

    func testInvoiceWithBlockingErrorIsNotWrittenAndIsListed() throws {
        let valid = sampleInvoice("2026-0001")
        var noSiren = sampleInvoice("2026-0002")
        noSiren.seller.siren = nil
        let firstError = try XCTUnwrap(blockingRuleErrors(noSiren).first, "précondition : BR-FR-10 bloquant")
        XCTAssertTrue(firstError.hasPrefix("BR-FR-10"), firstError)

        var export = ElectronicBulkExport(invoices: [valid, noSiren])
        XCTAssertEqual(export.pendingNumbers, ["2026-0001"])
        export.write(to: directory)

        XCTAssertEqual(try writtenFiles(), ["facture-2026-0001.pdf"])
        XCTAssertEqual(export.writtenFiles, ["facture-2026-0001.pdf"])
        XCTAssertEqual(export.rejections.map(\.number), ["2026-0002"])
        XCTAssertEqual(export.message, """
            1 fichier(s) généré(s).
            1 facture(s) non exportée(s), erreurs bloquantes à corriger :
            • 2026-0002 — \(firstError)
            """)
        let written = try Data(contentsOf: directory.appendingPathComponent("facture-2026-0001.pdf"))
        XCTAssertTrue(FacturXValidator().validate(pdf: written).isValid, "le fichier écrit est un Factur-X")
    }

    /// Autant d'erreurs que le message de l'export à l'unité (« Validation échouée : n erreur(s) »,
    /// `totalErrorCount`), et la première règle en cause.
    func testSeveralErrorsShowTheirCountAndTheFirstRule() throws {
        var invoice = sampleInvoice("2026-0003")
        invoice.seller.siren = nil
        invoice.legalNotePMT = ""
        let validation = FacturXValidator().validate(invoice: invoice)
        XCTAssertGreaterThanOrEqual(validation.totalErrorCount, 2, "précondition : BR-FR-10 et BR-FR-05")
        let rules = Set(validation.businessRules.filter { $0.severity == .error }.map(\.ruleId))
        XCTAssertTrue(rules.isSuperset(of: ["BR-FR-10", "BR-FR-05"]), "\(rules)")
        let firstError = try XCTUnwrap(blockingRuleErrors(invoice).first)

        var export = ElectronicBulkExport(invoices: [invoice])
        XCTAssertEqual(export.rejections.first?.errors.count, validation.totalErrorCount)
        export.write(to: directory)

        XCTAssertEqual(try writtenFiles(), [])
        XCTAssertEqual(export.message, """
            0 fichier(s) généré(s).
            1 facture(s) non exportée(s), erreurs bloquantes à corriger :
            • 2026-0003 — \(validation.totalErrorCount) erreurs, dont \(firstError)
            """)
    }

    /// Exportables = exactement celles que l'éditeur accepterait d'exporter une à une.
    func testExportableInvoicesAreThoseTheEditorWouldExport() throws {
        let valid = sampleInvoice("V-1")
        var sellerSiren = sampleInvoice("E-BR-FR-10")
        sellerSiren.seller.siren = nil
        var mentions = sampleInvoice("E-BR-FR-05")
        mentions.legalNoteAAB = "  "
        var vatRate = sampleInvoice("E-BR-FR-16")
        vatRate.lines[0].vatRate = 15
        var unit = sampleInvoice("E-BR-CL-23")
        unit.lines[1].unit = "KTM"
        var currency = sampleInvoice("E-BR-FR-CO-12")
        currency.currency = "USD"
        var buyerName = sampleInvoice("E-BR-07")
        buyerName.buyer.name = ""
        let invoices = [valid, sellerSiren, mentions, vatRate, unit, currency, buyerName]
        for invoice in invoices where invoice.number.hasPrefix("E-") {
            let validation = FacturXValidator().validate(invoice: invoice)
            let rule = String(invoice.number.dropFirst(2))
            XCTAssertFalse(validation.isValid, "précondition : \(invoice.number) en erreur")
            XCTAssertTrue(validation.businessRules.contains { $0.ruleId == rule && $0.severity == .error },
                          "précondition : \(rule) bloquant sur \(invoice.number)")
        }

        var export = ElectronicBulkExport(invoices: invoices)
        let accepted = invoices.filter { FacturXValidator().validate(invoice: $0).isValid }.map(\.number)
        XCTAssertEqual(accepted, ["V-1"])
        XCTAssertEqual(export.pendingNumbers, accepted)
        XCTAssertEqual(export.rejections.map(\.number), invoices.map(\.number).filter { $0 != "V-1" })
        for rejection in export.rejections {
            let invoice = try XCTUnwrap(invoices.first { $0.number == rejection.number })
            XCTAssertEqual(rejection.errors.count, FacturXValidator().validate(invoice: invoice).totalErrorCount,
                           rejection.number)
        }
        export.write(to: directory)
        XCTAssertEqual(try writtenFiles(), ["facture-V-1.pdf"])
    }

    /// Un avertissement ne bloque pas plus l'export groupé que l'export à l'unité.
    func testWarningsDoNotBlock() throws {
        let invoice = sampleInvoice("2026-0004")
        let validation = FacturXValidator().validate(invoice: invoice)
        XCTAssertTrue(validation.isValid)
        XCTAssertTrue(validation.businessRules.contains { $0.severity == .warning },
                      "précondition : la clé Luhn du SIREN 123456789 est fausse (avertissement)")

        var export = ElectronicBulkExport(invoices: [invoice])
        export.write(to: directory)
        XCTAssertEqual(try writtenFiles(), ["facture-2026-0004.pdf"])
        XCTAssertEqual(export.message, "1 fichier(s) généré(s).")
    }

    func testCreditNoteKeepsItsFileNameAndInternalCreditNotesAreStillSkipped() throws {
        var creditNote = sampleInvoice("AV-0001")
        creditNote.type = .creditNote
        creditNote.precedingInvoiceRef = "2026-0001"
        creditNote.precedingInvoiceDate = makeDate("2026-09-01")
        XCTAssertTrue(FacturXValidator().validate(invoice: creditNote).isValid, "précondition : avoir valide")
        var internalNote = sampleInvoice("AI-0001")
        internalNote.type = .internalCreditNote
        internalNote.buyer.name = ""

        var export = ElectronicBulkExport(invoices: [creditNote, internalNote])
        XCTAssertEqual(export.pendingNumbers, ["AV-0001"])
        XCTAssertEqual(export.rejections, [], "un avoir interne n'est pas contrôlé : il n'est jamais exporté")
        export.write(to: directory)

        XCTAssertEqual(try writtenFiles(), ["avoir-AV-0001.pdf"])
        XCTAssertEqual(export.message, "1 fichier(s) généré(s), 1 avoir(s) interne(s) ignoré(s).")
    }

    /// Rien à écrire : l'app ne demande pas de dossier et affiche directement la liste.
    func testNothingPendingWhenEveryInvoiceIsBlocked() throws {
        var first = sampleInvoice("2026-0005")
        first.buyer.name = ""
        var second = sampleInvoice("")
        second.legalNotePMD = ""
        let export = ElectronicBulkExport(invoices: [first, second])

        XCTAssertFalse(export.hasPendingDocuments)
        XCTAssertEqual(export.rejections.map(\.number), ["2026-0005", ""])
        let lines = export.message.components(separatedBy: "\n")
        guard lines.count == 4 else { return XCTFail("4 lignes attendues : \(export.message)") }
        XCTAssertEqual(Array(lines.prefix(2)), [
            "0 fichier(s) généré(s).",
            "2 facture(s) non exportée(s), erreurs bloquantes à corriger :",
        ])
        XCTAssertTrue(lines[2].hasPrefix("• 2026-0005 — "), lines[2])
        XCTAssertTrue(lines[3].hasPrefix("• (sans numéro) — "), lines[3])
    }

    /// Même contrôle qu'à l'unité après génération : un PDF sans Factur-X embarqué n'est pas écrit.
    func testGeneratedPDFFailingItsCheckIsNotWritten() throws {
        let invoice = sampleInvoice("2026-0006")
        let barePDF = InvoicePDFRenderer().render(invoice: invoice)
        let check = FacturXValidator().validate(pdf: barePDF)
        XCTAssertFalse(check.isValid, "précondition : un PDF simple n'est pas un Factur-X")

        var export = ElectronicBulkExport(invoices: [invoice], generate: { InvoicePDFRenderer().render(invoice: $0) })
        XCTAssertEqual(export.pendingNumbers, ["2026-0006"])
        export.write(to: directory)

        XCTAssertEqual(try writtenFiles(), [])
        XCTAssertEqual(export.rejections, [ElectronicBulkExport.Rejection(number: "2026-0006", errors: check.errors)])
        XCTAssertTrue(export.message.hasSuffix("• 2026-0006 — \(check.errors.count) erreurs, dont \(check.errors[0])"),
                      export.message)
    }

    func testGenerationFailureIsListedWithItsNumber() throws {
        struct Broken: LocalizedError {
            var errorDescription: String? { "générateur en panne" }
        }
        var export = ElectronicBulkExport(invoices: [sampleInvoice("2026-0007"), sampleInvoice("2026-0008")],
                                          generate: { invoice in
            if invoice.number == "2026-0008" { throw Broken() }
            return try FacturXGenerator().generate(invoice: invoice)
        })
        export.write(to: directory)

        XCTAssertEqual(try writtenFiles(), ["facture-2026-0007.pdf"])
        XCTAssertEqual(export.failures.map(\.number), ["2026-0008"])
        XCTAssertEqual(export.message, """
            1 fichier(s) généré(s).
            1 facture(s) non exportée(s), échec de la génération ou de l'écriture :
            • 2026-0008 — générateur en panne
            """)
    }

    // MARK: - Commandes

    func testOrderWithBlockingErrorIsNotWrittenAndIsListed() throws {
        let valid = sampleOrder("CD-0001")
        var noBuyer = sampleOrder("CD-0002")
        noBuyer.buyer.name = ""
        let validation = OrderXValidator().validate(order: noBuyer)
        XCTAssertEqual(validation.errors, ["Le nom de l'acheteur est obligatoire."], "précondition")

        var export = ElectronicBulkExport(orders: [valid, noBuyer])
        XCTAssertEqual(export.pendingNumbers, ["CD-0001"])
        export.write(to: directory)

        XCTAssertEqual(try writtenFiles(), ["commande-CD-0001.pdf"])
        XCTAssertEqual(export.message, """
            1 fichier(s) généré(s).
            1 commande(s) non exportée(s), erreurs bloquantes à corriger :
            • CD-0002 — Le nom de l'acheteur est obligatoire.
            """)
        let written = try Data(contentsOf: directory.appendingPathComponent("commande-CD-0001.pdf"))
        XCTAssertTrue(OrderXValidator().validate(pdf: written).isValid, "le fichier écrit est un Order-X")
    }

    func testGeneratedOrderPDFFailingItsCheckIsNotWritten() throws {
        let order = sampleOrder("CD-0003")
        var export = ElectronicBulkExport(orders: [order], generate: { OrderPDFRenderer().render(order: $0) })
        export.write(to: directory)

        XCTAssertEqual(try writtenFiles(), [])
        XCTAssertEqual(export.rejections.map(\.number), ["CD-0003"])
        XCTAssertEqual(export.rejections.first?.errors,
                       OrderXValidator().validate(pdf: OrderPDFRenderer().render(order: order)).errors)
    }

    // MARK: - Aides

    /// Messages des règles bloquantes, dans l'ordre où l'éditeur les affiche.
    private func blockingRuleErrors(_ invoice: Invoice) -> [String] {
        FacturXValidator().validate(invoice: invoice).businessRules.filter { $0.severity == .error }.map(\.message)
    }

    private func writtenFiles() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
    }

    private func makeDate(_ s: String) -> Date {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.date(from: s)!
    }

    private func sampleInvoice(_ number: String) -> Invoice {
        Invoice(
            number: number,
            type: .commercialInvoice,
            issueDate: makeDate("2026-09-01"),
            dueDate: makeDate("2026-09-30"),
            currency: "EUR",
            profile: .en16931,
            seller: InvoiceParty(
                name: "Mon Entreprise SARL",
                street: "12 rue du Commerce",
                postcode: "75001",
                city: "Paris",
                country: "FR",
                vatNumber: "FR12345678901",
                siren: "123456789",
                contactEmail: "contact@exemple.fr",
                endpointID: "123456789",
                endpointSchemeID: "0225"
            ),
            buyer: InvoiceParty(
                name: "Client Exemple SAS",
                street: "8 avenue des Champs",
                postcode: "75008",
                city: "Paris",
                country: "FR",
                siren: "987654321",
                endpointID: "987654321",
                endpointSchemeID: "0225"
            ),
            buyerReference: "CLIENT-REF-42",
            lines: [
                InvoiceLine(name: "Prestation de conseil", quantity: 2, unit: "DAY", unitPrice: 600, vatRate: 20),
                InvoiceLine(name: "Frais de déplacement", quantity: 1, unit: "C62", unitPrice: 150, vatRate: 20)
            ],
            paymentIBAN: "FR7630006000011234567890189",
            paymentBIC: "AGRIFRPP",
            paymentTerms: "Paiement à 30 jours",
            billingMode: .m1
        )
    }

    private func sampleOrder(_ number: String) -> SalesOrder {
        SalesOrder(
            number: number,
            type: .order,
            issueDate: makeDate("2026-09-01"),
            requestedDeliveryDate: makeDate("2026-09-15"),
            currency: "EUR",
            profile: .comfort,
            buyer: InvoiceParty(
                name: "Société Exemple SAS",
                street: "8 avenue des Champs",
                postcode: "75008",
                city: "Paris",
                country: "FR",
                siren: "987654321",
                endpointID: "987654321",
                endpointSchemeID: "0225"
            ),
            seller: InvoiceParty(
                name: "Mon Entreprise SARL",
                street: "12 rue du Commerce",
                postcode: "75001",
                city: "Paris",
                country: "FR",
                vatNumber: "FR12345678901",
                siren: "123456789",
                contactEmail: "contact@monentreprise.fr",
                endpointID: "123456789",
                endpointSchemeID: "0225"
            ),
            buyerReference: "ACHAT-REF-42",
            lines: [
                InvoiceLine(name: "Licence logicielle", quantity: 2, unit: "C62", unitPrice: 600, vatRate: 20),
                InvoiceLine(name: "Support technique", quantity: 10, unit: "HUR", unitPrice: 90, vatRate: 20)
            ],
            requestedResponseTypeCode: "AC"
        )
    }
}
