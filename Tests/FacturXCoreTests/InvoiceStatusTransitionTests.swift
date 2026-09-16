import XCTest
@testable import FacturXCore

final class InvoiceStatusTransitionTests: XCTestCase {

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "facturx.invoiceStatuses.v1")
        super.tearDown()
    }

    func testDefaultTransitionsMatchStandardLifecycle() {
        let store = InvoiceStatusStore()
        XCTAssertEqual(store.allowedTransitions(from: .draft, isAdmin: false), [.issued])
        XCTAssertEqual(store.allowedTransitions(from: .issued, isAdmin: false), [.sentToPDP, .rejected])
        XCTAssertEqual(store.allowedTransitions(from: .paid, isAdmin: false), [])
    }

    func testAdminCanForceAnyOtherStatus() {
        let store = InvoiceStatusStore()
        let forAdmin = store.allowedTransitions(from: .paid, isAdmin: true)
        XCTAssertEqual(Set(forAdmin), Set(InvoiceStatus.allCases.filter { $0 != .paid }))
    }

    func testTransitionsAreConfigurable() {
        let store = InvoiceStatusStore()
        guard let idx = store.overrides.firstIndex(where: { $0.id == InvoiceStatus.draft.rawValue }) else {
            return XCTFail("Statut brouillon introuvable")
        }
        store.overrides[idx].transitionCodes = [InvoiceStatus.cancelled.rawValue]
        XCTAssertEqual(store.allowedTransitions(from: .draft, isAdmin: false), [.cancelled])
    }

    func testReformCodesAreNonEditableAndAlignedOnOfficialTable() {
        let store = InvoiceStatusStore()
        XCTAssertEqual(store.override(for: .accepted).reformCode, "fr:207")
        XCTAssertEqual(store.override(for: .rejected).reformCode, "fr:206")
        XCTAssertEqual(store.override(for: .paid).reformCode, "fr:212")
        XCTAssertEqual(store.override(for: .cancelled).reformCode, "fr:320")
    }

    func testLoadRealignsPersistedReformCodeEvenIfStale() throws {
        // Simule une donnée déjà persistée avec un ancien code erroné (fr:310)
        // pour vérifier que le rechargement la corrige automatiquement.
        var stale = InvoiceStatusStore.defaults
        if let idx = stale.firstIndex(where: { $0.id == InvoiceStatus.accepted.rawValue }) {
            stale[idx].reformCode = "fr:310"
        }
        let data = try JSONEncoder().encode(stale)
        UserDefaults.standard.set(data, forKey: "facturx.invoiceStatuses.v1")

        let store = InvoiceStatusStore()
        XCTAssertEqual(store.override(for: .accepted).reformCode, "fr:207")
    }

    func testReformStatusRemainsNonDeletable() {
        let store = InvoiceStatusStore()
        guard let idx = store.overrides.firstIndex(where: { $0.id == InvoiceStatus.paid.rawValue }) else {
            return XCTFail("Statut payée introuvable")
        }
        let countBefore = store.overrides.count
        store.remove(at: idx)
        XCTAssertEqual(store.overrides.count, countBefore, "Un statut de réforme ne doit jamais être supprimable")
    }
}
