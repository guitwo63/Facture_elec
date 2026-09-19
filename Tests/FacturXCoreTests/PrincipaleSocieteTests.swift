import XCTest
@testable import FacturXCore

/// Incrément F.1 du chantier "Réglages par société" — désignation d'une société principale,
/// qui remplace le défaut global abstrait comme repli pour tous les réglages par société non
/// personnalisés (voir `PartyDirectory.principaleSocieteID`/`setPrincipale(_:)`).
final class PrincipaleSocieteTests: XCTestCase {

    private let directoryKey = "facturx.directory.v1"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: directoryKey)
        UserDefaults.standard.removeObject(forKey: "facturx.directory.societeInterco.migrated.v1")
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: directoryKey)
        UserDefaults.standard.removeObject(forKey: "facturx.directory.societeInterco.migrated.v1")
        super.tearDown()
    }

    private func party(_ name: String) -> InvoiceParty {
        InvoiceParty(name: name, street: "", postcode: "", city: "")
    }

    func testNoPrincipaleByDefault() {
        let directory = PartyDirectory()
        let a = DirectoryEntry(kinds: [.societe], party: party("A"))
        directory.upsert(a)

        XCTAssertNil(directory.principaleSocieteID)
    }

    func testSetPrincipaleDesignatesTheSociete() {
        let directory = PartyDirectory()
        let a = DirectoryEntry(kinds: [.societe], party: party("A"))
        directory.upsert(a)

        directory.setPrincipale(a.id)

        XCTAssertEqual(directory.principaleSocieteID, a.id)
        XCTAssertTrue(directory.entries.first { $0.id == a.id }!.isPrincipale)
    }

    func testSetPrincipaleOnAnotherSocieteClearsThePrevious() {
        let directory = PartyDirectory()
        let a = DirectoryEntry(kinds: [.societe], party: party("A"))
        let b = DirectoryEntry(kinds: [.societe], party: party("B"))
        directory.upsert(a)
        directory.upsert(b)

        directory.setPrincipale(a.id)
        directory.setPrincipale(b.id)

        XCTAssertEqual(directory.principaleSocieteID, b.id)
        XCTAssertFalse(directory.entries.first { $0.id == a.id }!.isPrincipale)
        XCTAssertTrue(directory.entries.first { $0.id == b.id }!.isPrincipale)
    }

    func testClearPrincipaleRemovesTheDesignation() {
        let directory = PartyDirectory()
        let a = DirectoryEntry(kinds: [.societe], party: party("A"))
        directory.upsert(a)
        directory.setPrincipale(a.id)

        directory.clearPrincipale()

        XCTAssertNil(directory.principaleSocieteID)
        XCTAssertFalse(directory.entries.first { $0.id == a.id }!.isPrincipale)
    }

    func testDeletingThePrincipaleSocieteClearsTheDesignation() {
        let directory = PartyDirectory()
        let a = DirectoryEntry(kinds: [.societe], party: party("A"))
        directory.upsert(a)
        directory.setPrincipale(a.id)

        directory.delete(a)

        XCTAssertNil(directory.principaleSocieteID)
    }

    func testPrincipaleDesignationPersistsAcrossReload() {
        let directory = PartyDirectory()
        let a = DirectoryEntry(kinds: [.societe], party: party("A"))
        directory.upsert(a)
        directory.setPrincipale(a.id)

        let reloaded = PartyDirectory()

        XCTAssertEqual(reloaded.principaleSocieteID, a.id)
    }

    func testDecodingLegacyEntryWithoutIsPrincipaleDefaultsToFalse() throws {
        let json = """
        [{"id":"\(UUID().uuidString)","kinds":["societe"],"party":{"name":"A","street":"","postcode":"","city":""}}]
        """
        let decoded = try JSONDecoder().decode([DirectoryEntry].self, from: Data(json.utf8))

        XCTAssertEqual(decoded.first?.isPrincipale, false)
    }

    func testIsPrincipaleRoundTripsThroughCodable() throws {
        var entry = DirectoryEntry(kinds: [.societe], party: party("A"))
        entry.isPrincipale = true

        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(DirectoryEntry.self, from: data)

        XCTAssertTrue(decoded.isPrincipale)
    }
}
