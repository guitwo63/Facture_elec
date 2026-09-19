import XCTest
@testable import FacturXCore

/// Deuxième incrément du mécanisme "réglage global + surcharge par société" (Réglages >
/// Tables) — voir `ValueTableSocietyOverrideTests.swift` pour les 6 stores "résolveur par
/// id". Ici : les stores "catalogue" (`TagStore`, `PaymentTermsPresetStore`, liste complète
/// superposée par id) et "dictionnaire" (`KindColorStore`).
final class ValueTableSocietyOverrideCatalogTests: XCTestCase {

    private let keys = [
        "facturx.tags.v1", "facturx.tags.bysociety.v1",
        "facturx.paymentTermsPresets.v1", "facturx.paymentTermsPresets.bysociety.v1",
        "facturx.kindcolors.v1", "facturx.kindcolors.bysociety.v1",
    ]

    override func setUp() {
        super.setUp()
        keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
    }

    override func tearDown() {
        keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
        super.tearDown()
    }

    // MARK: - TagStore

    func testTagStoreListForNilCompanyReturnsGlobalOnly() {
        let store = TagStore()
        store.upsert(PartyTag(name: "VIP", hexColor: "AAAAAA"))
        XCTAssertEqual(store.list(for: nil).map(\.name), ["VIP"])
    }

    func testTagStoreOverrideCustomizesExistingTagOnlyForItsCompany() {
        let store = TagStore()
        let global = PartyTag(name: "VIP", hexColor: "AAAAAA")
        store.upsert(global)
        let cidA = UUID(); let cidB = UUID()

        var customized = global
        customized.hexColor = "BBBBBB"
        store.setOverride(customized, companyID: cidA)

        XCTAssertEqual(store.list(for: cidA).first(where: { $0.id == global.id })?.hexColor, "BBBBBB")
        XCTAssertEqual(store.list(for: cidB).first(where: { $0.id == global.id })?.hexColor, "AAAAAA")
        XCTAssertEqual(store.list(for: nil).first(where: { $0.id == global.id })?.hexColor, "AAAAAA")
    }

    func testTagStoreOverrideCanAddACompanyOnlyTag() {
        let store = TagStore()
        let cid = UUID()
        let companyOnly = PartyTag(name: "Filiale uniquement", hexColor: "CCCCCC")
        store.setOverride(companyOnly, companyID: cid)

        XCTAssertTrue(store.list(for: cid).contains { $0.id == companyOnly.id })
        XCTAssertFalse(store.list(for: nil).contains { $0.id == companyOnly.id })
        XCTAssertEqual(store.tag(id: companyOnly.id, companyID: cid)?.name, "Filiale uniquement")
        XCTAssertNil(store.tag(id: companyOnly.id, companyID: nil))
    }

    func testTagStoreRemoveOverrideRevertsToGlobal() {
        let store = TagStore()
        let global = PartyTag(name: "VIP", hexColor: "AAAAAA")
        store.upsert(global)
        let cid = UUID()
        var customized = global
        customized.hexColor = "BBBBBB"
        store.setOverride(customized, companyID: cid)

        store.removeOverride(id: global.id, companyID: cid)
        XCTAssertEqual(store.list(for: cid).first(where: { $0.id == global.id })?.hexColor, "AAAAAA")
    }

    func testTagStoreOverridesPersistAcrossReload() {
        let store = TagStore()
        let cid = UUID()
        let tag = PartyTag(name: "Persisté", hexColor: "DDDDDD")
        store.setOverride(tag, companyID: cid)

        let reloaded = TagStore()
        XCTAssertEqual(reloaded.tag(id: tag.id, companyID: cid)?.name, "Persisté")
    }

    // MARK: - PaymentTermsPresetStore

    func testPaymentTermsPresetListForNilCompanyReturnsGlobalDefaults() {
        let store = PaymentTermsPresetStore()
        XCTAssertEqual(store.list(for: nil).map(\.id), PaymentTermsPresetStore.defaults.map(\.id))
    }

    func testPaymentTermsPresetOverrideScopedToCompany() {
        let store = PaymentTermsPresetStore()
        let cidA = UUID(); let cidB = UUID()
        var custom = store.presets.first { $0.id == "net30" }!
        custom.text = "Paiement à 30 jours net (filiale)"
        store.setOverride(custom, companyID: cidA)

        XCTAssertEqual(store.list(for: cidA).first(where: { $0.id == "net30" })?.text, "Paiement à 30 jours net (filiale)")
        XCTAssertNotEqual(store.list(for: cidB).first(where: { $0.id == "net30" })?.text, "Paiement à 30 jours net (filiale)")
        XCTAssertEqual(
            store.matchingPresetID(for: "Paiement à 30 jours net (filiale)", companyID: cidA),
            "net30"
        )
        XCTAssertNil(store.matchingPresetID(for: "Paiement à 30 jours net (filiale)", companyID: cidB))
    }

    func testPaymentTermsPresetOverridesPersistAcrossReload() {
        let store = PaymentTermsPresetStore()
        let cid = UUID()
        var custom = store.presets.first { $0.id == "comptant" }!
        custom.label = "Comptant (filiale)"
        store.setOverride(custom, companyID: cid)

        let reloaded = PaymentTermsPresetStore()
        XCTAssertEqual(reloaded.list(for: cid).first(where: { $0.id == "comptant" })?.label, "Comptant (filiale)")
    }

    // MARK: - KindColorStore

    func testKindColorNoOverrideFallsBackToGlobal() {
        let store = KindColorStore()
        let cid = UUID()
        XCTAssertEqual(store.hexColor(for: .client, companyID: cid), store.hexColor(for: .client))
    }

    func testKindColorOverrideScopedToCompany() {
        let store = KindColorStore()
        let cidA = UUID(); let cidB = UUID()
        store.setOverride(hexColor: "123456", for: .fournisseur, companyID: cidA)

        XCTAssertEqual(store.hexColor(for: .fournisseur, companyID: cidA), "123456")
        XCTAssertNotEqual(store.hexColor(for: .fournisseur, companyID: cidB), "123456")
        XCTAssertNotEqual(store.hexColor(for: .fournisseur, companyID: nil), "123456")
    }

    func testKindColorRemoveOverrideRevertsToGlobal() {
        let store = KindColorStore()
        let cid = UUID()
        store.setOverride(hexColor: "654321", for: .client, companyID: cid)
        store.removeOverride(for: .client, companyID: cid)
        XCTAssertEqual(store.hexColor(for: .client, companyID: cid), store.hexColor(for: .client))
    }

    func testKindColorOverridesPersistAcrossReload() {
        let store = KindColorStore()
        let cid = UUID()
        store.setOverride(hexColor: "789ABC", for: .societe, companyID: cid)

        let reloaded = KindColorStore()
        XCTAssertEqual(reloaded.hexColor(for: .societe, companyID: cid), "789ABC")
    }
}
