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
        "orderx.number.useseparator.v1"
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
}
