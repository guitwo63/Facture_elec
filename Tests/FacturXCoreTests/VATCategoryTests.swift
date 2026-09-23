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
        XCTAssertTrue(rules.contains { $0.ruleId == "BR-AE-10" && $0.severity == .error },
                     "un motif d'exonération est obligatoire pour l'autoliquidation")
    }

    func testBusinessRulesPassWhenExemptionReasonProvided() {
        let inv = sampleInvoice(lines: [
            InvoiceLine(name: "Prestation", quantity: 1, unitPrice: 100, vatRate: 0, vatCategory: .reverseCharge,
                        vatExemptionReason: "Autoliquidation, article 283-2 du CGI")
        ])
        let rules = EN16931BusinessRules.evaluate(invoice: inv)
        XCTAssertFalse(rules.contains { $0.ruleId == "BR-AE-10" })
    }

    func testBusinessRulesDoNotRequireReasonForZeroRatedOrStandard() {
        let inv = sampleInvoice(lines: [
            InvoiceLine(name: "Standard", quantity: 1, unitPrice: 100, vatRate: 20),
            InvoiceLine(name: "Zéro-rated", quantity: 1, unitPrice: 50, vatRate: 0, vatCategory: .zeroRated)
        ])
        let rules = EN16931BusinessRules.evaluate(invoice: inv)
        // Ni motif d'exonération exigé (BR-<cat>-10) ni taux incohérent (BR-<cat>-05).
        XCTAssertFalse(rules.contains { ["BR-S-10", "BR-Z-10", "BR-Z-05"].contains($0.ruleId) })
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
        XCTAssertTrue(rules.contains { $0.ruleId == "BR-AE-05" && $0.severity == .error },
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

    // MARK: - FacturXValidator.totalErrorCount

    /// Régression : le panneau "Validation locale échouée" affichait « 0 erreur(s) » — un
    /// message contradictoire — quand la seule cause d'échec était une règle métier
    /// (ex. BR-CO-09) sans qu'aucune des vérifications propres à FacturXValidator.errors ne
    /// soit elle-même en défaut. `isValid` tenait déjà compte de `businessRules`, mais les
    /// messages affichés ne comptaient que `errors.count` — `totalErrorCount` comble l'écart.
    func testTotalErrorCountIncludesBusinessRuleErrorsNotJustPlainErrors() {
        var seller = InvoiceParty(name: "Vendeur", street: "1 rue A", postcode: "75001", city: "Paris", country: "FR", siren: "123456789")
        seller.vatNumber = "XX123456789" // préfixe pays invalide -> BR-CO-09, aucune autre erreur
        let buyer = InvoiceParty(name: "Acheteur", street: "2 rue B", postcode: "75002", city: "Paris", country: "FR", siren: "987654321")
        let inv = Invoice(number: "F-1", seller: seller, buyer: buyer,
                          lines: [InvoiceLine(name: "Prestation", quantity: 1, unitPrice: 100, vatRate: 20)])
        let result = FacturXValidator().validate(invoice: inv)
        XCTAssertFalse(result.isValid, "une erreur de règle métier doit invalider le résultat")
        XCTAssertEqual(result.errors.count, 0, "aucune des vérifications directes de errors n'est en cause ici")
        XCTAssertEqual(result.totalErrorCount, 1, "totalErrorCount doit refléter l'erreur BR-CO-09, pas afficher 0")
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

    // MARK: - Catégorie O « Hors champ de TVA » (règles BR-O-* des Schematron officiels)

    // Reproduit le 2026-09-23 avec le Schematron officiel (`Factur-X_1.09_EN16931.xsl`) sur le
    // XML de l'application : BR-O-05 (taux sur la ligne), BR-O-02 (n° TVA des parties) et
    // BR-O-11/BR-O-12 (O mêlée à une autre catégorie), alors que l'export était autorisé.

    private let outOfScopeReason = "Opération hors champ d'application de la TVA"

    private func outOfScopeLine(_ name: String = "Débours refacturés", unitPrice: Double = 150) -> InvoiceLine {
        InvoiceLine(name: name, quantity: 1, unitPrice: unitPrice, vatRate: 0, vatCategory: .outOfScope,
                    vatExemptionReason: outOfScopeReason)
    }

    /// Parties identifiées par leur SIREN ; n° TVA (BT-31, BT-48) seulement si fournis.
    private func makeInvoice(_ lines: [InvoiceLine], sellerVAT: String? = nil, buyerVAT: String? = nil,
                             profile: FacturXProfile = .en16931) -> Invoice {
        var seller = party("Vendeur")
        seller.siren = "123456782"
        seller.vatNumber = sellerVAT
        var buyer = party("Acheteur")
        buyer.siren = "987654324"
        buyer.vatNumber = buyerVAT
        return Invoice(number: "F-O-1", profile: profile, seller: seller, buyer: buyer, lines: lines)
    }

    /// Chaque `ram:ApplicableTradeTax` du XML généré : sur une ligne ou dans la ventilation
    /// d'en-tête (BG-23), avec ses éléments enfants (nom local → valeur).
    private func tradeTaxes(_ invoice: Invoice) throws -> [(inLine: Bool, fields: [String: String])] {
        let doc = try XMLDocument(data: CIIXMLGenerator().generate(invoice: invoice))
        return try doc.nodes(forXPath: "//*[local-name()='ApplicableTradeTax']").compactMap { node in
            guard let element = node as? XMLElement else { return nil }
            let fields = (element.children ?? []).compactMap { $0 as? XMLElement }
                .reduce(into: [String: String]()) { $0[$1.localName ?? ""] = $1.stringValue ?? "" }
            return (element.parent?.localName == "SpecifiedLineTradeSettlement", fields)
        }
    }

    /// BR-O-05 : « An Invoice line (BG-25) where the VAT category code (BT-151) is "Not subject
    /// to VAT" shall not contain an Invoiced item VAT rate (BT-152) ». Règle présente aussi dans
    /// le Schematron EXTENDED.
    func testOutOfScopeLineCarriesNoVATRate() throws {
        for profile: FacturXProfile in [.en16931, .extended] {
            let lineTaxes = try tradeTaxes(makeInvoice([outOfScopeLine()], profile: profile)).filter(\.inLine)
            XCTAssertEqual(lineTaxes.count, 1)
            XCTAssertEqual(lineTaxes.first?.fields["CategoryCode"], "O")
            XCTAssertNil(lineTaxes.first?.fields["RateApplicablePercent"], "BR-O-05 (\(profile.rawValue)) : pas de taux (BT-152) sur une ligne O")
        }
    }

    /// Ventilation BG-23 de la catégorie O : BT-119 y est facultatif (BR-48 l'exige « except if
    /// the Invoice is not subject to VAT », aucune règle ne l'interdit) et omis comme BT-152 ;
    /// montant nul (BR-O-09), base = somme des lignes O (BR-O-08), motif présent (BR-O-10).
    func testOutOfScopeBreakdownHasNoRateZeroAmountAndExemptionReason() throws {
        let invoice = makeInvoice([outOfScopeLine(), outOfScopeLine("Frais de dossier", unitPrice: 37.5)])
        let header = try tradeTaxes(invoice).filter { !$0.inLine }
        XCTAssertEqual(header.count, 1, "BR-O-01 : une seule ventilation O")
        XCTAssertEqual(header.first?.fields["CategoryCode"], "O")
        XCTAssertNil(header.first?.fields["RateApplicablePercent"])
        XCTAssertEqual(header.first?.fields["CalculatedAmount"], "0.00")
        XCTAssertEqual(header.first?.fields["BasisAmount"], "187.50")
        XCTAssertEqual(header.first?.fields["ExemptionReason"], outOfScopeReason)
    }

    /// Seule la catégorie O perd son taux : les autres le gardent, sur la ligne (BT-152) comme
    /// dans la ventilation (BT-119, exigé par BR-48).
    func testOtherCategoriesKeepTheirVATRate() throws {
        let invoice = makeInvoice([
            InvoiceLine(name: "Standard", quantity: 1, unitPrice: 100, vatRate: 20),
            InvoiceLine(name: "Taux zéro", quantity: 1, unitPrice: 100, vatRate: 0, vatCategory: .zeroRated),
            InvoiceLine(name: "Autoliquidation", quantity: 1, unitPrice: 100, vatRate: 0, vatCategory: .reverseCharge,
                        vatExemptionReason: "Autoliquidation, article 283-2 du CGI"),
        ], sellerVAT: "FR11123456782")
        let taxes = try tradeTaxes(invoice)
        XCTAssertEqual(taxes.count, 6, "3 lignes + 3 ventilations")
        for tax in taxes {
            XCTAssertNotNil(tax.fields["RateApplicablePercent"], "catégorie \(tax.fields["CategoryCode"] ?? "?") sans taux")
        }
    }

    /// Ligne sans taux, comme l'exige BR-O-05 (facture reçue d'un fournisseur, ou émise par
    /// l'application) : relue à 0 %, et non aux 20 % par défaut du parseur, qui rendaient la
    /// ligne incohérente (catégorie O à 20 %, TVA recalculée non nulle).
    func testParserReadsLineWithoutRateAsZeroForNonStandardCategory() throws {
        func reparsedWithoutRates(_ invoice: Invoice) throws -> Invoice {
            let xml = String(decoding: try CIIXMLGenerator().generate(invoice: invoice), as: UTF8.self)
                .replacingOccurrences(of: "<ram:RateApplicablePercent>[^<]*</ram:RateApplicablePercent>", with: "",
                                      options: .regularExpression)
            XCTAssertFalse(xml.contains("RateApplicablePercent"))
            return try CIIXMLParser().parse(xml: Data(xml.utf8))
        }

        let outOfScope = try reparsedWithoutRates(makeInvoice([outOfScopeLine()]))
        XCTAssertEqual(outOfScope.lines.first?.vatCategory, .outOfScope)
        XCTAssertEqual(outOfScope.lines.first?.vatRate, 0)
        XCTAssertEqual(outOfScope.lines.first?.vatExemptionReason, outOfScopeReason, "BT-120 repris de la ventilation d'en-tête")
        XCTAssertEqual(outOfScope.taxTotal, 0)

        let zeroRated = try reparsedWithoutRates(makeInvoice([
            InvoiceLine(name: "Taux zéro", quantity: 1, unitPrice: 100, vatRate: 0, vatCategory: .zeroRated)
        ]))
        XCTAssertEqual(zeroRated.lines.first?.vatRate, 0)
    }

    /// BR-O-02 : une facture ayant une ligne O ne porte ni le n° TVA de l'émetteur (BT-31) ni
    /// celui de l'acheteur (BT-48). Bloquant : c'est à l'utilisateur de les retirer.
    func testBusinessRulesBlockVATNumbersOnOutOfScopeInvoice() {
        func rule(sellerVAT: String?, buyerVAT: String?) -> BusinessRuleResult? {
            EN16931BusinessRules.evaluate(invoice: makeInvoice([outOfScopeLine()], sellerVAT: sellerVAT, buyerVAT: buyerVAT))
                .first { $0.ruleId == "BR-O-02" }
        }
        let seller = rule(sellerVAT: "FR11123456782", buyerVAT: nil)
        XCTAssertEqual(seller?.severity, .error)
        XCTAssertTrue(seller?.message.contains("de l'émetteur (BT-31)") ?? false)
        XCTAssertFalse(seller?.message.contains("BT-48") ?? true)

        let buyer = rule(sellerVAT: nil, buyerVAT: "FR14987654324")
        XCTAssertTrue(buyer?.message.contains("de l'acheteur (BT-48)") ?? false)
        XCTAssertFalse(buyer?.message.contains("BT-31") ?? true)

        let both = rule(sellerVAT: "FR11123456782", buyerVAT: "FR14987654324")
        XCTAssertTrue(both?.message.contains("celui de l'émetteur (BT-31) et celui de l'acheteur (BT-48)") ?? false,
                      both?.message ?? "")
        XCTAssertNil(rule(sellerVAT: nil, buyerVAT: " "), "un n° TVA blanc compte comme absent, comme pour BR-S-02 et BR-E-02")
        XCTAssertFalse(FacturXValidator().validate(invoice: makeInvoice([outOfScopeLine()], sellerVAT: "FR11123456782")).isValid)
    }

    /// BR-O-11 / BR-O-12 : aucune autre catégorie dans une facture hors champ. Aucun XML
    /// conforme n'existe pour ce mélange : l'export doit être bloqué.
    func testBusinessRulesBlockMixingOutOfScopeWithOtherCategories() {
        let mixed = makeInvoice([
            InvoiceLine(name: "Prestation", quantity: 1, unitPrice: 100, vatRate: 20),
            outOfScopeLine(),
        ], sellerVAT: "FR11123456782")
        let rule = EN16931BusinessRules.evaluate(invoice: mixed).first { $0.ruleId == "BR-O-12" }
        XCTAssertEqual(rule?.severity, .error)
        XCTAssertTrue(rule?.message.contains("ligne(s) 1)") ?? false, "la ligne d'une autre catégorie est citée : \(rule?.message ?? "")")
        XCTAssertFalse(FacturXValidator().validate(invoice: mixed).isValid)
    }

    /// Une facture entièrement hors champ et sans n° TVA reste exportable.
    func testOutOfScopeOnlyInvoiceWithoutVATNumbersIsExportable() {
        let invoice = makeInvoice([outOfScopeLine(), outOfScopeLine("Frais de dossier", unitPrice: 37.5)])
        XCTAssertFalse(EN16931BusinessRules.evaluate(invoice: invoice).contains { $0.ruleId.hasPrefix("BR-O-") })
        let result = FacturXValidator().validate(invoice: invoice)
        XCTAssertTrue(result.isValid, "\(result.errors) \(result.businessRules.filter { $0.severity == .error }.map(\.message))")
    }

    /// Le Schematron EXTENDED ne contient ni BR-O-02 ni BR-O-11/12 (seulement BR-O-05 à 07 et
    /// BR-O-09/10) : n° TVA et mélange de catégories y restent admis.
    func testExtendedProfileAdmitsVATNumbersAndMixedCategoriesWithOutOfScope() {
        let invoice = makeInvoice([
            InvoiceLine(name: "Prestation", quantity: 1, unitPrice: 100, vatRate: 20),
            outOfScopeLine(),
        ], sellerVAT: "FR11123456782", buyerVAT: "FR14987654324", profile: .extended)
        XCTAssertFalse(EN16931BusinessRules.evaluate(invoice: invoice).contains { ["BR-O-02", "BR-O-12"].contains($0.ruleId) })
        let result = FacturXValidator().validate(invoice: invoice)
        XCTAssertTrue(result.isValid, "\(result.errors) \(result.businessRules.filter { $0.severity == .error }.map(\.message))")
    }
}
