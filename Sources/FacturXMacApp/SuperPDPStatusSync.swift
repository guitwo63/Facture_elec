import Foundation
import FacturXCore

/// La passerelle entre le journal des événements SUPER PDP (codes `fr:2XX`, envoyés et
/// reçus — voir la doc de `InvoiceStatus`) et le statut fonctionnel réduit de l'app.
/// La règle par code (quel statut fonctionnel il déclenche, le cas échéant) vit dans
/// `SuperPDPStatusCodeStore` (Réglages > Tables > Statuts SUPER PDP), pas ici : c'est cette
/// table, éditable sans changement de code, qui fait foi. Un code absent de la table ou
/// sans règle configurée reste purement informationnel (visible dans le journal SUPER PDP
/// de la facture) sans jamais forcer de changement de statut — comportement sûr par
/// défaut, pas une omission à corriger d'urgence.
///
/// Reconnaît aussi quelques mots libres tolérés avant l'introduction des codes détaillés
/// (le champ `status` de `GET /invoices/{id}` n'est pas documenté aussi précisément que
/// les codes de `invoice_events`) en repli si le code ne correspond à aucune entrée de la
/// table. Partagé entre le rafraîchissement manuel (bouton "Statut PDP" de la fiche
/// facture) et la synchronisation périodique en arrière-plan.
enum PDPStatusMapper {
    static func functionalTransition(for pdpStatus: String) -> InvoiceStatus? {
        if let configured = SuperPDPStatusCodeStore.shared.functionalTransition(for: pdpStatus) {
            return configured
        }
        let s = pdpStatus.lowercased()
        switch s {
        case "accepted", "processed", "received": return .accepted
        case "rejected": return .refused
        case "paid", "encaissée", "encaissee": return .paid
        case "cancelled", "annulée", "annulee": return .cancelled
        default: return nil
        }
    }

    /// Statuts pour lesquels un dépôt SUPER PDP existant n'a plus rien à apprendre : la
    /// synchronisation périodique ignore ces factures pour ne pas interroger l'API en pure
    /// perte (voir aussi `Invoice.superPDPRemoteID`, requis pour même envisager une requête).
    static let terminalStatuses: Set<InvoiceStatus> = [.paid, .cancelled, .refused]
}

/// Interroge périodiquement SUPER PDP pour les factures déposées mais pas encore à un
/// statut terminal, et applique tout avancement reçu — même logique "jamais de
/// rétrogradation" que le rafraîchissement manuel (`InvoiceEditorView.refreshSuperPDPStatus`),
/// mais sans état d'UI par facture puisque rien n'est affiché pendant le cycle.
@MainActor
final class PDPPeriodicSyncEngine: ObservableObject {
    @Published public private(set) var isRunning = false
    @Published public private(set) var lastRunAt: Date?
    @Published public private(set) var lastRunSummary: String?

    private var task: Task<Void, Never>?

    /// Entre deux cycles, en secondes. 15 minutes : assez réactif pour un usage
    /// quotidien sans multiplier les appels à l'API SUPER PDP (quota, latence).
    static let interval: TimeInterval = 15 * 60

    func start(store: InvoiceStore, credentials: @escaping () -> SuperPDPCredentials) {
        guard task == nil else { return }
        isRunning = true
        task = Task { [weak self] in
            while !Task.isCancelled {
                await self?.runOnce(store: store, credentials: credentials())
                try? await Task.sleep(nanoseconds: UInt64(Self.interval * 1_000_000_000))
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        isRunning = false
    }

    /// Exposé séparément de `start()` pour permettre un déclenchement immédiat (bouton
    /// "Synchroniser maintenant" dans Réglages) sans attendre le prochain cycle.
    func runOnce(store: InvoiceStore, credentials: SuperPDPCredentials) async {
        guard credentials.isConfigured else { return }
        let candidates = store.invoices.filter { invoice in
            guard let rid = invoice.superPDPRemoteID, !rid.isEmpty else { return false }
            return !PDPStatusMapper.terminalStatuses.contains(invoice.status)
        }
        var updatedCount = 0
        var errorCount = 0
        for invoice in candidates {
            guard let rid = invoice.superPDPRemoteID else { continue }
            do {
                let service = SuperPDPService()
                let updated = try await service.getInvoiceStatus(remoteID: rid, credentials: credentials)
                guard let mapped = PDPStatusMapper.functionalTransition(for: updated.status) else { continue }
                let isAdvance = mapped.lifecycleRank > invoice.status.lifecycleRank
                let isCancellation = mapped == .cancelled && invoice.status != .cancelled && invoice.status != .paid
                guard (isAdvance || isCancellation) && mapped != invoice.status else { continue }
                var next = invoice
                next.status = mapped
                store.upsert(next)
                updatedCount += 1
                store.audit?.record(
                    actor: "system",
                    action: "pdp_status_received",
                    target: invoice.number,
                    details: "Synchronisation périodique : \(updated.status) → \(mapped.label)",
                    objectType: .invoice,
                    objectCode: invoice.number
                )
            } catch {
                errorCount += 1
                store.audit?.record(
                    actor: "system",
                    action: "pdp_status_error",
                    target: invoice.number,
                    details: "Synchronisation périodique échouée : \(error.localizedDescription)",
                    objectType: .invoice,
                    objectCode: invoice.number
                )
            }
        }
        lastRunAt = Date()
        lastRunSummary = candidates.isEmpty
            ? "Aucune facture à interroger."
            : "\(candidates.count) facture(s) interrogée(s), \(updatedCount) mise(s) à jour" + (errorCount > 0 ? ", \(errorCount) échec(s)" : "") + "."
    }
}
