import XCTest
@testable import FacturXCore

/// Incrément F.2 du chantier "Réglages par société" — retrofit des stores déjà livrés en
/// Zone 1 pour que `companyID: nil` résolve désormais sur la société principale (voir
/// `PartyDirectory.principaleSocieteID`) plutôt que sur un défaut global anonyme. Couvre les
/// 3 formes d'accesseur rencontrées (statuts "if let", listes "guard let", dictionnaires) sur
/// un échantillon représentatif plutôt que les 13 sites un par un, qui sont mécaniquement
/// identiques au sein de chaque forme.
///
/// Règle confirmée le 2026-09-23 : SEUL `companyID: nil` résout sur la société principale.
/// Une autre société sans personnalisation propre suit le réglage par défaut, jamais celui
/// de la principale (même règle que le portage ARVERNX-SaaS) — d'où un test « n'hérite pas »
/// pour chaque forme, en plus du test « nil » ; Réglages > Tables et Réglages > Application
/// affichent cette règle et s'appuient dessus.
///
/// Ces stores lisent `PartyDirectory.shared` (le singleton réel, pas une instance injectable)
/// — chaque test nettoie ses propres entrées et la désignation de société principale en
/// `tearDown` pour ne pas polluer les autres tests partageant ce même singleton.
final class SocietePrincipaleInheritanceTests: XCTestCase {

    private let keys = [
        "facturx.directory.v1",
        "facturx.directory.societeInterco.migrated.v1",
        "facturx.invoiceStatuses.v1", "facturx.invoiceStatuses.bysociety.v1",
        "facturx.tags.v1", "facturx.tags.bysociety.v1",
        "facturx.kindcolors.v1", "facturx.kindcolors.bysociety.v1",
        "facturx.paymentTermsPresets.v1", "facturx.paymentTermsPresets.bysociety.v1",
        "facturx.invoices.v1",
        "facturx.number.prefix.v1", "facturx.number.includeyear.v1", "facturx.number.start.v1",
        "facturx.number.useseparator.v1", "facturx.number.overrides.bysociety.v1",
        "orderx.orders.v1", "orderx.buyerSellerSemantics.migrated.v1",
        "orderx.number.prefix.v1", "orderx.number.includeyear.v1", "orderx.number.start.v1",
        "orderx.number.useseparator.v1", "orderx.number.overrides.bysociety.v1",
        "facturx.quotes.v1",
        "facturx.quotes.number.prefix.v1", "facturx.quotes.number.includeyear.v1", "facturx.quotes.number.start.v1",
        "facturx.quotes.number.useseparator.v1", "facturx.quotes.number.overrides.bysociety.v1",
    ]

    override func setUp() {
        super.setUp()
        keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
        PartyDirectory.shared.entries = []
    }

    override func tearDown() {
        PartyDirectory.shared.entries = []
        keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
        super.tearDown()
    }

    private func party(_ name: String) -> InvoiceParty {
        InvoiceParty(name: name, street: "", postcode: "", city: "")
    }

    /// Désigne `societe` comme société principale sur le singleton partagé et retourne son id.
    @discardableResult
    private func designatePrincipale(_ name: String = "Principale") -> UUID {
        let entry = DirectoryEntry(kinds: [.societe], party: party(name))
        PartyDirectory.shared.upsert(entry)
        PartyDirectory.shared.setPrincipale(entry.id)
        return entry.id
    }

    // MARK: - InvoiceStatusStore (forme "if let", résolveur par id)

    func testInvoiceStatusNilResolvesToPrincipaleOverrideWhenDesignated() {
        let principaleID = designatePrincipale()
        let store = InvoiceStatusStore()
        var custom = store.override(for: .accepted)
        custom.hexColor = "112233"
        store.setOverride(custom, companyID: principaleID)

        XCTAssertEqual(store.override(for: .accepted, companyID: nil).hexColor, "112233")
    }

