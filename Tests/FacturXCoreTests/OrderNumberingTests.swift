import XCTest
@testable import FacturXCore

/// Avant cette correction, `OrderStore.nextNumber()` comptait toutes les commandes
/// sans filtrer par société — une seule séquence partagée par toutes les sociétés
/// émettrices, contrairement à `InvoiceStore`/`QuoteStore` qui scopent déjà leur
/// compteur par `companyID`. Ces tests verrouillent le comportement corrigé.
final class OrderNumberingTests: XCTestCase {

    private let keys = [
        "orderx.orders.v1",
        "orderx.buyerSellerSemantics.migrated.v1",
        "orderx.number.prefix.v1",
        "orderx.number.includeyear.v1",
        "orderx.number.start.v1",
        "orderx.number.useseparator.v1",
        "orderx.number.overrides.bysociety.v1"
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

    func testCountersStayIndependentPerCompany() {
        let store = OrderStore()
        store.numberPrefix = "CD"
        store.numberIncludeYear = false
        store.numberUseSeparator = false
        let cidA = UUID()
        let cidB = UUID()

        let first = store.nextNumber(companyID: cidA)
        XCTAssertEqual(first, "CD0001")
        store.upsert(SalesOrder(number: first, buyer: party(), seller: party(), companyID: cidA))

        XCTAssertEqual(store.nextNumber(companyID: cidA), "CD0002", "la société A a une commande : son compteur avance")
        XCTAssertEqual(store.nextNumber(companyID: cidB), "CD0001", "la société B n'a aucune commande : compteur au numéro de départ, pas influencé par A")
    }

    func testUnscopedOrdersDoNotInflateACompanySCounter() {
        let store = OrderStore()
        store.numberPrefix = "CD"
        store.numberIncludeYear = false
        store.numberUseSeparator = false
        let cid = UUID()
        // Une commande sans société (companyID nil) ne doit pas compter dans le
        // chrono d'une société précise.
        store.upsert(SalesOrder(number: store.nextNumber(companyID: nil), buyer: party(), seller: party(), companyID: nil))
        XCTAssertEqual(store.nextNumber(companyID: cid), "CD0001")
    }

    /// Régression : voir InvoiceNumberingTests.testDeletingAMiddleInvoiceNeverProducesADuplicateNumber.
    func testDeletingAMiddleOrderDoesNotProduceADuplicateNumberAfterwards() {
        let store = OrderStore()
        store.numberPrefix = "CD"
        store.numberIncludeYear = false
        store.numberUseSeparator = false

        let order1 = SalesOrder(number: store.nextNumber(), buyer: party(), seller: party())
        store.upsert(order1)
        let order2 = SalesOrder(number: store.nextNumber(), buyer: party(), seller: party())
        store.upsert(order2)
        let order3 = SalesOrder(number: store.nextNumber(), buyer: party(), seller: party())
        store.upsert(order3)
        XCTAssertEqual([order1.number, order2.number, order3.number], ["CD0001", "CD0002", "CD0003"])

        store.delete(order2)
        let n4 = store.nextNumber()
        XCTAssertFalse(store.orders.contains { $0.number == n4 })
    }

    /// Régression : voir InvoiceNumberingTests.testDeletingAMiddleInvoiceRecyclesItsFreedNumber.
    func testDeletingAMiddleOrderRecyclesItsFreedNumber() {
        let store = OrderStore()
        store.numberPrefix = "CD"
        store.numberIncludeYear = false
        store.numberUseSeparator = false

        let order1 = SalesOrder(number: store.nextNumber(), buyer: party(), seller: party())
        store.upsert(order1)
        let order2 = SalesOrder(number: store.nextNumber(), buyer: party(), seller: party())
        store.upsert(order2)
        let order3 = SalesOrder(number: store.nextNumber(), buyer: party(), seller: party())
        store.upsert(order3)

        store.delete(order2)
        XCTAssertEqual(store.nextNumber(), "CD0002")
    }

    // MARK: - Format par société (voir InvoiceNumberingTests, même mécanisme)

    func testCompanyWithoutFormatOverrideUsesDefaultFormat() {
        let store = OrderStore()
        store.numberPrefix = "CD"
        let cid = UUID()
        XCTAssertEqual(store.numberingFormat(for: cid).prefix, "CD")
        XCTAssertEqual(store.previewNextNumber(companyID: cid), store.previewNextNumber(companyID: nil))
    }

    func testFormatOverrideAppliesOnlyToItsOwnCompany() {
        let store = OrderStore()
        store.numberPrefix = "CD"
        let cidA = UUID()
        let cidB = UUID()
        store.numberFormatOverrides[cidA] = InvoiceNumberingFormat(prefix: "ALPHA", includeYear: false, start: 1, useSeparator: false)

        XCTAssertTrue(store.previewNextNumber(companyID: cidA).hasPrefix("ALPHA"))
        XCTAssertTrue(store.previewNextNumber(companyID: cidB).hasPrefix("CD"))
        XCTAssertTrue(store.previewNextNumber(companyID: nil).hasPrefix("CD"))
    }

    /// Régression : le numéro de début d'une société à format propre était ignoré, le
    /// compteur partait toujours de `numberStart` — voir
    /// InvoiceNumberingTests.testOverrideStartNumberIsIndependentOfDefault.
    func testOverrideStartNumberIsIndependentOfDefault() {
        let store = OrderStore()
        store.numberPrefix = "CD"
        store.numberIncludeYear = false
        store.numberUseSeparator = false
        store.numberStart = 1
        let cid = UUID()
        store.numberFormatOverrides[cid] = InvoiceNumberingFormat(prefix: "X", includeYear: false, start: 500, useSeparator: false)

        XCTAssertEqual(store.nextNumber(companyID: cid), "X0500")
        // Aperçus de Réglages › Application : société sélectionnée, puis « Toutes (format par défaut) ».
        XCTAssertEqual(store.previewNextNumber(companyID: cid, format: store.numberingFormat(for: cid)), "X0500")
        XCTAssertEqual(store.previewNextNumber(format: store.defaultNumberingFormat), "CD0001")
        XCTAssertEqual(store.nextNumber(companyID: UUID()), "CD0001", "une société sans format propre garde le numéro de début par défaut")
    }

    /// Le plus petit numéro libre se cherche à partir du numéro de début de la société :
    /// X0001 (numéroté quand ce numéro de début était ignoré) ne fait pas repartir le
    /// compteur d'en bas, et un numéro libéré au-dessus du début est recyclé.
    func testOverrideStartIsTheFloorOfRecycledNumbers() {
        let store = OrderStore()
        let cid = UUID()
        store.numberFormatOverrides[cid] = InvoiceNumberingFormat(prefix: "X", includeYear: false, start: 500, useSeparator: false)
        store.upsert(SalesOrder(number: "X0001", buyer: party(), seller: party(), companyID: cid))

        let order1 = SalesOrder(number: store.nextNumber(companyID: cid), buyer: party(), seller: party(), companyID: cid)
        store.upsert(order1)
        let order2 = SalesOrder(number: store.nextNumber(companyID: cid), buyer: party(), seller: party(), companyID: cid)
        store.upsert(order2)
        XCTAssertEqual([order1.number, order2.number], ["X0500", "X0501"])

        store.delete(order1)
        XCTAssertEqual(store.nextNumber(companyID: cid), "X0500")
    }

    func testRemovingFormatOverrideRevertsToDefaultFormat() {
        let store = OrderStore()
        store.numberPrefix = "CD"
        let cid = UUID()
        store.numberFormatOverrides[cid] = InvoiceNumberingFormat(prefix: "SPECIAL", includeYear: false, start: 1, useSeparator: false)
        XCTAssertEqual(store.numberingFormat(for: cid).prefix, "SPECIAL")

        store.numberFormatOverrides.removeValue(forKey: cid)
        XCTAssertEqual(store.numberingFormat(for: cid).prefix, "CD")
    }

    func testFormatOverridesPersistAcrossReload() {
        let store = OrderStore()
        let cid = UUID()
        store.numberFormatOverrides[cid] = InvoiceNumberingFormat(prefix: "PERSIST", includeYear: true, start: 42, useSeparator: true)
        store.save()

        let reloaded = OrderStore()
        XCTAssertEqual(reloaded.numberFormatOverrides[cid]?.prefix, "PERSIST")
        XCTAssertEqual(reloaded.numberFormatOverrides[cid]?.start, 42)
    }
}
