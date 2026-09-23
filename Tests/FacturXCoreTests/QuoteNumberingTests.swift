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
        "facturx.quotes.number.useseparator.v1",
        "facturx.quotes.number.overrides.bysociety.v1"
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

    /// Régression : voir InvoiceNumberingTests.testDeletingAMiddleInvoiceNeverProducesADuplicateNumber.
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
        XCTAssertFalse(store.quotes.contains { $0.number == n4 })
    }

    /// Régression : voir InvoiceNumberingTests.testDeletingAMiddleInvoiceRecyclesItsFreedNumber.
    func testDeletingAMiddleQuoteRecyclesItsFreedNumber() {
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

        store.delete(quote2)
        XCTAssertEqual(store.nextNumber(), "DEV0002")
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

    // MARK: - Format par société (voir InvoiceNumberingTests, même mécanisme)

    func testCompanyWithoutFormatOverrideUsesDefaultFormat() {
        let store = QuoteStore()
        store.numberPrefix = "DEV"
        let cid = UUID()
        XCTAssertEqual(store.numberingFormat(for: cid).prefix, "DEV")
        XCTAssertEqual(store.previewNextNumber(companyID: cid), store.previewNextNumber(companyID: nil))
    }

    func testFormatOverrideAppliesOnlyToItsOwnCompany() {
        let store = QuoteStore()
        store.numberPrefix = "DEV"
        let cidA = UUID()
        let cidB = UUID()
        store.numberFormatOverrides[cidA] = InvoiceNumberingFormat(prefix: "ALPHA", includeYear: false, start: 1, useSeparator: false)

        XCTAssertTrue(store.previewNextNumber(companyID: cidA).hasPrefix("ALPHA"))
        XCTAssertTrue(store.previewNextNumber(companyID: cidB).hasPrefix("DEV"))
        XCTAssertTrue(store.previewNextNumber(companyID: nil).hasPrefix("DEV"))
    }

    /// Régression : le numéro de début d'une société à format propre était ignoré, le
    /// compteur partait toujours de `numberStart` — voir
    /// InvoiceNumberingTests.testOverrideStartNumberIsIndependentOfDefault.
    func testOverrideStartNumberIsIndependentOfDefault() {
        let store = QuoteStore()
        store.numberPrefix = "DEV"
        store.numberIncludeYear = false
        store.numberUseSeparator = false
        store.numberStart = 1
        let cid = UUID()
        store.numberFormatOverrides[cid] = InvoiceNumberingFormat(prefix: "X", includeYear: false, start: 500, useSeparator: false)

        XCTAssertEqual(store.nextNumber(companyID: cid), "X0500")
        // Aperçus de Réglages › Application : société sélectionnée, puis « Toutes (format par défaut) ».
        XCTAssertEqual(store.previewNextNumber(companyID: cid, format: store.numberingFormat(for: cid)), "X0500")
        XCTAssertEqual(store.previewNextNumber(format: store.defaultNumberingFormat), "DEV0001")
        XCTAssertEqual(store.nextNumber(companyID: UUID()), "DEV0001", "une société sans format propre garde le numéro de début par défaut")
    }

    /// Le plus petit numéro libre se cherche à partir du numéro de début de la société :
    /// X0001 (numéroté quand ce numéro de début était ignoré) ne fait pas repartir le
    /// compteur d'en bas, et un numéro libéré au-dessus du début est recyclé.
    func testOverrideStartIsTheFloorOfRecycledNumbers() {
        let store = QuoteStore()
        let cid = UUID()
        store.numberFormatOverrides[cid] = InvoiceNumberingFormat(prefix: "X", includeYear: false, start: 500, useSeparator: false)
        store.upsert(Quote(number: "X0001", seller: party(), buyer: party(), companyID: cid))

        let quote1 = Quote(number: store.nextNumber(companyID: cid), seller: party(), buyer: party(), companyID: cid)
        store.upsert(quote1)
        let quote2 = Quote(number: store.nextNumber(companyID: cid), seller: party(), buyer: party(), companyID: cid)
        store.upsert(quote2)
        XCTAssertEqual([quote1.number, quote2.number], ["X0500", "X0501"])

        store.delete(quote1)
        XCTAssertEqual(store.nextNumber(companyID: cid), "X0500")
    }

    func testRemovingFormatOverrideRevertsToDefaultFormat() {
        let store = QuoteStore()
        store.numberPrefix = "DEV"
        let cid = UUID()
        store.numberFormatOverrides[cid] = InvoiceNumberingFormat(prefix: "SPECIAL", includeYear: false, start: 1, useSeparator: false)
        XCTAssertEqual(store.numberingFormat(for: cid).prefix, "SPECIAL")

        store.numberFormatOverrides.removeValue(forKey: cid)
        XCTAssertEqual(store.numberingFormat(for: cid).prefix, "DEV")
    }

    func testFormatOverridesPersistAcrossReload() {
        let store = QuoteStore()
        let cid = UUID()
        store.numberFormatOverrides[cid] = InvoiceNumberingFormat(prefix: "PERSIST", includeYear: true, start: 42, useSeparator: true)
        store.save()

        let reloaded = QuoteStore()
        XCTAssertEqual(reloaded.numberFormatOverrides[cid]?.prefix, "PERSIST")
        XCTAssertEqual(reloaded.numberFormatOverrides[cid]?.start, 42)
    }
}
