import XCTest
@testable import FacturXCore

/// Pendant de `InvoiceStatusTransitionTests` côté achats — mêmes garanties vérifiées,
/// retypées sur `PurchaseInvoiceStatus`/`PurchaseInvoiceStatusStore`.
final class PurchaseInvoiceStatusTransitionTests: XCTestCase {

    override func tearDown() {
        AppPersistence.defaults.removeObject(forKey: "facturx.purchaseInvoiceStatuses.v1")
        super.tearDown()
    }

    func testDefaultTransitionsMatchTheValidationWorkflow() {
        let store = PurchaseInvoiceStatusStore()
        XCTAssertEqual(store.allowedTransitions(from: .draft, isAdmin: false), [.received])
        XCTAssertEqual(store.allowedTransitions(from: .received, isAdmin: false), [.toValidate])
        XCTAssertEqual(Set(store.allowedTransitions(from: .toValidate, isAdmin: false)), Set([.validated, .disputed, .refused]))
        XCTAssertEqual(store.allowedTransitions(from: .paid, isAdmin: false), [])
    }

    func testAdminCanForceAnyOtherStatus() {
        let store = PurchaseInvoiceStatusStore()
        let forAdmin = store.allowedTransitions(from: .paid, isAdmin: true)
        XCTAssertEqual(Set(forAdmin), Set(PurchaseInvoiceStatus.allCases.filter { $0 != .paid }))
    }

    func testTransitionsAreConfigurable() {
        let store = PurchaseInvoiceStatusStore()
        guard let idx = store.overrides.firstIndex(where: { $0.id == PurchaseInvoiceStatus.draft.rawValue }) else {
            return XCTFail("Statut brouillon introuvable")
        }
        store.overrides[idx].transitionCodes = [PurchaseInvoiceStatus.cancelled.rawValue]
        XCTAssertEqual(store.allowedTransitions(from: .draft, isAdmin: false), [.cancelled])
    }

    /// `fr:211` (Paiement envoyé) est le premier usage réel de ce code dans l'app : côté
    /// ventes, seul son pendant réception `fr:212` (Paiement reçu) est envoyé.
    func testReformCodesMatchTheAcheteurComptableWorkflow() {
        let store = PurchaseInvoiceStatusStore()
        XCTAssertEqual(store.override(for: .validated).reformCode, "fr:205")
        XCTAssertEqual(store.override(for: .disputed).reformCode, "fr:207")
        XCTAssertEqual(store.override(for: .refused).reformCode, "fr:210")
        XCTAssertEqual(store.override(for: .paid).reformCode, "fr:211")
        XCTAssertNil(store.override(for: .draft).reformCode)
        XCTAssertNil(store.override(for: .received).reformCode)
        XCTAssertNil(store.override(for: .toValidate).reformCode)
        XCTAssertNil(store.override(for: .cancelled).reformCode)
    }

    func testPdpFeedbackMirrorsReformCode() {
        let store = PurchaseInvoiceStatusStore()
        XCTAssertEqual(store.pdpFeedback(for: .validated), "fr:205")
        XCTAssertNil(store.pdpFeedback(for: .received), "un statut sans code réforme n'a rien à notifier au fournisseur")
    }

    func testLoadRealignsPersistedReformCodeEvenIfStale() throws {
        var stale = PurchaseInvoiceStatusStore.defaults
        if let idx = stale.firstIndex(where: { $0.id == PurchaseInvoiceStatus.validated.rawValue }) {
            stale[idx].reformCode = "fr:999"
        }
        let data = try JSONEncoder().encode(stale)
        AppPersistence.defaults.set(data, forKey: "facturx.purchaseInvoiceStatuses.v1")

        let store = PurchaseInvoiceStatusStore()
        XCTAssertEqual(store.override(for: .validated).reformCode, "fr:205")
    }

