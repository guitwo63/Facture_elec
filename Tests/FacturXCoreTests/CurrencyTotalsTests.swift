import XCTest
@testable import FacturXCore

/// Sommes du tableau de bord et du montant facturé d'une commande : jamais de dollars additionnés
/// à des euros. Avant, le tableau de bord additionnait toutes les factures et affichait le total
/// avec la devise de la première.
final class CurrencyTotalsTests: XCTestCase {

    private func invoice(_ currency: String, ht: Double, vatRate: Double = 20,
                         type: InvoiceTypeCode = .commercialInvoice, status: InvoiceStatus = .sent,
                         buyer: String = "Client SAS",
                         dueDate: Date = Date().addingTimeInterval(30 * 86400)) -> Invoice {
        Invoice(
            number: "F-2026-\(UUID().uuidString.prefix(4))",
            type: type,
            status: status,
            dueDate: dueDate,
            currency: currency,
            seller: InvoiceParty(name: "Arverneo", street: "1 rue Test", postcode: "63000", city: "Clermont-Ferrand"),
            buyer: InvoiceParty(name: buyer, street: "2 rue Client", postcode: "75001", city: "Paris"),
            lines: [InvoiceLine(name: "Prestation", quantity: 1, unitPrice: ht, vatRate: vatRate)]
        )
    }

    private let overdueDate = Date().addingTimeInterval(-10 * 86400)

    // MARK: - Totaux par devise

    func testMixedCurrenciesGiveOneTotalPerCurrency() {
        let totals = CurrencyTotals.byCurrency([
            invoice("EUR", ht: 1000),                        // 1200 EUR
            invoice("USD", ht: 1000),                        // 1200 USD
            invoice("EUR", ht: 100, type: .creditNote),      // -120 EUR
        ])
        XCTAssertEqual(totals, [
            CurrencyAmount(currency: "EUR", amount: 1080),
            CurrencyAmount(currency: "USD", amount: 1200),
        ], "l'ancien calcul donnait 2280 affichés dans une seule devise")
    }

    func testEuroFirstThenOtherCurrenciesAlphabetically() {
        let totals = CurrencyTotals.byCurrency([
            invoice("USD", ht: 10), invoice("GBP", ht: 10), invoice("EUR", ht: 10), invoice("CHF", ht: 10),
        ])
        XCTAssertEqual(totals.map(\.currency), ["EUR", "CHF", "GBP", "USD"])
    }

    func testEuroOnlyInvoicesGiveASingleTotal() {
        let totals = CurrencyTotals.byCurrency([invoice("EUR", ht: 1000), invoice("EUR", ht: 250.5)])
        XCTAssertEqual(totals, [CurrencyAmount(currency: "EUR", amount: 1500.6)])
    }

    func testForeignCurrencyAloneHasNoEuroLine() {
        XCTAssertEqual(CurrencyTotals.byCurrency([invoice("USD", ht: 100)]), [CurrencyAmount(currency: "USD", amount: 120)])
    }

    func testNoInvoiceGivesNoTotal() {
        XCTAssertEqual(CurrencyTotals.byCurrency([]), [])
    }

    func testCurrencyCodesAreGroupedWithoutSpacesOrCase() {
        let totals = CurrencyTotals.byCurrency([invoice(" usd", ht: 100), invoice("USD ", ht: 100), invoice("EUR", ht: 100)])
        XCTAssertEqual(totals, [
            CurrencyAmount(currency: "EUR", amount: 120),
            CurrencyAmount(currency: "USD", amount: 240),
        ])
    }

    func testInvoiceWithoutCurrencyComesLast() {
        let totals = CurrencyTotals.byCurrency([invoice("", ht: 100), invoice("USD", ht: 100), invoice("EUR", ht: 100)])
        XCTAssertEqual(totals.map(\.currency), ["EUR", "USD", ""])
    }

    func testCreditNotesAndInternalCreditNotesAreDeducted() {
        let totals = CurrencyTotals.byCurrency([
            invoice("GBP", ht: 500),                                // 600
            invoice("GBP", ht: 100, type: .creditNote),             // -120
            invoice("GBP", ht: 50, type: .internalCreditNote),      // -60
        ])
        XCTAssertEqual(totals, [CurrencyAmount(currency: "GBP", amount: 420)])
    }

