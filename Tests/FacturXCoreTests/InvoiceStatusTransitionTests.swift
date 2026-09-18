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
        XCTAssertEqual(store.allowedTransitions(from: .issued, isAdmin: false), [.sent, .refused])
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

    /// Codes corrigés lors du passage au modèle séparé (statut fonctionnel / journal PDP) :
    /// avant cette évolution, `accepted`/`rejected` utilisaient à tort fr:207/fr:206
    /// ("Contestée"/"Partiellement acceptée"), pas leur vrai sens officiel.
    func testReformCodesAreAlignedOnOfficialTable() {
        let store = InvoiceStatusStore()
        XCTAssertEqual(store.override(for: .sent).reformCode, "200")
        XCTAssertEqual(store.override(for: .accepted).reformCode, "fr:205")
        XCTAssertEqual(store.override(for: .disputed).reformCode, "fr:207")
        XCTAssertEqual(store.override(for: .refused).reformCode, "fr:210")
        XCTAssertEqual(store.override(for: .paid).reformCode, "fr:212")
        XCTAssertNil(store.override(for: .draft).reformCode)
        XCTAssertNil(store.override(for: .issued).reformCode)
        XCTAssertNil(store.override(for: .cancelled).reformCode, "aucun code fr:2XX officiel pour \"Annulée\"")
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
        XCTAssertEqual(store.override(for: .accepted).reformCode, "fr:205")
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
    /// brouillon — seuls accepted/paid/cancelled verrouillaient. issued et sent doivent
    /// verrouiller aussi, sinon une facture déjà transmise peut être modifiée en silence
    /// par un utilisateur non admin.
    func testValidatedAndTransmittedStatusesLockTheInvoice() {
        XCTAssertTrue(InvoiceStatus.issued.locksInvoice)
        XCTAssertTrue(InvoiceStatus.sent.locksInvoice)
        XCTAssertTrue(InvoiceStatus.accepted.locksInvoice)
        XCTAssertTrue(InvoiceStatus.disputed.locksInvoice)
        XCTAssertTrue(InvoiceStatus.paid.locksInvoice)
        XCTAssertTrue(InvoiceStatus.cancelled.locksInvoice)
    }

    func testDraftAndRefusedStatusesRemainEditable() {
        XCTAssertFalse(InvoiceStatus.draft.locksInvoice)
        XCTAssertFalse(InvoiceStatus.refused.locksInvoice, "un refus doit rester modifiable pour corriger et réémettre")
    }

    // MARK: - Statuts alternatifs au même point du cycle

    func testAcceptedDisputedRefusedShareTheSameLifecycleRank() {
        XCTAssertEqual(InvoiceStatus.accepted.lifecycleRank, InvoiceStatus.disputed.lifecycleRank)
        XCTAssertEqual(InvoiceStatus.accepted.lifecycleRank, InvoiceStatus.refused.lifecycleRank)
    }

    func testLifecycleRankIsMonotonicAlongTheHappyPath() {
        let happyPath: [InvoiceStatus] = [.draft, .issued, .sent, .accepted, .paid]
        for (a, b) in zip(happyPath, happyPath.dropFirst()) {
            XCTAssertLessThanOrEqual(a.lifecycleRank, b.lifecycleRank, "\(a) devrait précéder ou égaler \(b) dans le cycle de vie")
        }
    }

    // MARK: - Règle AIFE : accepted ne redevient jamais refused directement

    /// Règle métier issue des Spécifications Externes AIFE : une facture acceptée/approuvée
    /// ne redevient jamais directement "refusée" — une contestation tardive passe par
    /// "disputed", pas par un refus direct.
    func testAcceptedInvoiceCanNeverTransitionDirectlyToRefused() {
        XCTAssertFalse(InvoiceStatus.accepted.allowedTransitions().contains(.refused))
        XCTAssertTrue(InvoiceStatus.accepted.allowedTransitions().contains(.disputed), "une contestation tardive reste possible")
    }

    func testRefusedIsReachableFromTheUsualDecisionPoints() {
        XCTAssertTrue(InvoiceStatus.issued.allowedTransitions().contains(.refused))
        XCTAssertTrue(InvoiceStatus.sent.allowedTransitions().contains(.refused))
        XCTAssertTrue(InvoiceStatus.disputed.allowedTransitions().contains(.refused))
    }

    // MARK: - Migration depuis l'ancien modèle détaillé (15 statuts, 2026-09-18)

    /// Un ancien statut réseau (étape intermédiaire de dépôt) doit se recaler sur "sent" —
    /// sans quoi une facture déjà persistée avec l'un de ces statuts deviendrait
    /// indécodable (perte silencieuse de toutes les factures du fichier).
    func testLegacyNetworkStatusesMigrateToSent() throws {
        for legacy in ["sentToPDP", "sentToRecipient", "receivedByRecipient", "madeAvailable", "acknowledged", "onHold"] {
            let json = "\"\(legacy)\"".data(using: .utf8)!
            let decoded = try JSONDecoder().decode(InvoiceStatus.self, from: json)
            XCTAssertEqual(decoded, .sent, "\(legacy) devrait migrer vers .sent")
        }
    }

    func testLegacyRejectionVariantsMigrateToRefused() throws {
        for legacy in ["rejected", "technicallyRejected"] {
            let json = "\"\(legacy)\"".data(using: .utf8)!
            let decoded = try JSONDecoder().decode(InvoiceStatus.self, from: json)
            XCTAssertEqual(decoded, .refused, "\(legacy) devrait migrer vers .refused")
        }
    }

    func testLegacyCompletionVariantsMigrateSensibly() throws {
        let completed = try JSONDecoder().decode(InvoiceStatus.self, from: "\"completed\"".data(using: .utf8)!)
        XCTAssertEqual(completed, .accepted)
        let paymentSent = try JSONDecoder().decode(InvoiceStatus.self, from: "\"paymentSent\"".data(using: .utf8)!)
        XCTAssertEqual(paymentSent, .paid)
    }

    func testUnknownStatusMigratesToDraftRatherThanFailingToDecode() throws {
        let decoded = try JSONDecoder().decode(InvoiceStatus.self, from: "\"some_future_unknown_status\"".data(using: .utf8)!)
        XCTAssertEqual(decoded, .draft)
    }

    /// Une facture entière (pas seulement le statut isolé) doit rester décodable avec un
    /// ancien statut — c'est le scénario réel : le champ est niché dans Invoice.
    func testInvoiceWithLegacyStatusStillDecodes() throws {
        let party = InvoiceParty(name: "Test", street: "", postcode: "", city: "")
        var invoice = Invoice(number: "FAC0001", seller: party, buyer: party)
        invoice.status = .sent
        let data = try JSONEncoder().encode(invoice)
        var text = String(data: data, encoding: .utf8)!
        text = text.replacingOccurrences(of: "\"status\":\"sent\"", with: "\"status\":\"sentToRecipient\"")
        let patched = text.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(Invoice.self, from: patched)
        XCTAssertEqual(decoded.status, .sent)
    }

    func testKnownStatusesRoundTripUnchanged() throws {
        for status in InvoiceStatus.allCases {
            let data = try JSONEncoder().encode(status)
            let decoded = try JSONDecoder().decode(InvoiceStatus.self, from: data)
            XCTAssertEqual(decoded, status)
        }
    }
}
