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

    /// Régression : repérée en conditions réelles via SUPER PDP (rejet BR-Z-05/BR-Z-09) sur une
    /// facture dont une ligne avait été créée à taux 0 % (catégorie Z auto-inférée) puis vue son
    /// taux changé vers une valeur non nulle par un sélecteur de TVA qui ne recalait pas la
    /// catégorie (le cas de "Facture guidée" avant correction). Le validateur interne affichait
    /// "Conforme" malgré cette incohérence — cette règle comble le trou.
    func testBusinessRulesFlagZeroRatedCategoryWithNonZeroRate() {
        let inv = sampleInvoice(lines: [
            InvoiceLine(name: "Ligne mal recalée", quantity: 1, unitPrice: 100, vatRate: 20, vatCategory: .zeroRated)
        ])
        let rules = EN16931BusinessRules.evaluate(invoice: inv)
        XCTAssertTrue(rules.contains { $0.ruleId == "BR-Z-05" && $0.severity == .error },
                     "catégorie Z avec un taux non nul doit être signalé en erreur, pas laissé passer silencieusement")
    }

    func testBusinessRulesFlagNonStandardCategoryWithNonZeroRateGenerically() {
        let inv = sampleInvoice(lines: [
            InvoiceLine(name: "Autoliquidation mal recalée", quantity: 1, unitPrice: 100, vatRate: 20, vatCategory: .reverseCharge,
                        vatExemptionReason: "Autoliquidation, article 283-2 du CGI")
        ])
        let rules = EN16931BusinessRules.evaluate(invoice: inv)
        XCTAssertTrue(rules.contains { $0.ruleId == "BR-AE-RATE" && $0.severity == .error },
                     "toute catégorie non standard implique un taux nul, même quand le motif d'exonération est renseigné")
    }

    /// Régression : repérée en conditions réelles via SUPER PDP (rejet BR-E-02) sur une
    /// facture avec une ligne exonérée dont l'émetteur n'avait pas de n° TVA — le validateur
    /// local ne couvrait déjà ce cas que pour la catégorie standard (BR-S-02), pas pour
    /// Exonérée, découvert seulement au dépôt via la validation distante.
    func testBusinessRulesFlagExemptLineWithoutSellerVATNumber() {
        let inv = sampleInvoice(lines: [
            InvoiceLine(name: "Prestation exonérée", quantity: 1, unitPrice: 100, vatRate: 0, vatCategory: .exempt,
                        vatExemptionReason: "Exonération, article 293 B du CGI")
        ])
        let rules = EN16931BusinessRules.evaluate(invoice: inv)
        XCTAssertTrue(rules.contains { $0.ruleId == "BR-E-02" && $0.severity == .error },
                     "une ligne exonérée oblige l'émetteur à avoir un n° TVA, comme BR-S-02 pour le taux standard")
    }

    /// Régression : repérée en conditions réelles via SUPER PDP (rejet BR-CO-09) sur une
    /// facture dont le n° TVA de l'émetteur ne commençait pas par un préfixe pays valide.
    func testBusinessRulesFlagSellerVATNumberWithInvalidCountryPrefix() {
        var seller = party("Vendeur")
        seller.vatNumber = "XX123456789"
        let inv = Invoice(number: "F-1", seller: seller, buyer: party("Acheteur"),
                          lines: [InvoiceLine(name: "Prestation", quantity: 1, unitPrice: 100, vatRate: 20)])
        let rules = EN16931BusinessRules.evaluate(invoice: inv)
        XCTAssertTrue(rules.contains { $0.ruleId == "BR-CO-09" && $0.severity == .error })
    }

    func testBusinessRulesFlagBuyerVATNumberWithInvalidCountryPrefix() {
        var buyer = party("Acheteur")
        buyer.vatNumber = "12345678901"
        let inv = Invoice(number: "F-1", seller: party("Vendeur"), buyer: buyer,
                          lines: [InvoiceLine(name: "Prestation", quantity: 1, unitPrice: 100, vatRate: 20)])
        let rules = EN16931BusinessRules.evaluate(invoice: inv)
        XCTAssertTrue(rules.contains { $0.ruleId == "BR-CO-09" && $0.severity == .error })
    }

    func testBusinessRulesAcceptValidOrMissingVATNumberPrefixes() {
        var seller = party("Vendeur")
        seller.vatNumber = "FR12345678901"
        let inv = Invoice(number: "F-1", seller: seller, buyer: party("Acheteur"),
                          lines: [InvoiceLine(name: "Prestation", quantity: 1, unitPrice: 100, vatRate: 20)])
        let rules = EN16931BusinessRules.evaluate(invoice: inv)
        XCTAssertFalse(rules.contains { $0.ruleId == "BR-CO-09" })
    }

    func testBusinessRulesDoNotFlagExemptLineWhenSellerHasVATNumber() {
        var seller = party("Vendeur")
        seller.vatNumber = "FR12345678901"
        let inv = Invoice(number: "F-1", seller: seller, buyer: party("Acheteur"), lines: [
            InvoiceLine(name: "Prestation exonérée", quantity: 1, unitPrice: 100, vatRate: 0, vatCategory: .exempt,
                        vatExemptionReason: "Exonération, article 293 B du CGI")
        ])
        let rules = EN16931BusinessRules.evaluate(invoice: inv)
        XCTAssertFalse(rules.contains { $0.ruleId == "BR-E-02" })
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

    // MARK: - Migration des données existantes (InvoiceStore/OrderStore/QuoteStore)

    /// Régression concrète : une facture créée avant le correctif du 2026-09-18 avait une
    /// ligne à vatRate=20 mais vatCategory=.zeroRated (rejetée BR-Z-05/BR-Z-09 par SUPER PDP).
    /// Comme le sélecteur de catégorie n'est visible qu'à taux 0 %, rien dans l'UI ne
    /// permettait de voir ni corriger cette incohérence déjà enregistrée — d'où la migration
    /// automatique au chargement, plutôt qu'une correction manuelle ligne par ligne.
    func testInvoiceStoreAutoCorrectsInconsistentCategoryOnLoad() {
        let key = "facturx.invoices.v1"
        UserDefaults.standard.removeObject(forKey: key)
        defer { UserDefaults.standard.removeObject(forKey: key) }

        let seedStore = InvoiceStore()
        var invoice = seedStore.newDraft()
        invoice.lines = [InvoiceLine(name: "Ligne corrompue", quantity: 1, unitPrice: 100, vatRate: 20,
                                      vatCategory: .zeroRated, vatExemptionReason: "reliquat incohérent")]
        seedStore.upsert(invoice)

        let reloaded = InvoiceStore()
        let fixedLine = reloaded.invoices.first(where: { $0.id == invoice.id })?.lines.first
        XCTAssertEqual(fixedLine?.vatCategory, .standard)
        XCTAssertNil(fixedLine?.vatExemptionReason)
    }

    func testOrderStoreAutoCorrectsInconsistentCategoryOnLoad() {
        let key = "orderx.orders.v1"
        UserDefaults.standard.removeObject(forKey: key)
        defer { UserDefaults.standard.removeObject(forKey: key) }

        let seedStore = OrderStore()
        var order = seedStore.newDraft()
        order.lines = [InvoiceLine(name: "Ligne corrompue", quantity: 1, unitPrice: 100, vatRate: 20,
                                    vatCategory: .reverseCharge, vatExemptionReason: "reliquat incohérent")]
        seedStore.upsert(order)

        let reloaded = OrderStore()
        let fixedLine = reloaded.orders.first(where: { $0.id == order.id })?.lines.first
        XCTAssertEqual(fixedLine?.vatCategory, .standard)
        XCTAssertNil(fixedLine?.vatExemptionReason)
    }

    func testQuoteStoreAutoCorrectsInconsistentCategoryOnLoad() {
        let key = "facturx.quotes.v1"
        UserDefaults.standard.removeObject(forKey: key)
        defer { UserDefaults.standard.removeObject(forKey: key) }

        let seedStore = QuoteStore()
        var quote = seedStore.newDraft(seller: party("Vendeur"))
        quote.lines = [InvoiceLine(name: "Ligne corrompue", quantity: 1, unitPrice: 100, vatRate: 20,
                                    vatCategory: .export, vatExemptionReason: "reliquat incohérent")]
        seedStore.upsert(quote)

        let reloaded = QuoteStore()
        let fixedLine = reloaded.quotes.first(where: { $0.id == quote.id })?.lines.first
        XCTAssertEqual(fixedLine?.vatCategory, .standard)
        XCTAssertNil(fixedLine?.vatExemptionReason)
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
