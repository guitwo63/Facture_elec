import XCTest
import FacturXCore

/// Lignes saisies avant le 2026-09-24 dans une unité dont le code est refusé par le Schematron
/// (KTM, PCE, PCK, BX, ROL) : les brouillons passent au code admis au chargement, et une copie
/// faite depuis un document émis (dupliquer, avoir, acompte, solde, commande → facture) le reçoit
/// aussi. Un document émis ne change pas.
final class LegacyUnitCodeMigrationTests: XCTestCase {

    private let invoicesKey = "facturx.invoices.v1"
    private let ordersKey = "orderx.orders.v1"
    private let orderPartiesMigratedKey = "orderx.buyerSellerSemantics.migrated.v1"
    private let purchasesKey = "facturx.purchaseinvoices.v1"

    override func setUp() {
        super.setUp()
        resetPersistedState()
    }

    override func tearDown() {
        resetPersistedState()
        super.tearDown()
    }

    private func resetPersistedState() {
        for key in [invoicesKey, ordersKey, orderPartiesMigratedKey, purchasesKey] {
            AppPersistence.defaults.removeObject(forKey: key)
        }
    }

    private func party(_ name: String) -> InvoiceParty {
        InvoiceParty(name: name, street: "1 rue A", postcode: "75001", city: "Paris")
    }

    private func lines(_ units: [String]) -> [InvoiceLine] {
        units.map { InvoiceLine(name: "Article \($0)", quantity: 1, unit: $0, unitPrice: 10) }
    }

    private func invoice(_ number: String, status: InvoiceStatus, units: [String]) -> Invoice {
        Invoice(number: number, status: status, seller: party("Vendeur"), buyer: party("Client"), lines: lines(units))
    }

    private func persisted<T: Decodable>(_ type: T.Type, _ key: String) throws -> T {
        try JSONDecoder().decode(T.self, from: XCTUnwrap(AppPersistence.defaults.data(forKey: key)))
    }

    // MARK: - Au chargement

    func testInvoiceDraftsAreMigratedOnLoadAndIssuedInvoicesKeepTheirCode() throws {
        let draft = invoice("2026-0001", status: .draft, units: ["PCE", "C62", "KTM", "PCK", "BX", "ROL"])
        let sent = invoice("2026-0002", status: .sent, units: ["PCE"])
        let refused = invoice("2026-0003", status: .refused, units: ["ROL"])
        AppPersistence.defaults.set(try JSONEncoder().encode([draft, sent, refused]), forKey: invoicesKey)

        let store = InvoiceStore()
        let units = { (id: UUID) in store.invoices.first { $0.id == id }?.lines.map(\.unit) }
        XCTAssertEqual(units(draft.id), ["H87", "C62", "KMT", "XPK", "XBX", "XRO"])
        XCTAssertEqual(units(sent.id), ["PCE"], "une facture émise garde le code avec lequel elle est partie")
        XCTAssertEqual(units(refused.id), ["ROL"])

        let saved = try persisted([Invoice].self, invoicesKey)
        XCTAssertEqual(saved.first { $0.id == draft.id }?.lines.map(\.unit), ["H87", "C62", "KMT", "XPK", "XBX", "XRO"], "migration enregistrée")
        XCTAssertEqual(saved.first { $0.id == sent.id }?.lines.map(\.unit), ["PCE"])
    }

    func testOrderDraftsAreMigratedOnLoadAndIssuedOrdersKeepTheirCode() throws {
        let draft = SalesOrder(number: "CD-1", status: .draft, buyer: party("Client"), seller: party("Vendeur"), lines: lines(["PCE", "DAY"]))
        let issued = SalesOrder(number: "CD-2", status: .issued, buyer: party("Client"), seller: party("Vendeur"), lines: lines(["BX"]))
        AppPersistence.defaults.set(try JSONEncoder().encode([draft, issued]), forKey: ordersKey)
        AppPersistence.defaults.set(true, forKey: orderPartiesMigratedKey)

        let store = OrderStore()
        XCTAssertEqual(store.orders.first { $0.id == draft.id }?.lines.map(\.unit), ["H87", "DAY"])
        XCTAssertEqual(store.orders.first { $0.id == issued.id }?.lines.map(\.unit), ["BX"])
        XCTAssertEqual(try persisted([SalesOrder].self, ordersKey).first { $0.id == draft.id }?.lines.map(\.unit), ["H87", "DAY"])
    }

    /// Une saisie manuelle en brouillon a pris son unité dans notre sélecteur ; une facture
    /// reçue garde le code de son fournisseur.
    func testManualPurchaseDraftsAreMigratedButReceivedInvoicesAreNot() throws {
        let manual = PurchaseInvoice(invoice: invoice("F-1", status: .draft, units: ["ROL"]), status: .draft)
        let received = PurchaseInvoice(invoice: invoice("F-2", status: .draft, units: ["ROL"]), status: .received)
        AppPersistence.defaults.set(try JSONEncoder().encode([manual, received]), forKey: purchasesKey)

        let store = PurchaseInvoiceStore()
        XCTAssertEqual(store.invoices.first { $0.id == manual.id }?.invoice.lines.map(\.unit), ["XRO"])
        XCTAssertEqual(store.invoices.first { $0.id == received.id }?.invoice.lines.map(\.unit), ["ROL"])
        XCTAssertEqual(try persisted([PurchaseInvoice].self, purchasesKey).first { $0.id == manual.id }?.invoice.lines.map(\.unit), ["XRO"])
    }

    // MARK: - Copies faites depuis un document émis

    func testCopiesOfAnIssuedInvoiceGetTheAdmittedCode() {
        let store = InvoiceStore()
        let source = invoice("2026-0010", status: .accepted, units: ["PCE", "HUR"])

        XCTAssertEqual(store.duplicate(from: source).lines.map(\.unit), ["H87", "HUR"], "dupliquer")
        XCTAssertEqual(store.newCreditNote(from: source).lines.map(\.unit), ["H87", "HUR"], "avoir")
        XCTAssertEqual(store.newDeposit(from: source).lines.map(\.unit), ["H87", "HUR"], "acompte")
        XCTAssertEqual(store.newFinalSettlement(from: source, deposits: []).lines.map(\.unit), ["H87", "HUR"], "solde")
        XCTAssertEqual(source.lines.map(\.unit), ["PCE", "HUR"], "l'original ne change pas")
    }

    func testInvoiceFromAnIssuedOrderGetsTheAdmittedCode() {
        let order = SalesOrder(number: "CD-3", status: .accepted, buyer: party("Client"), seller: party("Vendeur"), lines: lines(["KTM", "PCK"]))
        XCTAssertEqual(order.toInvoice(number: "2026-0011").lines.map(\.unit), ["KMT", "XPK"])
        XCTAssertEqual(order.lines.map(\.unit), ["KTM", "PCK"])
    }
}