    func testInvoiceStatusNilStillFallsBackToGlobalWhenNoPrincipaleDesignated() {
        let store = InvoiceStatusStore()
        XCTAssertEqual(store.override(for: .accepted, companyID: nil).hexColor, store.override(for: .accepted).hexColor)
    }

    func testInvoiceStatusOtherCompanyDoesNotInheritFromPrincipale() {
        let principaleID = designatePrincipale()
        let store = InvoiceStatusStore()
        var custom = store.override(for: .accepted)
        custom.hexColor = "445566"
        store.setOverride(custom, companyID: principaleID)

        let otherCompany = UUID()
        XCTAssertNotEqual(store.override(for: .accepted, companyID: otherCompany).hexColor, "445566")
    }

    // MARK: - TagStore (forme "guard let", liste complète)

    func testTagStoreListForNilResolvesToPrincipaleOverridesWhenDesignated() {
        let principaleID = designatePrincipale()
        let store = TagStore()
        let global = PartyTag(name: "VIP", hexColor: "AAAAAA")
        store.upsert(global)
        var customized = global
        customized.hexColor = "BBBBBB"
        store.setOverride(customized, companyID: principaleID)

        XCTAssertEqual(store.list(for: nil).first(where: { $0.id == global.id })?.hexColor, "BBBBBB")
    }

    func testTagStoreOtherCompanyDoesNotInheritFromPrincipale() {
        let principaleID = designatePrincipale()
        let store = TagStore()
        let global = PartyTag(name: "VIP", hexColor: "AAAAAA")
        store.upsert(global)
        var customized = global
        customized.hexColor = "BBBBBB"
        store.setOverride(customized, companyID: principaleID)
        let principaleOnly = PartyTag(name: "Principale seulement", hexColor: "CCCCCC")
        store.setOverride(principaleOnly, companyID: principaleID)

        let other = store.list(for: UUID())
        XCTAssertEqual(other.first(where: { $0.id == global.id })?.hexColor, "AAAAAA")
        XCTAssertFalse(other.contains { $0.id == principaleOnly.id })
    }

    // MARK: - KindColorStore (forme dictionnaire)

    func testKindColorNilResolvesToPrincipaleOverrideWhenDesignated() {
        let principaleID = designatePrincipale()
        let store = KindColorStore()
        store.setOverride(hexColor: "CCDDEE", for: .client, companyID: principaleID)

        XCTAssertEqual(store.hexColor(for: .client, companyID: nil), "CCDDEE")
    }

    func testKindColorOtherCompanyDoesNotInheritFromPrincipale() {
        let principaleID = designatePrincipale()
        let store = KindColorStore()
        store.setOverride(hexColor: "CCDDEE", for: .client, companyID: principaleID)

        XCTAssertEqual(store.hexColor(for: .client, companyID: UUID()), store.hexColor(for: .client))
    }

    // MARK: - PaymentTermsPresetStore (forme "guard let", liste complète)

    func testPaymentTermsPresetListForNilResolvesToPrincipaleOverridesWhenDesignated() {
        let principaleID = designatePrincipale()
        let store = PaymentTermsPresetStore()
        var custom = store.presets.first { $0.id == "net30" }!
        custom.text = "Paiement à 30 jours net (principale)"
        store.setOverride(custom, companyID: principaleID)

        XCTAssertEqual(store.list(for: nil).first(where: { $0.id == "net30" })?.text, "Paiement à 30 jours net (principale)")
    }

    func testPaymentTermsPresetOtherCompanyDoesNotInheritFromPrincipale() {
        let principaleID = designatePrincipale()
        let store = PaymentTermsPresetStore()
        let globalText = store.presets.first { $0.id == "net30" }!.text
        var custom = store.presets.first { $0.id == "net30" }!
        custom.text = "Paiement à 30 jours net (principale)"
        store.setOverride(custom, companyID: principaleID)

        XCTAssertEqual(store.list(for: UUID()).first(where: { $0.id == "net30" })?.text, globalText)
    }

