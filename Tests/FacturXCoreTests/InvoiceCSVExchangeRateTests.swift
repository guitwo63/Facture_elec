import XCTest
@testable import FacturXCore

/// Export CSV des factures : hors euro, le taux de change et la TVA en euros (BT-111) en fin de
/// ligne, sans décaler les colonnes existantes.
final class InvoiceCSVExchangeRateTests: XCTestCase {

    private func invoice(_ currency: String, rate: Double? = nil) -> Invoice {
        Invoice(
            number: "F-2026-0042",
            status: .sent,
            currency: currency,
            seller: InvoiceParty(name: "Arverneo", street: "1 rue Test", postcode: "63000", city: "Clermont-Ferrand"),
            buyer: InvoiceParty(name: "ACME Corp", street: "2 Main Street", postcode: "10001", city: "New York", country: "US"),
            lines: [InvoiceLine(name: "Prestation", quantity: 1, unitPrice: 1000, vatRate: 20)],
            paymentTerms: "30 jours nets",
            exchangeRate: rate
        )
    }

    /// En-tête et première ligne de données, découpées sur « ; » (aucun champ de ces factures
    /// n'en contient).
    private func headerAndRow(_ invoice: Invoice) -> (header: [String], row: [String]) {
        let lines = ExportGenerator().invoiceCSV([invoice]).components(separatedBy: "\r\n")
        XCTAssertEqual(lines.count, 2)
        return (lines[0].components(separatedBy: ";"), lines[1].components(separatedBy: ";"))
    }

    func testExistingColumnsKeepTheirPositionAndTheNewOnesComeLast() {
        let (header, row) = headerAndRow(invoice("EUR"))
        XCTAssertEqual(header.count, 25)
        XCTAssertEqual(row.count, header.count)
        XCTAssertEqual(header[5], "Devise")
        XCTAssertEqual(Array(header[15...17]), ["Total HT", "Total TVA", "Total TTC"])
        XCTAssertEqual(header[22], "Conditions de paiement")
        XCTAssertEqual(Array(header[23...24]), ["Taux de change (1 EUR = …)", "Total TVA en EUR (BT-111)"])
    }

    func testEuroInvoiceLeavesRateAndEuroTaxEmpty() {
        let (_, row) = headerAndRow(invoice("EUR"))
        XCTAssertEqual(row[22], "30 jours nets")
        XCTAssertEqual(Array(row[23...24]), ["", ""])
    }

    func testForeignInvoiceGivesRateAndTaxInEuros() {
        let usd = invoice("USD", rate: 1.1464)
        let (_, row) = headerAndRow(usd)
        XCTAssertEqual(row[5], "USD")
        XCTAssertEqual(row[16], "200.00", "la TVA reste dans la devise de la facture")
        // 200 USD ÷ 1,1464 = 174,459… EUR
        XCTAssertEqual(Array(row[23...24]), ["1.1464", "174.46"])
        XCTAssertEqual(usd.taxTotalInEuros, 174.46)
    }

    func testForeignInvoiceWithoutRateLeavesBothEmpty() {
        let (_, row) = headerAndRow(invoice("USD"))
        XCTAssertEqual(Array(row[23...24]), ["", ""])
    }

    /// Comme la mention du PDF : un taux nul ou négatif ne donne pas de TVA en euros et n'est pas
    /// repris (BR-FR-CO-12 bloque la facture à l'émission).
    func testInvalidRateIsNotExported() {
        let (_, row) = headerAndRow(invoice("USD", rate: 0))
        XCTAssertEqual(Array(row[23...24]), ["", ""])
    }
}
