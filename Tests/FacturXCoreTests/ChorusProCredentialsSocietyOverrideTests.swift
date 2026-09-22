import XCTest
@testable import FacturXCore

/// Incrément 4.3 du chantier "Réglages par société" — `ChorusProSettings` rejoint le principe
/// défaut + surcharge par société. Même patron que `SuperPDPCredentialsSocietyOverrideTests.swift`.
final class ChorusProCredentialsSocietyOverrideTests: XCTestCase {

    private let keys = [
        "facturx.choruspro.credentials.v1",
        "facturx.choruspro.credentials.bysociety.v1",
        "facturx.directory.v1",
        "facturx.directory.societeInterco.migrated.v1",
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

    @discardableResult
    private func designatePrincipale(_ name: String = "Principale") -> UUID {
        let entry = DirectoryEntry(kinds: [.societe], party: party(name))
        PartyDirectory.shared.upsert(entry)
        PartyDirectory.shared.setPrincipale(entry.id)
        return entry.id
    }

    func testCredentialsForNilCompanyReturnsGlobalDefault() {
        let settings = ChorusProSettings()
        settings.credentials = ChorusProCredentials(clientID: "global-id", clientSecret: "global-secret")

        XCTAssertEqual(settings.credentials(for: nil).clientID, "global-id")
    }

    func testOverrideCustomizesCredentialsOnlyForItsCompany() {
        let settings = ChorusProSettings()
        let cidA = UUID(); let cidB = UUID()
        settings.setOverride(ChorusProCredentials(clientID: "societe-a", clientSecret: "secret-a"), companyID: cidA)

        XCTAssertEqual(settings.credentials(for: cidA).clientID, "societe-a")
        XCTAssertNotEqual(settings.credentials(for: cidB).clientID, "societe-a")
        XCTAssertNotEqual(settings.credentials(for: nil).clientID, "societe-a")
    }

    func testRemoveOverrideRevertsToInherited() {
        let settings = ChorusProSettings()
        let cid = UUID()
        settings.setOverride(ChorusProCredentials(clientID: "societe-a", clientSecret: "secret-a"), companyID: cid)

        settings.removeOverride(companyID: cid)

        XCTAssertEqual(settings.credentials(for: cid).clientID, settings.credentials.clientID)
    }

    func testOverridesPersistAcrossReload() {
        let settings = ChorusProSettings()
        let cid = UUID()
        settings.setOverride(ChorusProCredentials(clientID: "societe-a", clientSecret: "secret-a"), companyID: cid)

        let reloaded = ChorusProSettings()
        XCTAssertEqual(reloaded.credentials(for: cid).clientID, "societe-a")
    }

    func testNilResolvesToPrincipaleOverrideWhenDesignated() {
        let principaleID = designatePrincipale()
        let settings = ChorusProSettings()
        settings.setOverride(ChorusProCredentials(clientID: "principale-id", clientSecret: "principale-secret"), companyID: principaleID)

        XCTAssertEqual(settings.credentials(for: nil).clientID, "principale-id")
    }

    func testOtherCompanyDoesNotInheritFromPrincipale() {
        let principaleID = designatePrincipale()
        let settings = ChorusProSettings()
        settings.setOverride(ChorusProCredentials(clientID: "principale-id", clientSecret: "principale-secret"), companyID: principaleID)

        let otherCompany = UUID()
        XCTAssertNotEqual(settings.credentials(for: otherCompany).clientID, "principale-id")
    }
}
