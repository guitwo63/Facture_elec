import XCTest
import FacturXCore

/// BR-FR-16 côté app. Le Schematron France CTC rejette en fatal tout taux de TVA (BT-152,
/// BT-119) absent d'une liste fermée, mais l'app ne signalait que les taux négatifs, et en
/// avertissement : un 3 % saisi via « Autre… » partait à la PDP pour y être rejeté (vérifié le
/// 2026-09-23 avec le Schematron : BR-FR-16 fatal sur BT-152 et BT-119).
final class FrenchVATRateRuleTests: XCTestCase {

    /// Les taux de la liste du Schematron (`custom:is-valid-vat-rate`), en valeurs.
    private let frenchRates: [Double] = [0, 0.9, 1.05, 1.75, 2.1, 5.5, 7, 8.5, 9.2, 9.6, 10, 13, 19.6, 20, 20.6]

    private func makeDate(_ s: String) -> Date {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f.date(from: s)!
    }

    private func invoice(rates: [Double]) -> Invoice {
        Invoice(
            number: "2026-0077",
            type: .commercialInvoice,
            issueDate: makeDate("2026-09-01"),
            dueDate: makeDate("2026-09-30"),
            seller: InvoiceParty(name: "Mon Entreprise SARL", street: "12 rue du Commerce", postcode: "75001", city: "Paris",
                                 vatNumber: "FR12345678901", siren: "123456789", contactEmail: "contact@exemple.fr",
                                 endpointID: "123456789", endpointSchemeID: "0225"),
            buyer: InvoiceParty(name: "Client Exemple SAS", street: "8 avenue des Champs", postcode: "75008", city: "Paris",
                                siren: "987654321", endpointID: "987654321", endpointSchemeID: "0225"),
            buyerReference: "CLIENT-REF-42",
            lines: rates.enumerated().map { InvoiceLine(name: "Article \($0.offset + 1)", quantity: 1, unit: "C62", unitPrice: 100, vatRate: $0.element) },
            paymentIBAN: "FR7630006000011234567890189",
            paymentBIC: "AGRIFRPP",
            paymentTerms: "Paiement à 30 jours",
            billingMode: .m1
        )
    }

    private func brFR16(_ invoice: Invoice, context: EN16931RuleContext = .issued) -> [BusinessRuleResult] {
        EN16931BusinessRules.evaluate(invoice: invoice, context: context).filter { $0.ruleId == "BR-FR-16" }
    }

    func testEveryFrenchRatePasses() {
        XCTAssertEqual(brFR16(invoice(rates: frenchRates)), [])
    }

    /// Le Schematron compare la chaîne émise : un bruit de calcul qui s'écrit encore « 20.00 »
    /// ou « 5.50 » passe à la PDP, donc ici aussi.
    func testRateWrittenInAnAllowedFormPasses() {
        XCTAssertEqual(brFR16(invoice(rates: [20.000_000_1, 5.500_000_1])), [])
    }

    func testOffListRatesAreBlockingErrorsNamingTheLineAndTheEmittedRate() {
        let results = brFR16(invoice(rates: [20, 3, 19, 5.55, -5]))
        XCTAssertEqual(results.count, 4)
        XCTAssertTrue(results.allSatisfy { $0.severity == .error })
        for (line, rate) in [(2, "3"), (3, "19"), (4, "5.55"), (5, "-5")] {
            XCTAssertTrue(results.contains { $0.message.contains("Ligne \(line) — le taux de TVA « \(rate) »") },
                          "ligne \(line), taux émis « \(rate) »")
        }
    }

    func testOffListRateBlocksTheExport() {
        XCTAssertTrue(FacturXValidator().validate(invoice: invoice(rates: [20, 5.5])).isValid, "référence exportable")
        let result = FacturXValidator().validate(invoice: invoice(rates: [20, 3]))
        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.businessRules.contains { $0.ruleId == "BR-FR-16" && $0.severity == .error })
    }

    /// Facture d'achat : un taux étranger (19 % allemand) n'a rien d'anormal ; seul un taux
    /// négatif reste signalé, en avertissement comme avant.
    func testReceivedInvoiceOnlyFlagsNegativeRates() {
        XCTAssertEqual(brFR16(invoice(rates: [19, 3]), context: .received), [])
        XCTAssertEqual(brFR16(invoice(rates: [-5]), context: .received).map(\.severity), [.warning])
    }
}
