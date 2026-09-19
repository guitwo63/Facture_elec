import XCTest
@testable import FacturXCore

/// Couvre le mécanisme "réglage global + surcharge par société" (Réglages > Tables),
/// répliqué sur les 6 tables "résolveur par id" — voir `SocietyScopedCatalog` et le plan
/// "Réglages par société". Même patron de test que `InvoiceNumberingTests.swift` : sans
/// surcharge -> repli sur le global, une surcharge société A ne fuite jamais vers B ni vers
/// `nil`, la persistance round-trip.
final class ValueTableSocietyOverrideTests: XCTestCase {

    private let keys = [
        "facturx.invoiceStatuses.v1", "facturx.invoiceStatuses.bysociety.v1",
        "facturx.purchaseInvoiceStatuses.v1", "facturx.purchaseInvoiceStatuses.bysociety.v1",
        "orderx.statuses.v1", "orderx.statuses.bysociety.v1",
        "orderx.buyerSellerSemantics.migrated.v1",
        "facturx.quotestatuses.v1", "facturx.quotestatuses.bysociety.v1",
        "facturx.superpdp.statusCodes.v1", "facturx.superpdp.statusCodes.bysociety.v1",
        "facturx.auditactionlabels.v1", "facturx.auditactionlabels.bysociety.v1",
    ]

    override func setUp() {
        super.setUp()
        keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
    }

    override func tearDown() {
        keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
        super.tearDown()
    }

    // MARK: - InvoiceStatusStore

    func testInvoiceStatusNoOverrideFallsBackToGlobal() {
        let store = InvoiceStatusStore()
        XCTAssertEqual(store.override(for: .accepted, companyID: UUID()).hexColor, store.override(for: .accepted).hexColor)
    }

    func testInvoiceStatusOverrideDoesNotLeakToOtherCompanyOrNil() {
        let store = InvoiceStatusStore()
        let cidA = UUID(); let cidB = UUID()
        var custom = store.override(for: .accepted)
        custom.hexColor = "ABCDEF"
        store.setOverride(custom, companyID: cidA)

        XCTAssertEqual(store.override(for: .accepted, companyID: cidA).hexColor, "ABCDEF")
        XCTAssertNotEqual(store.override(for: .accepted, companyID: cidB).hexColor, "ABCDEF")
        XCTAssertNotEqual(store.override(for: .accepted, companyID: nil).hexColor, "ABCDEF")
    }

    func testInvoiceStatusOverridePersistsAcrossReload() {
        let store = InvoiceStatusStore()
        let cid = UUID()
        var custom = store.override(for: .disputed)
        custom.label = "En litige"
        store.setOverride(custom, companyID: cid)

        let reloaded = InvoiceStatusStore()
        XCTAssertEqual(reloaded.override(for: .disputed, companyID: cid).label, "En litige")
    }

    func testInvoiceStatusRemoveOverrideRevertsToGlobal() {
        let store = InvoiceStatusStore()
        let cid = UUID()
        var custom = store.override(for: .accepted)
        custom.hexColor = "111111"
        store.setOverride(custom, companyID: cid)
        XCTAssertEqual(store.override(for: .accepted, companyID: cid).hexColor, "111111")

        store.removeOverride(for: .accepted, companyID: cid)
        XCTAssertEqual(store.override(for: .accepted, companyID: cid).hexColor, store.override(for: .accepted).hexColor)
    }

    func testInvoiceStatusAllowedTransitionsCompanyVariantMatchesGlobalWhenNoOverride() {
        let store = InvoiceStatusStore()
        let cid = UUID()
        XCTAssertEqual(
            store.allowedTransitions(from: .accepted, companyID: cid, isAdmin: false),
            store.allowedTransitions(from: .accepted, isAdmin: false)
        )
    }

    // MARK: - PurchaseInvoiceStatusStore

    func testPurchaseInvoiceStatusOverrideScopedToCompany() {
        let store = PurchaseInvoiceStatusStore()
        let cidA = UUID(); let cidB = UUID()
        var custom = store.override(for: .validated)
        custom.hexColor = "222222"
        store.setOverride(custom, companyID: cidA)

        XCTAssertEqual(store.override(for: .validated, companyID: cidA).hexColor, "222222")
        XCTAssertNotEqual(store.override(for: .validated, companyID: cidB).hexColor, "222222")
        XCTAssertNotEqual(store.override(for: .validated, companyID: nil).hexColor, "222222")
    }

    func testPurchaseInvoiceStatusOverridePersistsAcrossReload() {
        let store = PurchaseInvoiceStatusStore()
        let cid = UUID()
        var custom = store.override(for: .refused)
        custom.label = "Rejetée"
        store.setOverride(custom, companyID: cid)

        let reloaded = PurchaseInvoiceStatusStore()
        XCTAssertEqual(reloaded.override(for: .refused, companyID: cid).label, "Rejetée")
    }

