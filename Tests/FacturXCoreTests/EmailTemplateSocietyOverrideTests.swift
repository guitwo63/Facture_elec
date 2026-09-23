import XCTest
@testable import FacturXCore

/// Incrément 0.1 du chantier "Réglages par société" — `EmailTemplateStore` rejoint le
/// principe défaut + surcharge par société (voir `SocietyScopedCatalog` et
/// `ValueTableSocietyOverrideCatalogTests.swift` pour le même patron sur `TagStore`/
/// `PaymentTermsPresetStore`), construit nativement avec la société principale (F.1/F.2).
final class EmailTemplateSocietyOverrideTests: XCTestCase {

    private let keys = [
        "facturx.email.templates.enabled.v1",
        "facturx.email.templates.v1",
        "facturx.email.templates.bysociety.v1",
        "facturx.directory.v1",
        "facturx.directory.societeInterco.migrated.v1",
    ]

    override func setUp() {
        super.setUp()
        keys.forEach { AppPersistence.defaults.removeObject(forKey: $0) }
        PartyDirectory.shared.entries = []
    }

    override func tearDown() {
        PartyDirectory.shared.entries = []
        keys.forEach { AppPersistence.defaults.removeObject(forKey: $0) }
        super.tearDown()
    }

    private func party(_ name: String) -> InvoiceParty {
        InvoiceParty(name: name, street: "", postcode: "", city: "")
    }

    @discardableResult
    private func designatePrincipale(_ name: String = "Principale") -> UUID {
        let entry = DirectoryEntry(kinds: [.societe], party: party(name))
        PartyDirectory.shared.upsert(entry)
        PartyDirectory.shared.setPrincipale(entry.id)
        return entry.id
    }

    func testTemplateForNilCompanyReturnsGlobalDefault() {
        let store = EmailTemplateStore()
        XCTAssertEqual(store.template(for: .quoteSent, companyID: nil).subject, EmailTemplateKind.quoteSent.defaultSubject)
    }

    func testOverrideCustomizesTemplateOnlyForItsCompany() {
        let store = EmailTemplateStore()
        let cidA = UUID(); let cidB = UUID()
        var custom = store.template(for: .quoteSent)
        custom.subject = "Votre devis personnalisé {{numero}}"
        store.setOverride(custom, companyID: cidA)

        XCTAssertEqual(store.template(for: .quoteSent, companyID: cidA).subject, "Votre devis personnalisé {{numero}}")
        XCTAssertNotEqual(store.template(for: .quoteSent, companyID: cidB).subject, "Votre devis personnalisé {{numero}}")
        XCTAssertNotEqual(store.template(for: .quoteSent, companyID: nil).subject, "Votre devis personnalisé {{numero}}")
    }

    func testRemoveOverrideRevertsToGlobal() {
        let store = EmailTemplateStore()
        let cid = UUID()
        var custom = store.template(for: .invoiceSent)
        custom.enabled = false
        store.setOverride(custom, companyID: cid)

        store.removeOverride(kind: .invoiceSent, companyID: cid)

        XCTAssertTrue(store.template(for: .invoiceSent, companyID: cid).enabled)
    }

    func testOverridesPersistAcrossReload() {
        let store = EmailTemplateStore()
        let cid = UUID()
        var custom = store.template(for: .orderConfirmation)
        custom.body = "Corps personnalisé"
        store.setOverride(custom, companyID: cid)

        let reloaded = EmailTemplateStore()
        XCTAssertEqual(reloaded.template(for: .orderConfirmation, companyID: cid).body, "Corps personnalisé")
    }

    func testIsSendEnabledScopedToCompany() {
        let store = EmailTemplateStore()
        let cid = UUID()
        var custom = store.template(for: .deliveryNotice)
        custom.enabled = false
        store.setOverride(custom, companyID: cid)

        XCTAssertFalse(store.isSendEnabled(.deliveryNotice, companyID: cid))
        XCTAssertTrue(store.isSendEnabled(.deliveryNotice, companyID: UUID()))
    }

    // MARK: - Héritage société principale (voir SocietePrincipaleInheritanceTests.swift)

    func testNilResolvesToPrincipaleOverrideWhenDesignated() {
        let principaleID = designatePrincipale()
        let store = EmailTemplateStore()
        var custom = store.template(for: .invoiceSent)
        custom.subject = "Sujet de la société principale"
        store.setOverride(custom, companyID: principaleID)

        XCTAssertEqual(store.template(for: .invoiceSent, companyID: nil).subject, "Sujet de la société principale")
    }

    func testListForNilResolvesToPrincipaleOverridesWhenDesignated() {
        let principaleID = designatePrincipale()
        let store = EmailTemplateStore()
        var custom = store.template(for: .quoteSent)
        custom.subject = "Devis — société principale"
        store.setOverride(custom, companyID: principaleID)

        XCTAssertEqual(store.list(for: nil).first(where: { $0.kind == .quoteSent })?.subject, "Devis — société principale")
    }

    func testOtherCompanyDoesNotInheritFromPrincipale() {
        let principaleID = designatePrincipale()
        let store = EmailTemplateStore()
        var custom = store.template(for: .invoiceSent)
        custom.subject = "Sujet de la société principale"
        store.setOverride(custom, companyID: principaleID)

        let otherCompany = UUID()
        XCTAssertNotEqual(store.template(for: .invoiceSent, companyID: otherCompany).subject, "Sujet de la société principale")
    }
}
