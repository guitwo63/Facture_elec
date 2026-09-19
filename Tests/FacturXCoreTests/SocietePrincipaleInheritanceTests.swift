import XCTest
@testable import FacturXCore

/// Incrément F.2 du chantier "Réglages par société" — retrofit des stores déjà livrés en
/// Zone 1 pour que `companyID: nil` résolve désormais sur la société principale (voir
/// `PartyDirectory.principaleSocieteID`) plutôt que sur un défaut global anonyme. Couvre les
/// 3 formes d'accesseur rencontrées (statuts "if let", listes "guard let", dictionnaires) sur
/// un échantillon représentatif plutôt que les 13 sites un par un, qui sont mécaniquement
/// identiques au sein de chaque forme.
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
        "facturx.number.overrides.bysociety.v1",
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

    // MARK: - KindColorStore (forme dictionnaire)

    func testKindColorNilResolvesToPrincipaleOverrideWhenDesignated() {
        let principaleID = designatePrincipale()
        let store = KindColorStore()
        store.setOverride(hexColor: "CCDDEE", for: .client, companyID: principaleID)

        XCTAssertEqual(store.hexColor(for: .client, companyID: nil), "CCDDEE")
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

    // MARK: - InvoiceStore.numberingFormat (forme dictionnaire, numérotation)

    func testInvoiceNumberingNilResolvesToPrincipaleFormatWhenDesignated() {
        let principaleID = designatePrincipale()
        let store = InvoiceStore()
        let customFormat = InvoiceNumberingFormat(prefix: "PRINC", includeYear: false, start: 1, useSeparator: false)
        store.numberFormatOverrides[principaleID] = customFormat
        store.save()

        XCTAssertEqual(store.numberingFormat(for: nil).prefix, "PRINC")
    }
}
