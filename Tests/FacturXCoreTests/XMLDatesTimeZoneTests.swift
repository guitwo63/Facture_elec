import XCTest
import PDFKit
@testable import FacturXCore

/// Exécute `body` avec `identifier` comme fuseau de l'application (`NSTimeZone.default`), puis
/// rétablit le fuseau d'origine. Ce fuseau est suivi par les dates du XML (`DocumentDate`), par
/// le PDF (`DateFormatter()`) et par le calcul des échéances (`Calendar.current`), mais pas par
/// `TimeZone.current`.
func inAppTimeZone<T>(_ identifier: String, _ body: () throws -> T) rethrows -> T {
    let saved = NSTimeZone.default
    NSTimeZone.default = TimeZone(identifier: identifier)!
    defer { NSTimeZone.default = saved }
    return try body()
}

/// Les dates du XML (format 102) sont le jour du fuseau de l'application, celui de l'éditeur et
/// du PDF. Elles étaient écrites en UTC : à Paris, un instant entre 00:00 et 01:00 (02:00 en été)
/// s'écrivait la veille. C'était le cas des échéances « fin de mois », calculées à 00:00, et des
/// factures créées juste après minuit. Scénarios d'un utilisateur à Paris, sauf mention d'un
/// autre fuseau.
final class XMLDatesTimeZoneTests: XCTestCase {

    override func invokeTest() {
        inAppTimeZone("Europe/Paris") { super.invokeTest() }
    }

    // MARK: - Outils

    /// Instant à l'heure de Paris, par exemple "2026-09-15 00:30".
    private func paris(_ s: String) -> Date {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Europe/Paris")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.date(from: s)!
    }

    private let seller = InvoiceParty(name: "Mon Entreprise SARL", street: "12 rue du Commerce", postcode: "75001", city: "Paris",
                                      vatNumber: "FR12345678901", siren: "123456789", contactEmail: "contact@exemple.fr",
                                      endpointID: "123456789", endpointSchemeID: "0225")
    private let buyer = InvoiceParty(name: "Client Exemple SAS", street: "8 avenue des Champs", postcode: "75008", city: "Paris",
                                     siren: "987654321", endpointID: "987654321", endpointSchemeID: "0225")
    private let lines = [InvoiceLine(name: "Prestation de conseil", quantity: 2, unit: "DAY", unitPrice: 600, vatRate: 20)]

    /// Facture sans erreur de règle métier (celle de `FacturXCoreTests.sampleInvoice()`),
    /// échéance le jour même.
    private func sampleInvoice(issuedAt issueDate: Date) -> Invoice {
        Invoice(number: "2026-0001", type: .commercialInvoice, issueDate: issueDate, dueDate: issueDate,
                seller: seller, buyer: buyer, buyerReference: "CLIENT-REF-42", lines: lines,
                paymentIBAN: "FR7630006000011234567890189", paymentBIC: "AGRIFRPP",
                paymentTerms: "Paiement à réception", billingMode: .m1)
    }

    /// Dates format 102 d'un XML, par élément parent : IssueDateTime (BT-2), DueDateDateTime
    /// (BT-9), FormattedIssueDateTime (BT-26), OccurrenceDateTime (livraison).
    private func dates(inXML xml: Data) throws -> [String: String] {
        let doc = try XMLDocument(data: xml)
        var dates: [String: String] = [:]
        for node in try doc.nodes(forXPath: "//*[local-name()='DateTimeString']") {
            if let parent = node.parent?.localName, let value = node.stringValue {
                dates[parent] = value
            }
        }
        return dates
    }

    private func xmlDates(_ invoice: Invoice) throws -> [String: String] {
        try dates(inXML: CIIXMLGenerator().generate(invoice: invoice))
    }

    private func pdfText(_ invoice: Invoice) -> String {
        PDFDocument(data: InvoicePDFRenderer().render(invoice: invoice))?.string ?? ""
    }

    // MARK: - Échéances « fin de mois », calculées à 00:00

