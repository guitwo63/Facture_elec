import XCTest
import FacturXCore

/// Taux de TVA non entiers émis arrondis à l'entier (5,5 % → « 6 »), trouvé le 2026-09-23 avec
/// les validateurs officiels : BR-FR-16 (Schematron France CTC) rejetait en fatal « Taux
/// fourni : "6" », pour BT-152 (ligne) comme pour BT-119 (récapitulatif). Le test d'entier de
/// `formatRate` (`rate == rate.rounded()`) appelait l'extension `rounded(toPlaces: Int = 2)` de
/// FacturXCore et non l'arrondi à l'entier de la bibliothèque standard.
final class VATRateFormattingTests: XCTestCase {

    /// `custom:is-valid-vat-rate` de `cii-schematron-fr-ctc/BR-FR-Flux2-Schematron-CII.xslt`
    /// (paquet factur-x) : une comparaison de chaînes, où « 5.5 » et « 5.50 » passent.
    private let brFR16AllowedRates: Set<String> = [
        "0", "0.0", "0.00", "10", "10.0", "10.00", "13", "13.0", "13.00", "20", "20.0", "20.00",
        "8.5", "8.50", "19.6", "19.60", "2.1", "2.10", "5.5", "5.50", "7", "7.0", "7.00",
        "20.6", "20.60", "1.05", "0.9", "0.90", "1.75", "9.2", "9.20", "9.6", "9.60",
    ]
    /// Les taux de cette liste, triés.
    private let frenchRates: [Double] = [0, 0.9, 1.05, 1.75, 2.1, 5.5, 7, 8.5, 9.2, 9.6, 10, 13, 19.6, 20, 20.6]

    private let sampleRates: [Double] = [5.5, 2.1, 8.5, 10, 20]

    // MARK: - Outils

    private func makeDate(_ s: String) -> Date {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f.date(from: s)!
    }

    private let seller = InvoiceParty(name: "Mon Entreprise SARL", street: "12 rue du Commerce", postcode: "75001", city: "Paris",
                                      vatNumber: "FR12345678901", siren: "123456789", contactEmail: "contact@exemple.fr",
                                      endpointID: "123456789", endpointSchemeID: "0225")
    private let buyer = InvoiceParty(name: "Client Exemple SAS", street: "8 avenue des Champs", postcode: "75008", city: "Paris",
                                     siren: "987654321", endpointID: "987654321", endpointSchemeID: "0225")

    /// Une ligne à 100 € HT par taux, dans l'ordre donné.
    private func lines(_ rates: [Double]) -> [InvoiceLine] {
        rates.enumerated().map { InvoiceLine(name: "Article \($0.offset + 1)", quantity: 1, unit: "C62", unitPrice: 100, vatRate: $0.element) }
    }

    private func invoice(rates: [Double]) -> Invoice {
        Invoice(
            number: "2026-0055",
            type: .commercialInvoice,
            issueDate: makeDate("2026-09-01"),
            dueDate: makeDate("2026-09-30"),
            seller: seller,
            buyer: buyer,
            buyerReference: "CLIENT-REF-42",
            lines: lines(rates),
            paymentIBAN: "FR7630006000011234567890189",
            paymentBIC: "AGRIFRPP",
            paymentTerms: "Paiement à 30 jours",
            billingMode: .m1
        )
    }

    private func order(rates: [Double]) -> SalesOrder {
        SalesOrder(
            number: "CD2026-0055",
            type: .order,
            issueDate: makeDate("2026-09-01"),
            requestedDeliveryDate: makeDate("2026-09-15"),
            currency: "EUR",
            profile: .comfort,
            buyer: buyer,
            seller: seller,
            buyerReference: "ACHAT-REF-42",
            lines: lines(rates),
            requestedResponseTypeCode: "AC"
        )
    }

    /// Valeurs de `RateApplicablePercent` des lignes, puis du récapitulatif d'en-tête.
    private func emittedRates(_ xml: Data) throws -> (lines: [String], header: [String]) {
        let doc = try XMLDocument(data: xml)
        func values(_ path: String) throws -> [String] {
            try doc.nodes(forXPath: path).compactMap { $0.stringValue }
        }
        let tax = "*[local-name()='ApplicableTradeTax']/*[local-name()='RateApplicablePercent']"
        return (
            try values("//*[local-name()='IncludedSupplyChainTradeLineItem']/*[local-name()='SpecifiedLineTradeSettlement']/" + tax),
            try values("//*[local-name()='ApplicableHeaderTradeSettlement']/" + tax)
        )
    }

