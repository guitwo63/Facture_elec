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

    /// `credentialsProvider` résout les identifiants pour une société donnée (`nil` = le
    /// réglage par défaut/société principale) — voir `SuperPDPSettings.credentials(for:)`.
    /// La cadence reste pilotée par le seul réglage par défaut (simplification assumée :
    /// pas de cadence différente par société pour l'instant).
    func start(store: InvoiceStore, credentialsProvider: @escaping (UUID?) -> SuperPDPCredentials) {
        guard task == nil else { return }
        isRunning = true
        task = Task { [weak self] in
            while !Task.isCancelled {
                await self?.runOnce(store: store, credentialsProvider: credentialsProvider)
                // Relu à chaque cycle (pas capturé une fois pour toutes) : un changement de
                // `syncIntervalMinutes` dans Réglages > Application > SUPER PDP prend effet
                // dès le prochain cycle, sans redémarrer le moteur.
                let minutes = max(SuperPDPCredentials.minSyncIntervalMinutes, credentialsProvider(nil).syncIntervalMinutes)
                try? await Task.sleep(nanoseconds: UInt64(minutes) * 60 * 1_000_000_000)
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
    /// `credentialsProvider` résout les identifiants par société (chaque société a les
    /// siens — voir `SuperPDPSettings.credentials(for:)`) : les factures candidates sont
    /// regroupées par `companyID` et chaque groupe est interrogé avec ses propres
    /// identifiants, jamais ceux d'une autre société ni un jeu partagé pour tout le lot.
    func runOnce(store: InvoiceStore, credentialsProvider: (UUID?) -> SuperPDPCredentials) async {
        let allCandidates = store.invoices.filter { invoice in
            guard let rid = invoice.superPDPRemoteID, !rid.isEmpty else { return false }
            return !PDPStatusMapper.terminalStatuses.contains(invoice.status)
        }
        let byCompany = Dictionary(grouping: allCandidates, by: \.companyID)
        var updatedCount = 0
        var errorCount = 0
        var queriedCount = 0
        for (companyID, candidates) in byCompany {
            // `usePDP` coupe TOUTES les fonctions PDP pour cette société, y compris ce
            // cycle en arrière-plan — sans quoi désactiver le bouton dans Réglages n'empêchait
            // pas l'app d'interroger SUPER PDP en silence pour des identifiants restés
            // `isConfigured`.
            let credentials = credentialsProvider(companyID)
            guard credentials.usePDP, credentials.isConfigured else { continue }
            queriedCount += candidates.count
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
                        objectCode: invoice.number,
                        companyID: invoice.companyID
                    )
                } catch {
                    errorCount += 1
                    store.audit?.record(
                        actor: "system",
                        action: "pdp_status_error",
                        target: invoice.number,
                        details: "Synchronisation périodique échouée : \(error.localizedDescription)",
                        objectType: .invoice,
                        objectCode: invoice.number,
                        companyID: invoice.companyID
                    )
                }
            }
        }
        lastRunAt = Date()
        lastRunSummary = queriedCount == 0
            ? "Aucune facture à interroger."
            : "\(queriedCount) facture(s) interrogée(s), \(updatedCount) mise(s) à jour" + (errorCount > 0 ? ", \(errorCount) échec(s)" : "") + "."
    }
}
