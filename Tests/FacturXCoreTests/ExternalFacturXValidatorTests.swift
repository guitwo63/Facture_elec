import XCTest
import FacturXCore

/// Tests d'intégration pour ExternalFacturXValidator.
///
/// Ces tests nécessitent que Python 3 et la librairie factur-x soient installés :
///   brew install python3
///   pip3 install factur-x lxml
///
/// Si factur-x n'est pas installé, les tests sont sautés automatiquement.
final class ExternalFacturXValidatorTests: XCTestCase {

    private func sampleInvoice() -> Invoice {
        Invoice(
            number: "2026-0001",
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
                contactEmail: "contact@example.com",
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
                InvoiceLine(name: "Frais de deplacement", quantity: 1, unit: "C62", unitPrice: 150, vatRate: 20)
            ],
            paymentIBAN: "FR7630006000011234567890189",
            paymentBIC: "AGRIFRPP",
            paymentTerms: "Paiement a 30 jours",
            billingMode: .m1
        )
    }

    /// Vérifie que le validateur externe est disponible. Si non, saute les tests.
    private func skipIfUnavailable() throws -> Bool {
        let validator = ExternalFacturXValidator()
        let xml = try CIIXMLGenerator().generate(invoice: sampleInvoice())
        do {
            _ = try validator.validate(xmlData: xml)
            return true
        } catch let error as ExternalValidatorError {
            switch error {
            case .pythonNotFound, .scriptNotFound:
                throw XCTSkip("factur-x ou Python 3 non disponible — installez avec : pip3 install factur-x lxml")
            default:
                throw error
            }
        }
    }

    func testValidInvoicePassesExternalValidation() throws {
        try skipIfUnavailable()
        let validator = ExternalFacturXValidator()
        let result = try validator.validate(invoice: sampleInvoice())
        XCTAssertTrue(result.isValid, "Erreurs inattendues : \(result.errors)")
    }

    func testExternalValidatorCatchesMissingFields() throws {
        try skipIfUnavailable()
        var inv = sampleInvoice()
        inv.number = ""  // BR-02 violation
        let validator = ExternalFacturXValidator()
        let result = try validator.validate(invoice: inv)
        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.errors.contains { $0.contains("XSD") || $0.contains("Schematron") || $0.contains("BT-1") || $0.contains("BR-02") })
    }

    private func makeDate(_ s: String) -> Date {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f.date(from: s)!
    }
}
