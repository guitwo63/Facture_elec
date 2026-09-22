import XCTest
@testable import FacturXCore

/// Incrément 4.5 (dernier de la Zone 4) du chantier "Réglages par société" —
/// `PCloudSettings` rejoint le principe défaut + surcharge par société. Même patron que
/// `SuperPDPCredentialsSocietyOverrideTests.swift`.
final class PCloudCredentialsSocietyOverrideTests: XCTestCase {

    private let keys = [
        "facturx.pcloud.credentials.v1",
        "facturx.pcloud.credentials.bysociety.v1",
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

    private func customCredentials(username: String) -> PCloudCredentials {
        var creds = PCloudCredentials()
        creds.username = username
        creds.password = "secret"
        return creds
    }

    func testCredentialsForNilCompanyReturnsGlobalDefault() {
        let settings = PCloudSettings()
        settings.credentials = customCredentials(username: "global@example.com")

        XCTAssertEqual(settings.credentials(for: nil).username, "global@example.com")
    }

    func testOverrideCustomizesCredentialsOnlyForItsCompany() {
        let settings = PCloudSettings()
        let cidA = UUID(); let cidB = UUID()
        settings.setOverride(customCredentials(username: "societe-a@example.com"), companyID: cidA)

        XCTAssertEqual(settings.credentials(for: cidA).username, "societe-a@example.com")
        XCTAssertNotEqual(settings.credentials(for: cidB).username, "societe-a@example.com")
        XCTAssertNotEqual(settings.credentials(for: nil).username, "societe-a@example.com")
    }

    func testRemoveOverrideRevertsToInherited() {
        let settings = PCloudSettings()
        let cid = UUID()
        settings.setOverride(customCredentials(username: "societe-a@example.com"), companyID: cid)

        settings.removeOverride(companyID: cid)

        XCTAssertEqual(settings.credentials(for: cid).username, settings.credentials.username)
    }

    func testOverridesPersistAcrossReload() {
        let settings = PCloudSettings()
        let cid = UUID()
        settings.setOverride(customCredentials(username: "societe-a@example.com"), companyID: cid)

        let reloaded = PCloudSettings()
        XCTAssertEqual(reloaded.credentials(for: cid).username, "societe-a@example.com")
    }

    /// `PCloudSettings` a une méthode `load()` séparée en plus de `init()` (unique parmi les
    /// 4 services) — vérifie qu'elle recharge aussi les surcharges par société.
    func testExplicitLoadAlsoReloadsCredentialsBySociety() {
        let settings = PCloudSettings()
        let cid = UUID()
        settings.setOverride(customCredentials(username: "societe-a@example.com"), companyID: cid)

        let other = PCloudSettings()
        other.credentialsBySociety = [:]
        other.load()

        XCTAssertEqual(other.credentials(for: cid).username, "societe-a@example.com")
    }

    func testNilResolvesToPrincipaleOverrideWhenDesignated() {
        let principaleID = designatePrincipale()
        let settings = PCloudSettings()
        settings.setOverride(customCredentials(username: "principale@example.com"), companyID: principaleID)

        XCTAssertEqual(settings.credentials(for: nil).username, "principale@example.com")
    }

    func testOtherCompanyDoesNotInheritFromPrincipale() {
        let principaleID = designatePrincipale()
        let settings = PCloudSettings()
        settings.setOverride(customCredentials(username: "principale@example.com"), companyID: principaleID)

        let otherCompany = UUID()
        XCTAssertNotEqual(settings.credentials(for: otherCompany).username, "principale@example.com")
    }
}