    /// Préréglage par défaut « 30 jours fin de mois » : le XML portait l'échéance de la veille
    /// (29/09) alors que l'éditeur et le PDF affichaient le 30/09.
    func testDefaultEndOfMonthPresetGivesTheSameDueDayInTheXMLAndThePDF() throws {
        let preset = try XCTUnwrap(PaymentTermsPresetStore.defaults.first { $0.id == "finDeMois30" })
        var invoice = sampleInvoice(issuedAt: paris("2026-08-14 10:00"))
        invoice.paymentTerms = preset.text
        invoice.dueDate = preset.dueRule.dueDate(from: invoice.issueDate)

        XCTAssertEqual(try xmlDates(invoice)["DueDateDateTime"], "20260930", "31/08 + 30 jours")
        XCTAssertTrue(pdfText(invoice).contains("Échéance: 30/09/2026"))
    }

    /// « Fin de mois + 0 jour » sur une facture du dernier jour du mois : l'éditeur, le PDF et
    /// maintenant le XML portent deux fois le 31/08. BR-FR-CO-07 bloquait l'export, puisque le XML
    /// portait une échéance au 30/08. La PDP accepte pourtant une échéance égale à la date de facture.
    func testEndOfMonthPlusZeroOnTheLastDayOfTheMonthIsNotBlocked() throws {
        var invoice = sampleInvoice(issuedAt: paris("2026-08-31 16:00"))
        invoice.dueDate = PaymentTermsDueRule.endOfMonthPlusDays(0).dueDate(from: invoice.issueDate)
        XCTAssertLessThan(invoice.dueDate, invoice.issueDate, "échéance calculée à 00:00, avant l'heure de la facture")

        let dates = try xmlDates(invoice)
        XCTAssertEqual(dates["IssueDateTime"], "20260831")
        XCTAssertEqual(dates["DueDateDateTime"], "20260831")
        XCTAssertFalse(EN16931BusinessRules.evaluate(invoice: invoice).contains { $0.ruleId == "BR-FR-CO-07" })
        let validation = FacturXValidator().validate(invoice: invoice)
        XCTAssertTrue(validation.isValid, "\(validation.businessRules.filter { $0.severity == .error }.map(\.message))")

        let text = pdfText(invoice)
        XCTAssertTrue(text.contains("Date: 31/08/2026"))
        XCTAssertTrue(text.contains("Échéance: 31/08/2026"))
    }

    // MARK: - Facture créée juste après minuit

    func testInvoiceCreatedJustAfterMidnightKeepsItsDayInTheXML() throws {
        for (createdAt, xmlDay, printedDay) in [
            ("2026-09-15 00:30", "20260915", "15/09/2026"), // heure d'été, UTC+2
            ("2026-01-15 00:30", "20260115", "15/01/2026"), // heure d'hiver, UTC+1
        ] {
            let invoice = sampleInvoice(issuedAt: paris(createdAt))
            let dates = try xmlDates(invoice)
            XCTAssertEqual(dates["IssueDateTime"], xmlDay, createdAt)
            XCTAssertEqual(dates["DueDateDateTime"], xmlDay, createdAt)
            XCTAssertEqual(dates["OccurrenceDateTime"], xmlDay, "\(createdAt) : date de livraison = date de facture")
            XCTAssertTrue(pdfText(invoice).contains("Date: \(printedDay)"), createdAt)
        }
    }

    /// Le PDF/A cite aussi la date de facture dans ses métadonnées XMP.
    func testXMPMetadataCitesTheInvoiceDay() throws {
        let pdf = try FacturXGenerator().generate(invoice: sampleInvoice(issuedAt: paris("2026-09-15 00:30")))
        XCTAssertNotNil(pdf.range(of: Data("Invoice 2026-0001 dated 2026-09-15".utf8)))
    }

    // MARK: - Date de la facture antérieure (BT-26)

