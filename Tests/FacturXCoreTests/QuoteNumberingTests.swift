import XCTest
@testable import FacturXCore

/// Avant cette correction, QuoteStore générait un numéro au format figé
/// "DEV-AAAA-NNN", sans les réglages de format (préfixe, année, séparateur,
/// numéro de début) dont bénéficient InvoiceStore et OrderStore. Ces tests
/// verrouillent le nouveau moteur, aligné sur OrderStore.
final class QuoteNumberingTests: XCTestCase {

    private let keys = [
        "facturx.quotes.v1",
        "facturx.quotes.number.prefix.v1",
        "facturx.quotes.number.includeyear.v1",
        "facturx.quotes.number.start.v1",
        "facturx.quotes.number.useseparator.v1"
    ]

    override func setUp() {
        super.setUp()
        keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
    }

    override func tearDown() {
        keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
        super.tearDown()
    }

    private func party() -> InvoiceParty { InvoiceParty(name: "", street: "", postcode: "", city: "") }

    func testPrefixYearSeparatorAndStartAreConfigurable() {
        let store = QuoteStore()
        store.numberPrefix = "DV"
        store.numberIncludeYear = false
        store.numberUseSeparator = false
        store.numberStart = 10
        XCTAssertEqual(store.nextNumber(), "DV0010")
    }

    func testDefaultFormatIncludesYearAndSeparator() {
        let store = QuoteStore()
        let year = Calendar.current.component(.year, from: Date())
        XCTAssertEqual(store.nextNumber(), "DEV-\(year)-0001")
    }

    func testCountersStayIndependentPerCompany() {
        let store = QuoteStore()
        store.numberPrefix = "DEV"
        store.numberIncludeYear = false
        store.numberUseSeparator = false
        let cidA = UUID()
        let cidB = UUID()

        let first = store.nextNumber(companyID: cidA)
        XCTAssertEqual(first, "DEV0001")
        store.upsert(Quote(number: first, seller: party(), buyer: party(), companyID: cidA))

        XCTAssertEqual(store.nextNumber(companyID: cidA), "DEV0002", "la société A a un devis : son compteur avance")
        XCTAssertEqual(store.nextNumber(companyID: cidB), "DEV0001", "la société B n'a aucun devis : compteur au numéro de départ, pas influencé par A")
    }

    func testUnscopedQuotesDoNotInflateACompanysCounter() {
        let store = QuoteStore()
        store.numberPrefix = "DEV"
        store.numberIncludeYear = false
        store.numberUseSeparator = false
        let cid = UUID()
        store.upsert(Quote(number: store.nextNumber(companyID: nil), seller: party(), buyer: party(), companyID: nil))
        XCTAssertEqual(store.nextNumber(companyID: cid), "DEV0001")
    }

    /// Régression : voir InvoiceNumberingTests.testDeletingAMiddleInvoiceDoesNotProduceADuplicateNumberAfterwards.
    func testDeletingAMiddleQuoteDoesNotProduceADuplicateNumberAfterwards() {
        let store = QuoteStore()
        store.numberPrefix = "DEV"
        store.numberIncludeYear = false
        store.numberUseSeparator = false

        let quote1 = Quote(number: store.nextNumber(), seller: party(), buyer: party())
        store.upsert(quote1)
        let quote2 = Quote(number: store.nextNumber(), seller: party(), buyer: party())
        store.upsert(quote2)
        let quote3 = Quote(number: store.nextNumber(), seller: party(), buyer: party())
        store.upsert(quote3)
        XCTAssertEqual([quote1.number, quote2.number, quote3.number], ["DEV0001", "DEV0002", "DEV0003"])

        store.delete(quote2)
        let n4 = store.nextNumber()
        XCTAssertEqual(n4, "DEV0004")
        XCTAssertFalse(store.quotes.contains { $0.number == n4 })
    }

    func testPersistsNumberingFormatAcrossReload() {
        let store = QuoteStore()
        store.numberPrefix = "DV"
        store.numberIncludeYear = false
        store.numberStart = 42
        store.numberUseSeparator = false
        store.save()

        let reloaded = QuoteStore()
        XCTAssertEqual(reloaded.numberPrefix, "DV")
        XCTAssertEqual(reloaded.numberIncludeYear, false)
        XCTAssertEqual(reloaded.numberStart, 42)
        XCTAssertEqual(reloaded.numberUseSeparator, false)
    }
}