    // MARK: - InvoiceStore.numberingFormat (forme dictionnaire, numérotation)

    func testInvoiceNumberingNilResolvesToPrincipaleFormatWhenDesignated() {
        let principaleID = designatePrincipale()
        let store = InvoiceStore()
        let customFormat = InvoiceNumberingFormat(prefix: "PRINC", includeYear: false, start: 1, useSeparator: false)
        store.numberFormatOverrides[principaleID] = customFormat
        store.save()

        XCTAssertEqual(store.numberingFormat(for: nil).prefix, "PRINC")
    }

    func testInvoiceNumberingOtherCompanyDoesNotInheritFromPrincipale() {
        let principaleID = designatePrincipale()
        let store = InvoiceStore()
        store.numberPrefix = "FAC"
        store.numberFormatOverrides[principaleID] = InvoiceNumberingFormat(prefix: "PRINC", includeYear: false, start: 1, useSeparator: false)

        let other = UUID()
        XCTAssertEqual(store.numberingFormat(for: other).prefix, "FAC")
        XCTAssertTrue(store.previewNextNumber(companyID: other).hasPrefix("FAC"))
    }

    // MARK: - Format par défaut (« Toutes » dans Réglages > Application)

    /// L'option « Toutes » affiche et enregistre le format par défaut : son aperçu ne doit
    /// pas montrer celui de la principale, vers lequel `companyID == nil` résout.
    func testInvoiceDefaultNumberingFormatIgnoresPrincipaleOverride() {
        let principaleID = designatePrincipale()
        let store = InvoiceStore()
        store.numberPrefix = "FAC"
        store.numberStart = 7
        store.numberFormatOverrides[principaleID] = InvoiceNumberingFormat(prefix: "PRINC", includeYear: false, start: 1, useSeparator: false)

        XCTAssertEqual(store.numberingFormat(for: nil).prefix, "PRINC")
        XCTAssertEqual(store.defaultNumberingFormat.prefix, "FAC")
        XCTAssertEqual(store.previewNextNumber(), "PRINC0001")
        XCTAssertTrue(store.previewNextNumber(format: store.defaultNumberingFormat).hasPrefix("FAC"))
        XCTAssertTrue(store.previewNextNumber(format: store.defaultNumberingFormat).hasSuffix("0007"))
    }

    func testOrderDefaultNumberingFormatIgnoresPrincipaleOverride() {
        let principaleID = designatePrincipale()
        let store = OrderStore()
        store.numberPrefix = "CD"
        store.numberFormatOverrides[principaleID] = InvoiceNumberingFormat(prefix: "PRINC", includeYear: false, start: 1, useSeparator: false)

        XCTAssertEqual(store.defaultNumberingFormat.prefix, "CD")
        XCTAssertTrue(store.previewNextNumber().hasPrefix("PRINC"))
        XCTAssertTrue(store.previewNextNumber(format: store.defaultNumberingFormat).hasPrefix("CD"))
        XCTAssertTrue(store.previewNextNumber(companyID: UUID()).hasPrefix("CD"))
    }

    func testQuoteDefaultNumberingFormatIgnoresPrincipaleOverride() {
        let principaleID = designatePrincipale()
        let store = QuoteStore()
        store.numberPrefix = "DEV"
        store.numberFormatOverrides[principaleID] = InvoiceNumberingFormat(prefix: "PRINC", includeYear: false, start: 1, useSeparator: false)

        XCTAssertEqual(store.defaultNumberingFormat.prefix, "DEV")
        XCTAssertTrue(store.previewNextNumber().hasPrefix("PRINC"))
        XCTAssertTrue(store.previewNextNumber(format: store.defaultNumberingFormat).hasPrefix("DEV"))
        XCTAssertTrue(store.previewNextNumber(companyID: UUID()).hasPrefix("DEV"))
    }
}