    func testPrecedingInvoiceDateIsTheDayPrintedOnTheCreditNote() throws {
        var credit = sampleInvoice(issuedAt: paris("2026-09-16 10:00"))
        credit.type = .creditNote
        credit.precedingInvoiceRef = "2026-0000"
        credit.precedingInvoiceDate = paris("2026-09-15 00:18")

        XCTAssertEqual(try xmlDates(credit)["FormattedIssueDateTime"], "20260915")
        XCTAssertTrue(pdfText(credit).contains("Facture antérieure: 2026-0000 du 15/09/2026"))
    }

    // MARK: - Order-X

    func testOrderXDatesAreTheDaysPrintedOnTheOrder() throws {
        let order = SalesOrder(number: "CD2026-0001", type: .order,
                               issueDate: paris("2025-11-14 00:00"), requestedDeliveryDate: paris("2025-11-28 00:30"),
                               buyer: buyer, seller: seller, lines: lines)

        let dates = try dates(inXML: OrderCIOXMLGenerator().generate(order: order))
        XCTAssertEqual(dates["IssueDateTime"], "20251114")
        XCTAssertEqual(dates["OccurrenceDateTime"], "20251128", "date de livraison souhaitée")
        let text = PDFDocument(data: OrderPDFRenderer().render(order: order))?.string ?? ""
        XCTAssertTrue(text.contains("Date: 14/11/2025"))
        XCTAssertTrue(text.contains("Livraison souhaitée: 28/11/2025"))
    }

    // MARK: - Parseur

    /// Aller-retour parseur → générateur, dans plusieurs fuseaux. Le jour lu est celui que l'app
    /// affiche et imprime, et régénérer le XML redonne les mêmes dates. L'ancien parseur lisait
    /// minuit UTC, soit la veille à l'ouest de Greenwich (Antilles, Polynésie).
    func testParserReadsTheXMLDaysInTheAppTimeZone() throws {
        var credit = sampleInvoice(issuedAt: paris("2026-09-30 10:00"))
        credit.type = .creditNote
        credit.dueDate = paris("2026-10-31 10:00")
        credit.precedingInvoiceRef = "2026-0000"
        credit.precedingInvoiceDate = paris("2026-09-15 10:00")
        let xml = try CIIXMLGenerator().generate(invoice: credit)
        let expected = ["IssueDateTime": "20260930", "OccurrenceDateTime": "20260930",
                        "DueDateDateTime": "20261031", "FormattedIssueDateTime": "20260915"]
        XCTAssertEqual(try dates(inXML: xml), expected)

        for zone in ["Europe/Paris", "UTC", "America/Martinique", "Pacific/Tahiti", "Indian/Reunion", "Pacific/Noumea"] {
            try inAppTimeZone(zone) {
                let parsed = try CIIXMLParser().parse(xml: xml)
                XCTAssertEqual(try xmlDates(parsed), expected, zone)
                let text = pdfText(parsed)
                for printed in ["Date: 30/09/2026", "Échéance: 31/10/2026", "Facture antérieure: 2026-0000 du 15/09/2026"] {
                    XCTAssertTrue(text.contains(printed), "\(zone) : \(printed)")
                }
            }
        }
    }

    /// Le jour lu est placé à midi : il reste le même si le fuseau du Mac change ensuite.
    func testParsedDateKeepsItsDayAfterATimeZoneChange() throws {
        let xml = try CIIXMLGenerator().generate(invoice: sampleInvoice(issuedAt: paris("2026-09-30 10:00")))
        let parsed = try CIIXMLParser().parse(xml: xml)
        for zone in ["America/Martinique", "Pacific/Noumea"] {
            inAppTimeZone(zone) {
                XCTAssertTrue(pdfText(parsed).contains("Date: 30/09/2026"), zone)
            }
        }
    }

    func testMalformedXMLDatesAreRejected() {
        for s in ["20260231", "20261301", "20260900", "2026093", "202609301", "2026-09-30", "2026O930", ""] {
            XCTAssertNil(DocumentDate.date(xmlString: s), s)
        }
        XCTAssertNotNil(DocumentDate.date(xmlString: "20280229"), "29 février d'une année bissextile")
    }
}