    func testReformStatusRemainsNonDeletable() {
        let store = PurchaseInvoiceStatusStore()
        guard let idx = store.overrides.firstIndex(where: { $0.id == PurchaseInvoiceStatus.paid.rawValue }) else {
            return XCTFail("Statut payée introuvable")
        }
        let countBefore = store.overrides.count
        store.remove(at: idx)
        XCTAssertEqual(store.overrides.count, countBefore, "Un statut de réforme ne doit jamais être supprimable")
    }

    func testLoadDropsOrphanedEntries() throws {
        var stale = PurchaseInvoiceStatusStore.defaults
        stale.append(PurchaseInvoiceStatusOverride(id: "custom-abc123", label: "Archivée", systemImage: "doc", hexColor: "6E6E73"))
        let data = try JSONEncoder().encode(stale)
        AppPersistence.defaults.set(data, forKey: "facturx.purchaseInvoiceStatuses.v1")

        let store = PurchaseInvoiceStatusStore()
        XCTAssertEqual(store.overrides.count, PurchaseInvoiceStatus.allCases.count)
        XCTAssertNil(store.overrides.first { $0.id == "custom-abc123" })
    }

    func testDraftAndRefusedRemainEditable() {
        XCTAssertFalse(PurchaseInvoiceStatus.draft.locksInvoice)
        XCTAssertFalse(PurchaseInvoiceStatus.refused.locksInvoice)
    }

    func testReceivedThroughPaidLockTheInvoice() {
        XCTAssertTrue(PurchaseInvoiceStatus.received.locksInvoice)
        XCTAssertTrue(PurchaseInvoiceStatus.toValidate.locksInvoice)
        XCTAssertTrue(PurchaseInvoiceStatus.validated.locksInvoice)
        XCTAssertTrue(PurchaseInvoiceStatus.disputed.locksInvoice)
        XCTAssertTrue(PurchaseInvoiceStatus.paid.locksInvoice)
        XCTAssertTrue(PurchaseInvoiceStatus.cancelled.locksInvoice)
    }

    func testValidatedDisputedRefusedShareTheSameLifecycleRank() {
        XCTAssertEqual(PurchaseInvoiceStatus.validated.lifecycleRank, PurchaseInvoiceStatus.disputed.lifecycleRank)
        XCTAssertEqual(PurchaseInvoiceStatus.validated.lifecycleRank, PurchaseInvoiceStatus.refused.lifecycleRank)
    }

    func testLifecycleRankIsMonotonicAlongTheHappyPath() {
        let happyPath: [PurchaseInvoiceStatus] = [.draft, .received, .toValidate, .validated, .paid]
        for (a, b) in zip(happyPath, happyPath.dropFirst()) {
            XCTAssertLessThanOrEqual(a.lifecycleRank, b.lifecycleRank, "\(a) devrait précéder ou égaler \(b) dans le cycle de vie")
        }
    }

    func testValidatedCanNeverTransitionDirectlyToRefused() {
        XCTAssertFalse(PurchaseInvoiceStatus.validated.allowedTransitions().contains(.refused), "un litige doit passer par 'Contestée', pas un refus direct après validation")
        XCTAssertTrue(PurchaseInvoiceStatus.validated.allowedTransitions().contains(.disputed))
    }

    func testRefusedIsReachableFromTheDecisionPoint() {
        XCTAssertTrue(PurchaseInvoiceStatus.toValidate.allowedTransitions().contains(.refused))
        XCTAssertTrue(PurchaseInvoiceStatus.disputed.allowedTransitions().contains(.refused))
    }

    func testUnknownStatusMigratesToDraftRatherThanFailingToDecode() throws {
        let decoded = try JSONDecoder().decode(PurchaseInvoiceStatus.self, from: "\"some_future_unknown_status\"".data(using: .utf8)!)
        XCTAssertEqual(decoded, .draft)
    }

    func testKnownStatusesRoundTripUnchanged() throws {
        for status in PurchaseInvoiceStatus.allCases {
            let data = try JSONEncoder().encode(status)
            let decoded = try JSONDecoder().decode(PurchaseInvoiceStatus.self, from: data)
            XCTAssertEqual(decoded, status)
        }
    }
}
