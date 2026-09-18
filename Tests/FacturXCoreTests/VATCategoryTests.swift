import XCTest
@testable import FacturXCore

/// `Invoice.vatCategory(for:)` déduisait la catégorie EN16931 (BT-151) uniquement
/// du taux (0 % -> Z, sinon S) : impossible de distinguer une autoliquidation,
/// une exportation ou une exonération, qui affichent toutes un taux à 0 % mais
/// nécessitent un code et un motif d'exonération (BT-120) différents. Pire : le
/// code par ligne (`ram:SpecifiedLineTradeSettlement/.../CategoryCode`) était
/// carrément figé à "S" dans les générateurs XML, quel que soit le taux. Ces
/// tests verrouillent le nouveau modèle par ligne.
final class VATCategoryTests: XCTestCase {

    private func party(_ name: String) -> InvoiceParty {
        InvoiceParty(name: name, street: "1 rue A", postcode: "75001", city: "Paris", country: "FR")
    }

    // MARK: - InvoiceLine

    func testDefaultCategoryInferredFromRateWhenNotSpecified() {
        XCTAssertEqual(InvoiceLine(name: "A", quantity: 1, unitPrice: 100, vatRate: 20).vatCategory, .standard)
        XCTAssertEqual(InvoiceLine(name: "A", quantity: 1, unitPrice: 100, vatRate: 0).vatCategory, .zeroRated)
    }

    func testExplicitCategoryOverridesRateInference() {
        let line = InvoiceLine(name: "Export", quantity: 1, unitPrice: 100, vatRate: 0, vatCategory: .export,
                                vatExemptionReason: "Exportation hors UE")
        XCTAssertEqual(line.vatCategory, .export)
        XCTAssertEqual(line.vatExemptionReason, "Exportation hors UE")
    }

    func testRequiresExemptionReasonOnlyForNonStandardNonZeroCategories() {
        XCTAssertFalse(VATCategory.standard.requiresExemptionReason)
        XCTAssertFalse(VATCategory.zeroRated.requiresExemptionReason)
        for category: VATCategory in [.exempt, .reverseCharge, .intraCommunity, .export, .outOfScope] {
            XCTAssertTrue(category.requiresExemptionReason, "\(category.rawValue) doit exiger un motif d'exonération")
        }
    }

    func testDecodingLegacyDataWithoutCategoryInfersFromRate() throws {
        let legacyStandardJSON = """
        {"name":"A","quantity":1,"unitPrice":100,"vatRate":20}
        """
        let standard = try JSONDecoder().decode(InvoiceLine.self, from: Data(legacyStandardJSON.utf8))
        XCTAssertEqual(standard.vatCategory, .standard)

        let legacyZeroJSON = """
        {"name":"A","quantity":1,"unitPrice":100,"vatRate":0}
        """
        let zero = try JSONDecoder().decode(InvoiceLine.self, from: Data(legacyZeroJSON.utf8))
        XCTAssertEqual(zero.vatCategory, .zeroRated)
        XCTAssertNil(zero.vatExemptionReason)
    }

    func testDecodingIgnoresUnknownCategoryRawValue() throws {
        let json = """
        {"name":"A","quantity":1,"unitPrice":100,"vatRate":20,"vatCategory":"NOPE"}
        """
        let decoded = try JSONDecoder().decode(InvoiceLine.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.vatCategory, .standard, "retombe sur l'inférence par taux si la valeur brute est inconnue")
    }

    // MARK: - vatBreakdown (Invoice)

    func testVatBreakdownGroupsSameRateDifferentCategoriesSeparately() {
        let inv = Invoice(
            number: "F-1", seller: party("V"), buyer: party("A"),
            lines: [
                InvoiceLine(name: "Zéro-rated", quantity: 1, unitPrice: 100, vatRate: 0, vatCategory: .zeroRated),
                InvoiceLine(name: "Autoliquidation", quantity: 1, unitPrice: 200, vatRate: 0, vatCategory: .reverseCharge,
                            vatExemptionReason: "Autoliquidation, article 283-2 du CGI")
            ]
        )
        let breakdown = inv.vatBreakdown
        XCTAssertEqual(breakdown.count, 2, "deux catégories différentes au même taux -> deux sous-totaux distincts")
        let zeroGroup = breakdown.first { $0.category == .zeroRated }
        let aeGroup = breakdown.first { $0.category == .reverseCharge }
        XCTAssertEqual(zeroGroup?.basis, 100)
        XCTAssertNil(zeroGroup?.exemptionReason)
        XCTAssertEqual(aeGroup?.basis, 200)
        XCTAssertEqual(aeGroup?.exemptionReason, "Autoliquidation, article 283-2 du CGI")
    }

