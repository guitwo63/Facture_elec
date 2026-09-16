import XCTest
@testable import FacturXCore

final class SuperPDPDirectoryMappingTests: XCTestCase {

    func testFlatResponseMapsNameDirectly() {
        let dict: [String: Any] = ["name": "ACME SAS", "siren": "123456789"]
        let entry = SuperPDPService().mapDirectoryEntry(dict)
        XCTAssertEqual(entry.name, "ACME SAS")
        XCTAssertEqual(entry.siren, "123456789")
    }

    func testNestedPartyResponseFallsBackForName() {
        // Reproduit le bug signalé : la recherche renvoyait des lignes "sans
        // dénomination" quand le nom est niché sous "party" plutôt qu'à plat.
        let dict: [String: Any] = [
            "id": "abc-123",
            "party": [
                "name": "ACME SAS",
                "siren": "123456789",
                "city": "Paris"
            ]
        ]
        let entry = SuperPDPService().mapDirectoryEntry(dict)
        XCTAssertEqual(entry.name, "ACME SAS", "le nom niché sous « party » doit être retrouvé")
        XCTAssertEqual(entry.siren, "123456789")
        XCTAssertEqual(entry.city, "Paris")
    }

    func testNestedCompanyResponseFallsBackForName() {
        let dict: [String: Any] = [
            "id": "abc-123",
            "company": ["name": "ACME SAS"]
        ]
        let entry = SuperPDPService().mapDirectoryEntry(dict)
        XCTAssertEqual(entry.name, "ACME SAS")
    }

    func testFlatNameTakesPrecedenceOverNested() {
        let dict: [String: Any] = [
            "name": "Nom à plat",
            "party": ["name": "Nom imbriqué"]
        ]
        let entry = SuperPDPService().mapDirectoryEntry(dict)
        XCTAssertEqual(entry.name, "Nom à plat")
    }
}
