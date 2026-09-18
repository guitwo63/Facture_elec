import XCTest
@testable import FacturXCore

/// Teste `SuperPDPService.parseInvoiceList`/`mapInvoiceListItem` en isolation (sans appel
/// réseau), même esprit que `SuperPDPDirectoryMappingTests` pour `mapDirectoryEntry` —
/// première méthode ajoutée pour couvrir la réception de factures (`GET /v1.beta/invoices`,
/// jusqu'ici documentée mais non intégrée).
final class SuperPDPInvoiceListTests: XCTestCase {

    func testEnvelopeWithDataKey() throws {
        let json = #"{"data":[{"id":"inv-1","status":"processed"}]}"#.data(using: .utf8)!
        let result = try SuperPDPService().parseInvoiceList(data: json, defaultDirection: .received)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].remoteID, "inv-1")
        XCTAssertEqual(result[0].status, "processed")
    }

    func testEnvelopeWithInvoicesKey() throws {
        let json = #"{"invoices":[{"id":"inv-2","status":"pending"}]}"#.data(using: .utf8)!
        let result = try SuperPDPService().parseInvoiceList(data: json, defaultDirection: .received)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].remoteID, "inv-2")
    }

    func testEnvelopeWithResultsKey() throws {
        let json = #"{"results":[{"id":"inv-3","status":"pending"}]}"#.data(using: .utf8)!
        let result = try SuperPDPService().parseInvoiceList(data: json, defaultDirection: .received)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].remoteID, "inv-3")
    }

    func testBareArrayEnvelope() throws {
        let json = #"[{"id":"inv-4","status":"pending"},{"id":"inv-5","status":"processed"}]"#.data(using: .utf8)!
        let result = try SuperPDPService().parseInvoiceList(data: json, defaultDirection: .received)
        XCTAssertEqual(result.count, 2)
    }

    func testUnrecognizedEnvelopeYieldsEmptyRatherThanThrowing() throws {
        let json = #"{"something_else": []}"#.data(using: .utf8)!
        let result = try SuperPDPService().parseInvoiceList(data: json, defaultDirection: .received)
        XCTAssertTrue(result.isEmpty)
    }

    func testMalformedJSONThrowsDecodingError() {
        let malformed = "not json at all".data(using: .utf8)!
        XCTAssertThrowsError(try SuperPDPService().parseInvoiceList(data: malformed, defaultDirection: .received)) { error in
            guard case SuperPDPError.decoding = error else {
                return XCTFail("attendu .decoding, obtenu \(error)")
            }
        }
    }

    func testDirectionDefaultsWhenAbsentFromPayload() {
        let item = SuperPDPService().mapInvoiceListItem(["id": "inv-6", "status": "pending"], defaultDirection: .received)
        XCTAssertEqual(item.direction, .received)
    }

    func testDirectionFromPayloadOverridesDefault() {
        let item = SuperPDPService().mapInvoiceListItem(["id": "inv-7", "status": "pending", "direction": "sent"], defaultDirection: .received)
        XCTAssertEqual(item.direction, .sent)
    }

    func testMissingRemoteIDFallsBackToGeneratedID() {
        let item = SuperPDPService().mapInvoiceListItem(["status": "pending"], defaultDirection: .received)
        XCTAssertNil(item.remoteID)
        XCTAssertFalse(item.id.isEmpty, "un identifiant local doit toujours être généré même sans id distant")
    }
}