    func testVatBreakdownMergesSameRateAndCategory() {
        let inv = Invoice(
            number: "F-1", seller: party("V"), buyer: party("A"),
            lines: [
                InvoiceLine(name: "L1", quantity: 1, unitPrice: 100, vatRate: 20),
                InvoiceLine(name: "L2", quantity: 1, unitPrice: 50, vatRate: 20)
            ]
        )
        XCTAssertEqual(inv.vatBreakdown.count, 1)
        XCTAssertEqual(inv.vatBreakdown.first?.basis, 150)
    }

    // MARK: - Conversion (Quote -> Invoice / Order)

    func testToInvoicePreservesLineVATCategoryAndReason() {
        let quote = Quote(
            number: "DEV-1", seller: party("V"), buyer: party("A"),
            lines: [InvoiceLine(name: "Export", quantity: 1, unitPrice: 100, vatRate: 0, vatCategory: .export,
                                 vatExemptionReason: "Exportation hors UE")]
        )
        let invoice = quote.toInvoice(number: "F-1")
        XCTAssertEqual(invoice.lines.first?.vatCategory, .export)
        XCTAssertEqual(invoice.lines.first?.vatExemptionReason, "Exportation hors UE")
    }

    // MARK: - EN16931BusinessRules

    private func sampleInvoice(lines: [InvoiceLine]) -> Invoice {
        Invoice(number: "F-1", seller: party("Vendeur"), buyer: party("Acheteur"), lines: lines)
    }

    func testBusinessRulesRequireExemptionReasonForReverseCharge() {
        let inv = sampleInvoice(lines: [
            InvoiceLine(name: "Prestation", quantity: 1, unitPrice: 100, vatRate: 0, vatCategory: .reverseCharge)
        ])
        let rules = EN16931BusinessRules.evaluate(invoice: inv)
        XCTAssertTrue(rules.contains { $0.ruleId == "BR-AE-05" && $0.severity == .error },
                     "un motif d'exonération est obligatoire pour l'autoliquidation")
    }

    func testBusinessRulesPassWhenExemptionReasonProvided() {
        let inv = sampleInvoice(lines: [
            InvoiceLine(name: "Prestation", quantity: 1, unitPrice: 100, vatRate: 0, vatCategory: .reverseCharge,
                        vatExemptionReason: "Autoliquidation, article 283-2 du CGI")
        ])
        let rules = EN16931BusinessRules.evaluate(invoice: inv)
        XCTAssertFalse(rules.contains { $0.ruleId == "BR-AE-05" })
    }

    func testBusinessRulesDoNotRequireReasonForZeroRatedOrStandard() {
        let inv = sampleInvoice(lines: [
            InvoiceLine(name: "Standard", quantity: 1, unitPrice: 100, vatRate: 20),
            InvoiceLine(name: "Zéro-rated", quantity: 1, unitPrice: 50, vatRate: 0, vatCategory: .zeroRated)
        ])
        let rules = EN16931BusinessRules.evaluate(invoice: inv)
        XCTAssertFalse(rules.contains { $0.ruleId.hasSuffix("-05") })
    }

    // MARK: - CIIXMLGenerator / OrderCIOXMLGenerator

    func testXMLLineAndBreakdownUseTheLinesActualCategoryNotHardcodedS() throws {
        let inv = sampleInvoice(lines: [
            InvoiceLine(name: "Livraison UE", quantity: 1, unitPrice: 100, vatRate: 0, vatCategory: .intraCommunity,
                        vatExemptionReason: "Livraison intracommunautaire, article 262 ter I du CGI")
        ])
        let data = try CIIXMLGenerator().generate(invoice: inv)
        let xml = String(data: data, encoding: .utf8) ?? ""
        XCTAssertTrue(xml.contains("<ram:CategoryCode>K</ram:CategoryCode>"),
                     "la catégorie de la ligne doit être K (intracommunautaire), pas S en dur")
        XCTAssertTrue(xml.contains("<ram:ExemptionReason>Livraison intracommunautaire, article 262 ter I du CGI</ram:ExemptionReason>"))
    }

    func testOrderXMLLineUsesTheLinesActualCategory() throws {
        let order = SalesOrder(
            number: "CMD-1", buyer: party("A"), seller: party("V"),
            lines: [InvoiceLine(name: "Export", quantity: 1, unitPrice: 100, vatRate: 0, vatCategory: .export,
                                 vatExemptionReason: "Exportation hors UE")]
        )
        let data = try OrderCIOXMLGenerator().generate(order: order)
        let xml = String(data: data, encoding: .utf8) ?? ""
        XCTAssertTrue(xml.contains("<ram:CategoryCode>G</ram:CategoryCode>"),
                     "la catégorie de la ligne doit être G (export), pas S en dur")
    }
}
