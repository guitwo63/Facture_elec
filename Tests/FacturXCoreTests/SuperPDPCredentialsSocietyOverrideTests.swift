import XCTest
@testable import FacturXCore

/// Incrément 4.1 du chantier "Réglages par société" — `SuperPDPSettings` rejoint le principe
/// défaut + surcharge par société, comme les 3 numérotations (`InvoiceStore.numberFormatOverrides`
/// et sœurs) : la surcharge remplace la valeur entière (pas de fusion par id, contrairement aux
/// tables de valeurs), construit nativement avec la société principale (F.1/F.2).
final class SuperPDPCredentialsSocietyOverrideTests: XCTestCase {

    private let keys = [
        "facturx.superpdp.credentials.v1",
        "facturx.superpdp.credentials.bysociety.v1",
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

    func testCredentialsForNilCompanyReturnsGlobalDefault() {
        let settings = SuperPDPSettings()
        settings.credentials = SuperPDPCredentials(clientID: "global-id", clientSecret: "global-secret")

        XCTAssertEqual(settings.credentials(for: nil).clientID, "global-id")
    }

    func testOverrideCustomizesCredentialsOnlyForItsCompany() {
        let settings = SuperPDPSettings()
        let cidA = UUID(); let cidB = UUID()
        settings.setOverride(SuperPDPCredentials(clientID: "societe-a", clientSecret: "secret-a"), companyID: cidA)

        XCTAssertEqual(settings.credentials(for: cidA).clientID, "societe-a")
        XCTAssertNotEqual(settings.credentials(for: cidB).clientID, "societe-a")
        XCTAssertNotEqual(settings.credentials(for: nil).clientID, "societe-a")
    }

    func testRemoveOverrideRevertsToInherited() {
        let settings = SuperPDPSettings()
        let cid = UUID()
        settings.setOverride(SuperPDPCredentials(clientID: "societe-a", clientSecret: "secret-a"), companyID: cid)

        settings.removeOverride(companyID: cid)

        XCTAssertEqual(settings.credentials(for: cid).clientID, settings.credentials.clientID)
    }

    func testOverridesPersistAcrossReload() {
        let settings = SuperPDPSettings()
        let cid = UUID()
        settings.setOverride(SuperPDPCredentials(clientID: "societe-a", clientSecret: "secret-a"), companyID: cid)

        let reloaded = SuperPDPSettings()
        XCTAssertEqual(reloaded.credentials(for: cid).clientID, "societe-a")
    }

    // MARK: - Héritage société principale (voir SocietePrincipaleInheritanceTests.swift)

    func testNilResolvesToPrincipaleOverrideWhenDesignated() {
        let principaleID = designatePrincipale()
        let settings = SuperPDPSettings()
        settings.setOverride(SuperPDPCredentials(clientID: "principale-id", clientSecret: "principale-secret"), companyID: principaleID)

        XCTAssertEqual(settings.credentials(for: nil).clientID, "principale-id")
    }

    func testOtherCompanyDoesNotInheritFromPrincipale() {
        let principaleID = designatePrincipale()
        let settings = SuperPDPSettings()
        settings.setOverride(SuperPDPCredentials(clientID: "principale-id", clientSecret: "principale-secret"), companyID: principaleID)

        let otherCompany = UUID()
        XCTAssertNotEqual(settings.credentials(for: otherCompany).clientID, "principale-id")
    }
}
