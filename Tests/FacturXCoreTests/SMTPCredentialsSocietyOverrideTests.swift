import XCTest
@testable import FacturXCore

/// Incrément 4.4 du chantier "Réglages par société" — `SMTPSettings` rejoint le principe
/// défaut + surcharge par société. Même patron que `SuperPDPCredentialsSocietyOverrideTests.swift`.
final class SMTPCredentialsSocietyOverrideTests: XCTestCase {

    private let keys = [
        "facturx.smtp.credentials.v1",
        "facturx.smtp.credentials.bysociety.v1",
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

    private func customCredentials(host: String) -> SMTPCredentials {
        var creds = SMTPCredentials()
        creds.host = host
        creds.username = "user@\(host)"
        creds.password = "secret"
        return creds
    }

    func testCredentialsForNilCompanyReturnsGlobalDefault() {
        let settings = SMTPSettings()
        settings.credentials = customCredentials(host: "global.example.com")

        XCTAssertEqual(settings.credentials(for: nil).host, "global.example.com")
    }

    func testOverrideCustomizesCredentialsOnlyForItsCompany() {
        let settings = SMTPSettings()
        let cidA = UUID(); let cidB = UUID()
        settings.setOverride(customCredentials(host: "societe-a.example.com"), companyID: cidA)

        XCTAssertEqual(settings.credentials(for: cidA).host, "societe-a.example.com")
        XCTAssertNotEqual(settings.credentials(for: cidB).host, "societe-a.example.com")
        XCTAssertNotEqual(settings.credentials(for: nil).host, "societe-a.example.com")
    }

    func testRemoveOverrideRevertsToInherited() {
        let settings = SMTPSettings()
        let cid = UUID()
        settings.setOverride(customCredentials(host: "societe-a.example.com"), companyID: cid)

        settings.removeOverride(companyID: cid)

        XCTAssertEqual(settings.credentials(for: cid).host, settings.credentials.host)
    }

    func testOverridesPersistAcrossReload() {
        let settings = SMTPSettings()
        let cid = UUID()
        settings.setOverride(customCredentials(host: "societe-a.example.com"), companyID: cid)

        let reloaded = SMTPSettings()
        XCTAssertEqual(reloaded.credentials(for: cid).host, "societe-a.example.com")
    }

    func testNilResolvesToPrincipaleOverrideWhenDesignated() {
        let principaleID = designatePrincipale()
        let settings = SMTPSettings()
        settings.setOverride(customCredentials(host: "principale.example.com"), companyID: principaleID)

        XCTAssertEqual(settings.credentials(for: nil).host, "principale.example.com")
    }

    func testOtherCompanyDoesNotInheritFromPrincipale() {
        let principaleID = designatePrincipale()
        let settings = SMTPSettings()
        settings.setOverride(customCredentials(host: "principale.example.com"), companyID: principaleID)

        let otherCompany = UUID()
        XCTAssertNotEqual(settings.credentials(for: otherCompany).host, "principale.example.com")
    }
}