    private func childValue(_ element: XMLElement, _ name: String) -> Double? {
        element.children?.compactMap { $0 as? XMLElement }.first { $0.localName == name }?.stringValue.flatMap(Double.init)
    }

    // MARK: - Cause racine

    /// `x.rounded()` doit rester l'arrondi à l'entier de la bibliothèque standard, y compris là où
    /// FacturXCore est importé : son extension `rounded(toPlaces:)` y est publique, et une valeur
    /// par défaut la ferait de nouveau passer devant.
    func testPlainRoundedIsTheStandardLibraryRoundingToAnInteger() {
        let rate: Double = 5.5
        XCTAssertEqual(rate.rounded(), 6)
        XCTAssertEqual((2.1 as Double).rounded(), 2)
        XCTAssertEqual(rate.rounded(toPlaces: 2), 5.5)
    }

    // MARK: - XML Factur-X (CII)

    func testInvoiceEmitsDecimalRatesAsIsOnLinesAndInTheVATBreakdown() throws {
        let rates = try emittedRates(CIIXMLGenerator().generate(invoice: invoice(rates: sampleRates)))
        XCTAssertEqual(rates.lines, ["5.50", "2.10", "8.50", "10", "20"], "BT-152, dans l'ordre des lignes")
        XCTAssertEqual(rates.header, ["2.10", "5.50", "8.50", "10", "20"], "BT-119, récapitulatif trié par taux")
    }

    func testEveryFrenchRateIsEmittedInAFormAllowedByBRFR16() throws {
        let rates = try emittedRates(CIIXMLGenerator().generate(invoice: invoice(rates: frenchRates)))
        XCTAssertEqual(rates.lines.count, frenchRates.count)
        for (rate, text) in zip(frenchRates, rates.lines) {
            XCTAssertTrue(brFR16AllowedRates.contains(text), "BT-152 « \(text) » refusé par BR-FR-16 (taux \(rate))")
            XCTAssertEqual(Double(text), rate, "BT-152 « \(text) » ne vaut pas \(rate)")
        }
        for text in rates.header {
            XCTAssertTrue(brFR16AllowedRates.contains(text), "BT-119 « \(text) » refusé par BR-FR-16")
        }
        XCTAssertEqual(rates.header.compactMap(Double.init), frenchRates, "un sous-total par taux")
    }

    /// BR-CO-17 (BR-FXEXT-S-09b pour le Schematron EXTENDED) : montant de TVA = base × taux / 100.
    /// Avec « 6 » émis pour un montant calculé à 5,5 %, le XML se contredisait.
    func testVATBreakdownAmountMatchesTheEmittedRate() throws {
        let doc = try XMLDocument(data: CIIXMLGenerator().generate(invoice: invoice(rates: sampleRates)))
        let taxes = try doc.nodes(forXPath: "//*[local-name()='ApplicableHeaderTradeSettlement']/*[local-name()='ApplicableTradeTax']")
            .compactMap { $0 as? XMLElement }
        XCTAssertEqual(taxes.count, sampleRates.count)
        for tax in taxes {
            let basis = try XCTUnwrap(childValue(tax, "BasisAmount"))
            let rate = try XCTUnwrap(childValue(tax, "RateApplicablePercent"))
            let amount = try XCTUnwrap(childValue(tax, "CalculatedAmount"))
            XCTAssertEqual(amount, basis * rate / 100, accuracy: 0.005, "BT-117 incohérent avec BT-119 \(rate)")
        }
    }

    /// L'import d'un XML émis par l'app relit 5,5 %, et non 6 %.
    func testParserReadsTheDecimalRatesBack() throws {
        let parsed = try CIIXMLParser().parse(xml: CIIXMLGenerator().generate(invoice: invoice(rates: sampleRates)))
        XCTAssertEqual(parsed.lines.map(\.vatRate), sampleRates)
    }

    // MARK: - XML Order-X

    func testOrderEmitsDecimalRatesAsIsOnLinesAndInTheVATBreakdown() throws {
        let rates = try emittedRates(OrderCIOXMLGenerator().generate(order: order(rates: sampleRates)))
        XCTAssertEqual(rates.lines, ["5.50", "2.10", "8.50", "10", "20"])
        XCTAssertEqual(rates.header, ["2.10", "5.50", "8.50", "10", "20"])
    }
}
