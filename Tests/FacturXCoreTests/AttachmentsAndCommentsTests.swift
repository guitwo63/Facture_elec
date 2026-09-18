import XCTest
@testable import FacturXCore

final class AttachmentsAndCommentsTests: XCTestCase {

    private func party(_ name: String) -> InvoiceParty {
        InvoiceParty(name: name, street: "1 rue A", postcode: "75001", city: "Paris", country: "FR")
    }

    // MARK: - Attachment

    func testAttachmentRoundTripsThroughJSON() throws {
        let original = Attachment(fileName: "devis-signe.pdf", data: Data("contenu".utf8))
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Attachment.self, from: encoded)
        XCTAssertEqual(decoded.fileName, original.fileName)
        XCTAssertEqual(decoded.data, original.data)
        XCTAssertEqual(decoded.id, original.id)
    }

    func testAttachmentSizeDescriptionIsHumanReadable() {
        let attachment = Attachment(fileName: "x.pdf", data: Data(repeating: 0, count: 2048))
        XCTAssertFalse(attachment.sizeDescription.isEmpty)
    }

    // MARK: - Migration (données existantes sans attachments/internalComment)

    func testDecodingInvoiceWithoutAttachmentsFieldsDefaultsEmpty() throws {
        let legacyJSON = """
        {"id":"\(UUID().uuidString)","number":"F-1",
         "seller":{"name":"S","street":"","postcode":"","city":"","country":"FR","legalSchemeID":"0002","endpointSchemeID":"0225"},
         "buyer":{"name":"B","street":"","postcode":"","city":"","country":"FR","legalSchemeID":"0002","endpointSchemeID":"0225"}}
        """
        let decoded = try JSONDecoder().decode(Invoice.self, from: Data(legacyJSON.utf8))
        XCTAssertTrue(decoded.attachments.isEmpty)
        XCTAssertNil(decoded.internalComment)
    }

    func testDecodingOrderWithoutAttachmentsFieldsDefaultsEmpty() throws {
        let legacyJSON = """
        {"id":"\(UUID().uuidString)","number":"CD-1",
         "seller":{"name":"S","street":"","postcode":"","city":"","country":"FR","legalSchemeID":"0002","endpointSchemeID":"0225"},
         "buyer":{"name":"B","street":"","postcode":"","city":"","country":"FR","legalSchemeID":"0002","endpointSchemeID":"0225"}}
        """
        let decoded = try JSONDecoder().decode(SalesOrder.self, from: Data(legacyJSON.utf8))
        XCTAssertTrue(decoded.attachments.isEmpty)
        XCTAssertNil(decoded.internalComment)
    }

    func testDecodingQuoteWithoutAttachmentsFieldsDefaultsEmpty() throws {
        let legacyJSON = """
        {"id":"\(UUID().uuidString)","number":"DEV-1",
         "seller":{"name":"S","street":"","postcode":"","city":"","country":"FR","legalSchemeID":"0002","endpointSchemeID":"0225"},
         "buyer":{"name":"B","street":"","postcode":"","city":"","country":"FR","legalSchemeID":"0002","endpointSchemeID":"0225"}}
        """
        let decoded = try JSONDecoder().decode(Quote.self, from: Data(legacyJSON.utf8))
        XCTAssertTrue(decoded.attachments.isEmpty)
        XCTAssertNil(decoded.internalComment)
    }

    // MARK: - Round-trip avec pièces jointes et commentaire

    func testInvoiceRoundTripsAttachmentsAndInternalComment() throws {
        var invoice = Invoice(number: "F-1", seller: party("V"), buyer: party("A"))
        invoice.attachments = [Attachment(fileName: "bon.pdf", data: Data("x".utf8))]
        invoice.internalComment = "À relancer la semaine prochaine"

        let encoded = try JSONEncoder().encode(invoice)
        let decoded = try JSONDecoder().decode(Invoice.self, from: encoded)
        XCTAssertEqual(decoded.attachments.count, 1)
        XCTAssertEqual(decoded.attachments.first?.fileName, "bon.pdf")
        XCTAssertEqual(decoded.internalComment, "À relancer la semaine prochaine")
    }
}
