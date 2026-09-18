import XCTest
@testable import FacturXCore

final class QuoteModelTests: XCTestCase {

    private func makeQuote(status: QuoteStatus = .draft, validUntilDaysFromNow: Double = 30) -> Quote {
        Quote(
            number: "DEV-2026-001",
            status: status,
            validUntil: Date().addingTimeInterval(validUntilDaysFromNow * 86400),
            seller: InvoiceParty(name: "Vendeur SARL", street: "1 rue A", postcode: "75001", city: "Paris"),
            buyer: InvoiceParty(name: "Client SAS", street: "2 rue B", postcode: "75002", city: "Paris"),
            lines: [
                InvoiceLine(name: "Prestation", quantity: 2, unit: "DAY", unitPrice: 500, vatRate: 20)
            ]
        )
    }

    func testTotalsMatchInvoiceComputation() {
        let quote = makeQuote()
        XCTAssertEqual(quote.lineTotal, 1000, accuracy: 0.001)
        XCTAssertEqual(quote.taxTotal, 200, accuracy: 0.001)
        XCTAssertEqual(quote.grandTotal, 1200, accuracy: 0.001)
    }

    func testDefaultStatusIsDraft() {
        let quote = Quote(number: "DEV-1", seller: InvoiceParty(name: "S", street: "", postcode: "", city: ""), buyer: InvoiceParty(name: "B", street: "", postcode: "", city: ""))
        XCTAssertEqual(quote.status, .draft)
    }

    func testAllowedTransitionsFollowSimpleLifecycle() {
        XCTAssertEqual(QuoteStatus.draft.allowedTransitions(), [.sent])
        XCTAssertEqual(QuoteStatus.sent.allowedTransitions(), [.accepted, .refused, .expired])
        XCTAssertTrue(QuoteStatus.accepted.allowedTransitions().isEmpty)
        XCTAssertTrue(QuoteStatus.refused.allowedTransitions().isEmpty)
        XCTAssertTrue(QuoteStatus.expired.allowedTransitions().isEmpty)
    }

    func testAcceptedAndRefusedLockTheQuote() {
        XCTAssertTrue(QuoteStatus.accepted.locksQuote)
        XCTAssertTrue(QuoteStatus.refused.locksQuote)
        XCTAssertFalse(QuoteStatus.draft.locksQuote)
        XCTAssertFalse(QuoteStatus.sent.locksQuote)
    }

    func testIsExpiredByDateOnlyAppliesToSentQuotesPastValidity() {
        XCTAssertTrue(makeQuote(status: .sent, validUntilDaysFromNow: -1).isExpiredByDate)
        XCTAssertFalse(makeQuote(status: .sent, validUntilDaysFromNow: 1).isExpiredByDate)
        XCTAssertFalse(makeQuote(status: .draft, validUntilDaysFromNow: -1).isExpiredByDate, "un brouillon n'a jamais été envoyé, la validité ne s'applique pas")
        XCTAssertFalse(makeQuote(status: .accepted, validUntilDaysFromNow: -1).isExpiredByDate)
    }

    func testToInvoiceCopiesLinesAndPartiesUnchanged() {
        let quote = makeQuote(status: .accepted)
        let invoice = quote.toInvoice(number: "FAC-2026-042")
        XCTAssertEqual(invoice.number, "FAC-2026-042")
        XCTAssertEqual(invoice.status, .draft, "une facture issue d'un devis démarre toujours en brouillon")
        XCTAssertEqual(invoice.seller.name, quote.seller.name)
        XCTAssertEqual(invoice.buyer.name, quote.buyer.name)
        XCTAssertEqual(invoice.lines.count, quote.lines.count)
        XCTAssertEqual(invoice.grandTotal, quote.grandTotal, accuracy: 0.001)
    }

    func testToOrderCopiesLinesAndPartiesAndKeepsQuotationRef() {
        let quote = makeQuote(status: .accepted)
        let order = quote.toOrder(number: "CD-2026-017")
        XCTAssertEqual(order.number, "CD-2026-017")
        XCTAssertEqual(order.status, .draft, "une commande issue d'un devis démarre toujours en brouillon")
        XCTAssertEqual(order.quotationRef, quote.number, "traçabilité vers le devis d'origine")
        XCTAssertEqual(order.seller.name, quote.seller.name)
        XCTAssertEqual(order.buyer.name, quote.buyer.name)
        XCTAssertEqual(order.lines.count, quote.lines.count)
        XCTAssertEqual(order.grandTotal, quote.grandTotal, accuracy: 0.001)
    }

    func testDecodingToleratesMissingFieldsFromOlderPersistedData() throws {
        let legacyJSON = """
        {"id":"\(UUID().uuidString)","number":"DEV-OLD-1",
         "seller":{"name":"S","street":"","postcode":"","city":"","country":"FR","legalSchemeID":"0002","endpointSchemeID":"0225"},
         "buyer":{"name":"B","street":"","postcode":"","city":"","country":"FR","legalSchemeID":"0002","endpointSchemeID":"0225"}}
        """
        let decoded = try JSONDecoder().decode(Quote.self, from: Data(legacyJSON.utf8))
        XCTAssertEqual(decoded.status, .draft, "doit retomber sur brouillon si absent des données")
        XCTAssertEqual(decoded.currency, "EUR")
        XCTAssertTrue(decoded.lines.isEmpty)
        XCTAssertNil(decoded.convertedInvoiceNumber)
        XCTAssertNil(decoded.convertedOrderNumber)
    }
}
