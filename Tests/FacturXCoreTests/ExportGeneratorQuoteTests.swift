import XCTest
@testable import FacturXCore

final class ExportGeneratorQuoteTests: XCTestCase {

    private func sampleQuote() -> Quote {
        Quote(
            number: "DEV-2026-001",
            status: .sent,
            issueDate: Date(timeIntervalSince1970: 1_700_000_000),
            validUntil: Date(timeIntervalSince1970: 1_702_000_000),
            currency: "EUR",
            seller: InvoiceParty(name: "Arverneo", street: "1 rue Test", postcode: "63000", city: "Clermont-Ferrand", siren: "123456789"),
            buyer: InvoiceParty(name: "Client SAS", street: "2 rue Client", postcode: "75001", city: "Paris", siren: "987654321"),
            lines: [
                InvoiceLine(name: "Prestation A", quantity: 2, unitPrice: 100, vatRate: 20),
                InvoiceLine(name: "Prestation B", quantity: 1, unitPrice: 50, vatRate: 10)
            ],
            notes: "Note de test"
        )
    }

    func testQuoteCSVHasHeaderAndOneRowPerQuote() {
        let csv = ExportGenerator().quoteCSV([sampleQuote(), sampleQuote()])
        let lines = csv.components(separatedBy: "\r\n")
        XCTAssertEqual(lines.count, 3, "1 en-tête + 2 devis")
        XCTAssertTrue(lines[0].hasPrefix("Numéro;Statut;Date"))
    }

    func testQuoteCSVIncludesKeyFields() {
        let csv = ExportGenerator().quoteCSV([sampleQuote()])
        XCTAssertTrue(csv.contains("DEV-2026-001"))
        XCTAssertTrue(csv.contains("Envoyé"))
        XCTAssertTrue(csv.contains("Arverneo"))
        XCTAssertTrue(csv.contains("Client SAS"))
        XCTAssertTrue(csv.contains("987654321"))
    }

    func testQuoteCSVComputesGrandTotal() {
        let quote = sampleQuote()
        let csv = ExportGenerator().quoteCSV([quote])
        // 2*100 + 1*50 = 250 HT ; TVA (200*20% + 50*10%) = 45 ; TTC = 295
        XCTAssertTrue(csv.contains(String(format: "%.2f", quote.grandTotal)))
        XCTAssertEqual(quote.grandTotal, 295.0, accuracy: 0.001)
    }

    func testQuoteLinesCSVHasOneRowPerLine() {
        let csv = ExportGenerator().quoteLinesCSV([sampleQuote()])
        let lines = csv.components(separatedBy: "\r\n")
        XCTAssertEqual(lines.count, 3, "1 en-tête + 2 lignes de prestation")
        XCTAssertTrue(lines[0].hasPrefix("N° devis;Date;Client"))
        XCTAssertTrue(lines[1].contains("Prestation A"))
        XCTAssertTrue(lines[2].contains("Prestation B"))
    }

    func testQuoteCSVEmptyListProducesHeaderOnly() {
        let csv = ExportGenerator().quoteCSV([])
        XCTAssertEqual(csv.components(separatedBy: "\r\n").count, 1)
    }
}
