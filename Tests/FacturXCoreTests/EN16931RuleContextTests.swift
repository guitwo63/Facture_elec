import XCTest
import FacturXCore

/// Le paramètre `context` d'`EN16931BusinessRules.evaluate` distingue une facture qu'on
/// émet (`.issued`, comportement par défaut, inchangé) d'une facture reçue d'un tiers
/// (`.received`, factures d'achat) — voir la doc de `EN16931RuleContext`.
final class EN16931RuleContextTests: XCTestCase {

    private func invoiceWithoutLegalNotesOrProfile() -> Invoice {
        Invoice(
            number: "SUP-2026-01",
            profile: .basic,
            seller: InvoiceParty(name: "Fournisseur", street: "1 rue Test", postcode: "75000", city: "Paris", siren: "123456789"),
            buyer: InvoiceParty(name: "Nous", street: "2 rue Test", postcode: "75001", city: "Paris", siren: "987654321"),
            lines: [InvoiceLine(name: "Prestation", quantity: 1, unitPrice: 100, vatRate: 20)],
            legalNotePMT: "",
            legalNotePMD: "",
            legalNoteAAB: ""
        )
    }

    func testIssuedContextFlagsMissingLegalNotesAndLimitedProfile() {
        let results = EN16931BusinessRules.evaluate(invoice: invoiceWithoutLegalNotesOrProfile(), context: .issued)
        XCTAssertTrue(results.contains { $0.ruleId == "BR-FR-05" }, "une facture qu'on émet doit porter les mentions légales FR")
        XCTAssertTrue(results.contains { $0.ruleId == "BR-PROFIL" }, "le profil limité doit être signalé pour une facture qu'on émet")
    }

    func testReceivedContextSuppressesLegalNotesAndProfileChecks() {
        let results = EN16931BusinessRules.evaluate(invoice: invoiceWithoutLegalNotesOrProfile(), context: .received)
        XCTAssertFalse(results.contains { $0.ruleId == "BR-FR-05" }, "rien à corriger sur des mentions légales qu'on n'a pas rédigées")
        XCTAssertFalse(results.contains { $0.ruleId == "BR-PROFIL" }, "on n'a pas choisi le profil d'un document reçu")
    }

    /// Les contrôles de qualité de données génériques (arithmétique, structure, tiers)
    /// restent actifs dans les deux contextes — utiles pour repérer une saisie manuelle
    /// erronée ou un XML malformé, quelle que soit la direction du document.
    func testReceivedContextKeepsGenericDataQualityChecks() {
        var invoice = invoiceWithoutLegalNotesOrProfile()
        invoice.number = ""
        let results = EN16931BusinessRules.evaluate(invoice: invoice, context: .received)
        XCTAssertTrue(results.contains { $0.ruleId == "BR-1" }, "un numéro manquant doit rester détecté, reçu ou pas")
    }

    func testDefaultContextIsIssued() {
        let withoutContext = EN16931BusinessRules.evaluate(invoice: invoiceWithoutLegalNotesOrProfile())
        let explicit = EN16931BusinessRules.evaluate(invoice: invoiceWithoutLegalNotesOrProfile(), context: .issued)
        XCTAssertEqual(withoutContext.map(\.ruleId), explicit.map(\.ruleId), "le comportement par défaut ne doit pas changer pour les appels existants")
    }
}
