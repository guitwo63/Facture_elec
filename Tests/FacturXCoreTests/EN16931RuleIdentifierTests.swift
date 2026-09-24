import XCTest
import FacturXCore

/// Les identifiants de règle d'`EN16931BusinessRules` sont ceux des Schematron officiels
/// (EN16931 de Factur-X 1.09, France CTC), pour qu'un contrôle local se rapproche directement
/// du rejet de la PDP. Un contrôle sans règle officielle porte un identifiant interne
/// « BT-<n>-<MOTIF> », jamais un BR-xx qui désignerait une autre règle officielle.
final class EN16931RuleIdentifierTests: XCTestCase {

    private func party(_ name: String) -> InvoiceParty {
        InvoiceParty(name: name, street: "1 rue A", postcode: "75001", city: "Paris", country: "FR",
                     vatNumber: "FR44732829320", siren: "732829320")
    }

    private func invoice(lines: [InvoiceLine] = [InvoiceLine(name: "Prestation", quantity: 1, unitPrice: 100, vatRate: 20)]) -> Invoice {
        Invoice(number: "F-1", seller: party("Vendeur"), buyer: party("Acheteur"), lines: lines)
    }

    private func ruleIDs(_ invoice: Invoice) -> Set<String> {
        Set(EN16931BusinessRules.evaluate(invoice: invoice).map(\.ruleId))
    }

    func testMissingMandatoryDataUsesOfficialIdentifiers() {
        var inv = invoice(lines: [])
        inv.number = ""
        inv.seller.name = ""
        inv.seller.country = ""
        inv.buyer.name = ""
        inv.buyer.country = ""
        let found = ruleIDs(inv)
        // BR-02 numéro (BT-1), BR-06/BR-07 nom du vendeur/de l'acheteur (BT-27/BT-44),
        // BR-09/BR-11 pays du vendeur/de l'acheteur (BT-40/BT-55), BR-16 au moins une ligne.
        for id in ["BR-02", "BR-06", "BR-07", "BR-09", "BR-11", "BR-16"] {
            XCTAssertTrue(found.contains(id), id)
        }
    }

    func testMissingElectronicAddressUsesFrenchCTCRules() {
        var inv = invoice()
        inv.seller.siren = nil
        inv.buyer.siren = nil
        let rules = EN16931BusinessRules.evaluate(invoice: inv)
        // BR-FR-13 : « Le BT-34 est obligatoire » (vendeur) ; BR-FR-12 : BT-49 (acheteur).
        XCTAssertTrue(rules.contains { $0.ruleId == "BR-FR-13" && $0.severity == .error && $0.message.contains("BT-34") })
        XCTAssertTrue(rules.contains { $0.ruleId == "BR-FR-12" && $0.severity == .error && $0.message.contains("BT-49") })
    }

    func testInvalidSirenAndSiretUseFrenchCTCRules() {
        var inv = invoice()
        inv.seller.siren = "12345678"
        inv.buyer.siren = "12345678"
        inv.seller.siret = "73282932000075"
        let rules = EN16931BusinessRules.evaluate(invoice: inv)
        XCTAssertTrue(rules.contains { $0.ruleId == "BR-FR-10" && $0.message.contains("BT-30") }, "SIREN du vendeur : BT-30")
        XCTAssertTrue(rules.contains { $0.ruleId == "BR-FR-32" && $0.message.contains("BT-47") }, "SIREN de l'acheteur : BT-47")
        XCTAssertTrue(rules.contains { $0.ruleId == "BR-FR-09" }, "SIRET")
    }

    /// Aucun Schematron ne vérifie la clé de Luhn d'un SIREN : 9 chiffres respectent BR-FR-10
    /// et BR-FR-32, et la clé fausse relève d'un contrôle interne.
    func testSirenLuhnKeyUsesInternalIdentifiers() {
        var inv = invoice()
        inv.seller.siren = "123456780"
        inv.buyer.siren = "123456780"
        let found = ruleIDs(inv)
        XCTAssertTrue(found.isSuperset(of: ["BT-30-LUHN", "BT-47-LUHN"]))
        XCTAssertTrue(found.isDisjoint(with: ["BR-FR-10", "BR-FR-32"]))
    }

    func testIntraCommunitySupplyRulesUseICPrefix() {
        let found = ruleIDs(invoice(lines: [
            InvoiceLine(name: "Livraison UE", quantity: 1, unitPrice: 100, vatRate: 20, vatCategory: .intraCommunity)
        ]))
        // Catégorie K : ses règles EN16931 sont les BR-IC-xx (taux nul BR-IC-05, motif BR-IC-10).
        XCTAssertTrue(found.contains("BR-IC-05"))
        XCTAssertTrue(found.contains("BR-IC-10"))
        XCTAssertFalse(found.contains { $0.hasPrefix("BR-K-") })
    }

    func testPrecedingInvoiceRuleDependsOnDocumentType() {
        let expected: [(InvoiceTypeCode, String)] = [
            (.correction, "BR-FR-CO-04"), (.creditNote, "BR-FR-CO-05"), (.finalSettlement, "BT-25-SOLDE")
        ]
        for (type, id) in expected {
            var inv = invoice()
            inv.type = type
            XCTAssertTrue(ruleIDs(inv).contains(id), "\(type.rawValue) → \(id)")
        }
    }

    func testChecksWithoutOfficialRuleUseInternalIdentifiers() {
        var inv = invoice(lines: [
            InvoiceLine(name: "Quantité nulle", quantity: 0, unitPrice: 100, vatRate: 20),
            InvoiceLine(name: "Taux zéro", quantity: 1, unitPrice: 100, vatRate: 0, vatCategory: .zeroRated)
        ])
        inv.issueDate = Date().addingTimeInterval(10 * 86400)
        inv.dueDate = inv.issueDate.addingTimeInterval(30 * 86400)
        inv.paymentIBAN = "FR7630006000011234567890188"
        let found = ruleIDs(inv)
        for id in ["BT-2-FUTURE", "BT-129-POSITIVE", "BT-152-ZERO", "BT-84-IBAN"] {
            XCTAssertTrue(found.contains(id), id)
        }

        var settlement = invoice()
        settlement.type = .finalSettlement
        XCTAssertTrue(ruleIDs(settlement).contains("BT-113-SOLDE"))
    }
}
