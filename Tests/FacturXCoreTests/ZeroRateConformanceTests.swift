import XCTest
import FacturXCore

/// Lignes à 0 % que la PDP rejetait alors que l'application les laissait exporter. Chaque cas
/// a été reproduit le 2026-09-23 sur le XML de `CIIXMLGenerator` avec le Schematron EN16931
/// officiel (Factur-X 1.09, paquet `factur-x` + saxonche) ; BR-S-05 et BR-Z-02 ont aussi été
/// confirmés sur l'API de validation SUPER PDP.
final class ZeroRateConformanceTests: XCTestCase {

    private let motif = "Exonération de TVA, article 261-4-4° du CGI"

    private func party(_ name: String, vatNumber: String? = nil, siren: String) -> InvoiceParty {
        InvoiceParty(name: name, street: "1 rue A", postcode: "75001", city: "Paris", country: "FR",
                     vatNumber: vatNumber, siren: siren)
    }

    private func invoice(_ lines: [InvoiceLine], sellerVAT: String? = "FR44732829320") -> Invoice {
        Invoice(number: "2026-0099", seller: party("Vendeur", vatNumber: sellerVAT, siren: "732829320"),
                buyer: party("Client", siren: "303265045"), lines: lines)
    }

    /// Ventilations d'en-tête (BG-23) du XML : catégorie → éléments enfants (nom local → valeur).
    private func headerTaxes(_ xml: Data) throws -> [String: [String: String]] {
        let doc = try XMLDocument(data: xml)
        let nodes = try doc.nodes(forXPath: "//*[local-name()='ApplicableHeaderTradeSettlement']/*[local-name()='ApplicableTradeTax']")
        return nodes.compactMap { $0 as? XMLElement }.reduce(into: [:]) { result, element in
            let fields = (element.children ?? []).compactMap { $0 as? XMLElement }
                .reduce(into: [String: String]()) { $0[$1.localName ?? ""] = $1.stringValue ?? "" }
            result[fields["CategoryCode"] ?? "?"] = fields
        }
    }

    // MARK: - BR-Z-10 / BR-S-10 : pas de motif d'exonération en Z ni en S

    /// On choisit E, on tape un motif, puis on repasse en Z dans le menu Catégorie : le champ
    /// disparaît mais la ligne garde son motif, qui partait dans la ventilation Z (BR-Z-10).
    func testLeftoverReasonIsNotEmittedForZeroRatedOrStandardCategories() throws {
        var backToZero = InvoiceLine(name: "Formation", quantity: 1, unitPrice: 100, vatRate: 0, vatCategory: .exempt,
                                     vatExemptionReason: motif)
        backToZero.vatCategory = .zeroRated
        let exempt = InvoiceLine(name: "Soins", quantity: 1, unitPrice: 50, vatRate: 0, vatCategory: .exempt,
                                 vatExemptionReason: motif)
        let standard = InvoiceLine(name: "Conseil", quantity: 1, unitPrice: 100, vatRate: 20, vatCategory: .standard,
                                   vatExemptionReason: "reliquat")
        let inv = invoice([backToZero, exempt, standard])

        let breakdown = inv.vatBreakdown
        XCTAssertNil(breakdown.first { $0.category == .zeroRated }?.exemptionReason, "BR-Z-10")
        XCTAssertNil(breakdown.first { $0.category == .standard }?.exemptionReason, "BR-S-10")
        XCTAssertEqual(breakdown.first { $0.category == .exempt }?.exemptionReason, motif, "BR-E-10 : le motif E reste")

        let taxes = try headerTaxes(CIIXMLGenerator().generate(invoice: inv))
        XCTAssertEqual(taxes.count, 3)
        XCTAssertNil(taxes["Z"]?["ExemptionReason"])
        XCTAssertNil(taxes["S"]?["ExemptionReason"])
        XCTAssertEqual(taxes["E"]?["ExemptionReason"], motif)

        XCTAssertEqual(inv.lines[0].vatExemptionReason, motif, "donnée intacte : revenir à E retrouve le motif")
    }

    /// Même ventilation, donc même correction, pour les commandes (Order-X).
    func testLeftoverReasonIsNotEmittedInOrders() throws {
        let order = SalesOrder(number: "CD-1", buyer: party("Client", siren: "303265045"),
                               seller: party("Vendeur", vatNumber: "FR44732829320", siren: "732829320"),
                               lines: [InvoiceLine(name: "Formation", quantity: 1, unitPrice: 100, vatRate: 0,
                                                   vatCategory: .zeroRated, vatExemptionReason: motif)])
        XCTAssertNil(order.vatBreakdown.first?.exemptionReason)
        let xml = String(decoding: try OrderCIOXMLGenerator().generate(order: order), as: UTF8.self)
        XCTAssertFalse(xml.contains("ExemptionReason"), xml)
    }

    // MARK: - BR-S-05 : taux strictement positif en catégorie S

    /// Ligne à 0 % mise en « S — Taux normal » dans le menu Catégorie : la PDP la rejette
    /// (confirmé sur l'API SUPER PDP), l'app l'exportait.
    func testStandardCategoryWithZeroRateBlocksExport() {
        let line = InvoiceLine(name: "Formation", quantity: 1, unitPrice: 100, vatRate: 0, vatCategory: .standard)
        let rule = EN16931BusinessRules.evaluate(invoice: invoice([line])).first { $0.ruleId == "BR-S-05" }
        XCTAssertEqual(rule?.severity, .error)
        XCTAssertTrue(rule?.message.contains("Ligne 1") ?? false, rule?.message ?? "")
        XCTAssertFalse(FacturXValidator().validate(invoice: invoice([line])).isValid)
    }

    func testStandardCategoryWithPositiveRateIsFine() {
        let rules = EN16931BusinessRules.evaluate(invoice: invoice([
            InvoiceLine(name: "Conseil", quantity: 1, unitPrice: 100, vatRate: 20),
            InvoiceLine(name: "Livre", quantity: 1, unitPrice: 100, vatRate: 5.5),
            InvoiceLine(name: "Formation", quantity: 1, unitPrice: 100, vatRate: 0, vatCategory: .exempt, vatExemptionReason: motif),
        ]))
        XCTAssertFalse(rules.contains { $0.ruleId == "BR-S-05" })
    }

    /// Le menu Catégorie d'une ligne à 0 % ne propose plus S, sauf à une ligne déjà en S,
    /// qu'il doit pouvoir afficher avant correction.
    func testZeroRateCategoryChoicesLeaveOutStandard() {
        for category in VATCategory.allCases where category != .standard {
            XCTAssertEqual(VATCategory.zeroRateChoices(current: category), [.zeroRated, .exempt, .reverseCharge, .intraCommunity, .export, .outOfScope],
                           category.rawValue)
        }
        XCTAssertEqual(VATCategory.zeroRateChoices(current: .standard), VATCategory.allCases)
    }
}
