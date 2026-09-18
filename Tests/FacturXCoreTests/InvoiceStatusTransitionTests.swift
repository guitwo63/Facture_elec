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

    /// Régression : une facture "Validée (non envoyée)" restait modifiable comme un
    /// brouillon — seuls accepted/paid/cancelled verrouillaient. issued et sentToPDP
    /// doivent verrouiller aussi, sinon une facture déjà transmise peut être modifiée
    /// en silence par un utilisateur non admin.
    func testValidatedAndTransmittedStatusesLockTheInvoice() {
        XCTAssertTrue(InvoiceStatus.issued.locksInvoice)
        XCTAssertTrue(InvoiceStatus.sentToPDP.locksInvoice)
        XCTAssertTrue(InvoiceStatus.accepted.locksInvoice)
        XCTAssertTrue(InvoiceStatus.paid.locksInvoice)
        XCTAssertTrue(InvoiceStatus.cancelled.locksInvoice)
    }

    func testDraftAndRejectedStatusesRemainEditable() {
        XCTAssertFalse(InvoiceStatus.draft.locksInvoice)
        XCTAssertFalse(InvoiceStatus.rejected.locksInvoice, "un rejet doit rester modifiable pour être corrigé")
    }

    // MARK: - Statuts de réforme ajoutés (fr:201-204, fr:208-209, fr:211, fr:213)

    func testNewReformStatusesHaveTheExpectedReformCode() {
        let store = InvoiceStatusStore()
        XCTAssertEqual(store.override(for: .sentToRecipient).reformCode, "fr:201")
        XCTAssertEqual(store.override(for: .receivedByRecipient).reformCode, "fr:202")
        XCTAssertEqual(store.override(for: .madeAvailable).reformCode, "fr:203")
        XCTAssertEqual(store.override(for: .acknowledged).reformCode, "fr:204")
        XCTAssertEqual(store.override(for: .onHold).reformCode, "fr:208")
        XCTAssertEqual(store.override(for: .completed).reformCode, "fr:209")
        XCTAssertEqual(store.override(for: .paymentSent).reformCode, "fr:211")
        XCTAssertEqual(store.override(for: .refused).reformCode, "fr:210")
        XCTAssertEqual(store.override(for: .technicallyRejected).reformCode, "fr:213")
    }

    /// Les statuts réseau (rapportés automatiquement par SUPER PDP, jamais créés par l'app)
    /// n'ont aucune transition manuelle configurée par défaut — ils ne s'atteignent qu'en
    /// recevant le statut réel depuis SUPER PDP (voir InvoiceEditorView.mapPDPStatusToLocal,
    /// non testable ici : logique UI sans cible de test).
    func testNetworkOnlyReformStatusesAreNotManuallyReachableByDefault() {
        XCTAssertEqual(InvoiceStatus.sentToRecipient.allowedTransitions(), [])
        XCTAssertEqual(InvoiceStatus.receivedByRecipient.allowedTransitions(), [])
        XCTAssertEqual(InvoiceStatus.madeAvailable.allowedTransitions(), [])
        XCTAssertEqual(InvoiceStatus.technicallyRejected.allowedTransitions(), [])
    }

    func testNetworkOnlyReformCodesMatchTheOnesFlaggedAsNonCreatable() {
        for status in [InvoiceStatus.sentToPDP, .sentToRecipient, .receivedByRecipient, .madeAvailable, .technicallyRejected] {
            let code = InvoiceStatusStore.reformCode(for: status)
            XCTAssertNotNil(code)
            XCTAssertTrue(InvoiceStatusStore.networkOnlyReformCodes.contains(code!), "\(status) (\(code!)) devrait être marqué non créable via l'API")
        }
        // Les codes réellement créables ne doivent pas être marqués à tort comme réseau seul.
        for status in [InvoiceStatus.acknowledged, .onHold, .accepted, .rejected, .refused, .completed, .paymentSent, .paid] {
            let code = InvoiceStatusStore.reformCode(for: status)
            XCTAssertNotNil(code)
            XCTAssertFalse(InvoiceStatusStore.networkOnlyReformCodes.contains(code!), "\(status) (\(code!)) est créable via l'API, ne devrait pas être marqué réseau seul")
        }
    }

    /// Les statuts alternatifs à un même point du cycle de vie (accepted/rejected/refused/
    /// technicallyRejected après acknowledged) ne doivent jamais se "rétrograder" l'un
    /// l'autre : même rang, pour que la synchronisation PDP (qui refuse tout recul) ne
    /// bloque pas le passage légitime de l'un à l'autre.
    func testAlternativeOutcomesAtTheSameLifecycleStageShareTheSameRank() {
        XCTAssertEqual(InvoiceStatus.accepted.lifecycleRank, InvoiceStatus.rejected.lifecycleRank)
        XCTAssertEqual(InvoiceStatus.accepted.lifecycleRank, InvoiceStatus.refused.lifecycleRank)
        XCTAssertEqual(InvoiceStatus.accepted.lifecycleRank, InvoiceStatus.technicallyRejected.lifecycleRank)
    }

    func testLifecycleRankIsMonotonicAlongTheHappyPath() {
        let happyPath: [InvoiceStatus] = [
            .draft, .issued, .sentToPDP, .sentToRecipient, .receivedByRecipient,
            .madeAvailable, .acknowledged, .accepted, .completed, .paymentSent, .paid
        ]
        for (a, b) in zip(happyPath, happyPath.dropFirst()) {
            XCTAssertLessThanOrEqual(a.lifecycleRank, b.lifecycleRank, "\(a) devrait précéder ou égaler \(b) dans le cycle de vie")
        }
    }

    func testAllNewReformStatusesLockTheInvoice() {
        for status in [InvoiceStatus.sentToRecipient, .receivedByRecipient, .madeAvailable, .acknowledged, .onHold, .technicallyRejected, .completed, .paymentSent] {
            XCTAssertTrue(status.locksInvoice, "\(status) devrait verrouiller la facture, comme les autres statuts transmis")
        }
    }

    // MARK: - fr:210 "Refusée" (AIFE REFUSEE) — refus métier, distinct du rejet technique

    /// Un refus métier du destinataire doit rester modifiable, comme un rejet technique :
    /// l'émetteur doit pouvoir corriger et réémettre (nouveau dépôt) sans être bloqué par
    /// un verrouillage sur l'ancienne facture.
    func testRefusedStatusRemainsEditable() {
        XCTAssertFalse(InvoiceStatus.refused.locksInvoice)
    }

    /// Règle métier issue des Spécifications Externes AIFE : une facture acceptée/approuvée
    /// ne redevient jamais "refusée" — seul un avoir permet de corriger une contestation
    /// tardive après acceptation.
    func testAcceptedInvoiceCanNeverTransitionToRefused() {
        XCTAssertFalse(InvoiceStatus.accepted.allowedTransitions().contains(.refused))
    }

    func testRefusedIsReachableFromTheUsualDecisionPoints() {
        XCTAssertTrue(InvoiceStatus.sentToPDP.allowedTransitions().contains(.refused))
        XCTAssertTrue(InvoiceStatus.acknowledged.allowedTransitions().contains(.refused))
        XCTAssertTrue(InvoiceStatus.onHold.allowedTransitions().contains(.refused))
    }
}