    // MARK: - OrderStatusStore

    private func party() -> InvoiceParty { InvoiceParty(name: "", street: "", postcode: "", city: "") }

    func testOrderStatusOverrideScopedToCompany() {
        let store = OrderStatusStore()
        let cidA = UUID(); let cidB = UUID()
        var custom = store.override(for: .accepted)
        custom.hexColor = "333333"
        store.setOverride(custom, companyID: cidA)

        XCTAssertEqual(store.override(for: .accepted, companyID: cidA).hexColor, "333333")
        XCTAssertNotEqual(store.override(for: .accepted, companyID: cidB).hexColor, "333333")
    }

    /// `override(for order:)` doit résoudre la surcharge de la société portée par
    /// `order.companyID`, sans que l'appelant n'ait à passer de companyID séparément —
    /// c'est le point central du design ("zéro changement aux sites d'appel existants").
    func testOrderOverrideForOrderUsesOrdersOwnCompanyID() {
        let store = OrderStatusStore()
        let cidA = UUID(); let cidB = UUID()
        var custom = store.override(for: .accepted)
        custom.hexColor = "444444"
        store.setOverride(custom, companyID: cidA)

        let orderA = SalesOrder(number: "CD-1", status: .accepted, buyer: party(), seller: party(), companyID: cidA)
        let orderB = SalesOrder(number: "CD-2", status: .accepted, buyer: party(), seller: party(), companyID: cidB)
        XCTAssertEqual(store.override(for: orderA).hexColor, "444444")
        XCTAssertNotEqual(store.override(for: orderB).hexColor, "444444")
    }

    // MARK: - QuoteStatusStore

    func testQuoteStatusOverrideScopedToCompany() {
        let store = QuoteStatusStore()
        let cidA = UUID(); let cidB = UUID()
        var custom = store.override(for: .accepted)
        custom.hexColor = "555555"
        store.setOverride(custom, companyID: cidA)

        XCTAssertEqual(store.override(for: .accepted, companyID: cidA).hexColor, "555555")
        XCTAssertNotEqual(store.override(for: .accepted, companyID: cidB).hexColor, "555555")
        XCTAssertEqual(store.allowedTransitions(from: .accepted, companyID: cidB), store.allowedTransitions(from: .accepted))
    }

    // MARK: - SuperPDPStatusCodeStore

    func testSuperPDPStatusCodeOverrideScopedToCompanyAndCaseInsensitive() {
        let store = SuperPDPStatusCodeStore()
        let cidA = UUID(); let cidB = UUID()
        var custom = store.override(for: "fr:205")!
        custom.label = "Approuvée"
        store.setOverride(custom, companyID: cidA)

        XCTAssertEqual(store.override(for: "FR:205", companyID: cidA)?.label, "Approuvée")
        XCTAssertNotEqual(store.override(for: "fr:205", companyID: cidB)?.label, "Approuvée")
        XCTAssertEqual(store.functionalTransition(for: "fr:205", companyID: cidA), .accepted)
    }

    func testSuperPDPStatusCodeRemoveOverrideRevertsToGlobal() {
        let store = SuperPDPStatusCodeStore()
        let cid = UUID()
        var custom = store.override(for: "fr:210")!
        custom.label = "Rejetée"
        store.setOverride(custom, companyID: cid)
        store.removeOverride(id: "fr:210", companyID: cid)
        XCTAssertEqual(store.override(for: "fr:210", companyID: cid)?.label, store.override(for: "fr:210")?.label)
    }

    // MARK: - AuditActionLabelStore

    func testAuditActionLabelOverrideScopedToCompany() {
        let store = AuditActionLabelStore()
        let cidA = UUID(); let cidB = UUID()
        store.setOverride(AuditActionLabel(id: "invoice_created", label: "Nouvelle facture créée"), companyID: cidA)

        XCTAssertEqual(store.label(for: "invoice_created", companyID: cidA), "Nouvelle facture créée")
        XCTAssertEqual(store.label(for: "invoice_created", companyID: cidB), store.label(for: "invoice_created"))
        XCTAssertEqual(store.label(for: "invoice_created", companyID: nil), store.label(for: "invoice_created"))
    }

    func testAuditActionLabelOverridePersistsAcrossReload() {
        let store = AuditActionLabelStore()
        let cid = UUID()
        store.setOverride(AuditActionLabel(id: "order_created", label: "Commande passée"), companyID: cid)

        let reloaded = AuditActionLabelStore()
        XCTAssertEqual(reloaded.label(for: "order_created", companyID: cid), "Commande passée")
    }
}