    /// 0,30 - 0,10 - 0,20 vaut -2,8e-17 en `Double` : sans précaution, « -0.00 USD ».
    func testZeroTotalIsNotNegative() {
        let totals = CurrencyTotals.byCurrency([
            invoice("USD", ht: 0.3, vatRate: 0),
            invoice("USD", ht: 0.1, vatRate: 0, type: .creditNote),
            invoice("USD", ht: 0.2, vatRate: 0, type: .creditNote),
        ])
        XCTAssertEqual(totals.count, 1, "une devise dont le total est nul reste affichée")
        XCTAssertEqual(totals[0].amount.sign, .plus)
        XCTAssertEqual(String(format: "%.2f", totals[0].amount), "0.00")
    }

    // MARK: - Total dans une devise (montant facturé d'une commande)

    func testTotalInCurrencyIgnoresOtherCurrencies() {
        let invoices = [
            invoice("EUR", ht: 1000),                        // 1200 EUR
            invoice("USD", ht: 500),                         // 600 USD, hors montant d'une commande en euros
            invoice("EUR", ht: 100, type: .creditNote),      // -120 EUR
        ]
        XCTAssertEqual(CurrencyTotals.total(invoices, in: "EUR"), 1080)
        XCTAssertEqual(CurrencyTotals.total(invoices, in: " usd"), 600)
        XCTAssertEqual(CurrencyTotals.total(invoices, in: "GBP"), 0)
    }

    func testSameCurrencyIgnoresSpacesAndCase() {
        XCTAssertTrue(CurrencyTotals.sameCurrency(" eur", "EUR"))
        XCTAssertFalse(CurrencyTotals.sameCurrency("EUR", "USD"))
        XCTAssertFalse(CurrencyTotals.sameCurrency("", "EUR"))
    }

    // MARK: - Montant dû par client

    func testClientBalancesAreSplitByCurrency() {
        let balances = CurrencyTotals.clientBalances([
            invoice("EUR", ht: 1000, buyer: "ACME"),         // 1200 EUR
            invoice("USD", ht: 500, buyer: "ACME"),          // 600 USD
            invoice("EUR", ht: 2500, buyer: "Dupont SA"),    // 3000 EUR
        ])
        XCTAssertEqual(balances, [
            ClientBalance(name: "Dupont SA", currency: "EUR", outstanding: 3000, overdue: 0),
            ClientBalance(name: "ACME", currency: "EUR", outstanding: 1200, overdue: 0),
            ClientBalance(name: "ACME", currency: "USD", outstanding: 600, overdue: 0),
        ])
        XCTAssertEqual(Set(balances.map(\.id)).count, balances.count, "identifiants uniques pour ForEach")
    }

    /// Le libellé « … en retard » ne s'affichait que pour un retard négatif : il faut un montant
    /// en retard positif pour une facture échue.
    func testOverdueAmountIsPositiveAndOnlyCountsOverdueInvoices() {
        let balances = CurrencyTotals.clientBalances([
            invoice("EUR", ht: 1000, buyer: "ACME", dueDate: overdueDate),                       // 1200 échus
            invoice("EUR", ht: 500, buyer: "ACME"),                                              // 600 non échus
            invoice("EUR", ht: 100, type: .creditNote, buyer: "ACME", dueDate: overdueDate),     // -120 échus
        ])
        XCTAssertEqual(balances, [ClientBalance(name: "ACME", currency: "EUR", outstanding: 1680, overdue: 1080)])
    }

    func testClientWithoutNameIsGroupedUnderOneLabel() {
        let balances = CurrencyTotals.clientBalances([invoice("EUR", ht: 100, buyer: "  "), invoice("EUR", ht: 100, buyer: "")])
        XCTAssertEqual(balances, [ClientBalance(name: CurrencyTotals.unnamedClient, currency: "EUR", outstanding: 240, overdue: 0)])
    }

    func testEqualBalancesAreSortedByName() {
        let balances = CurrencyTotals.clientBalances([
            invoice("EUR", ht: 100, buyer: "Zèbre SARL"), invoice("EUR", ht: 100, buyer: "Alpha SAS"),
        ])
        XCTAssertEqual(balances.map(\.name), ["Alpha SAS", "Zèbre SARL"])
    }
}
