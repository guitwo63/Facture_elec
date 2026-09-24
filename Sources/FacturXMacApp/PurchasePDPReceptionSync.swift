import Foundation
import FacturXCore

/// Réception automatique des factures d'achat via SUPER PDP — pendant de
/// `PDPPeriodicSyncEngine` (`SuperPDPStatusSync.swift`), même structure `start`/`stop`/
/// `runOnce`, même cadence partagée (`SuperPDPCredentials.syncIntervalMinutes`) plutôt qu'un
/// second réglage séparé — simplification assumée pour cette première version : à scinder
/// plus tard si un vrai besoin de cadence différente pour la réception apparaît.
@MainActor
final class PurchasePDPReceptionEngine: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var lastRunAt: Date?
    @Published private(set) var lastRunSummary: String?

    private var task: Task<Void, Never>?

    /// Reçoit les échecs : une entrée d'audit au début d'une panne, une à son retour à la
    /// normale, plutôt qu'une à chaque cycle (voir `SyncFailureJournal`).
    var failureJournal = SyncFailureJournal.shared

    /// `defaultCredentials`/`credentialsBySociety` — voir `SuperPDPSettings.credentials`/
    /// `.credentialsBySociety`. La cadence reste pilotée par le seul réglage par défaut.
    func start(store: PurchaseInvoiceStore, defaultCredentials: @escaping () -> SuperPDPCredentials, credentialsBySociety: @escaping () -> [UUID: SuperPDPCredentials]) {
        guard task == nil else { return }
        isRunning = true
        task = Task { [weak self] in
            while !Task.isCancelled {
                await self?.runOnce(store: store, defaultCredentials: defaultCredentials(), credentialsBySociety: credentialsBySociety())
                let minutes = max(SuperPDPCredentials.minSyncIntervalMinutes, defaultCredentials().syncIntervalMinutes)
                try? await Task.sleep(nanoseconds: UInt64(minutes) * 60 * 1_000_000_000)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        isRunning = false
    }

    /// Exposé séparément de `start()` pour un déclenchement immédiat ("Synchroniser
    /// maintenant" dans Réglages), même principe que `PDPPeriodicSyncEngine.runOnce`.
    ///
    /// Interroge le compte par défaut (hérité par toute société sans surcharge propre —
    /// ambigu par nature, réceptions attribuées à `companyID: nil` comme aujourd'hui) PUIS,
    /// séparément, chaque société ayant sa **propre** surcharge d'identifiants explicite
    /// (`credentialsBySociety`) — celles-là seules peuvent être attribuées avec certitude à
    /// la bonne société, puisque leur compte SUPER PDP n'est partagé par personne d'autre.
    /// Ne pas interroger le compte par défaut une seconde fois pour chaque société sans
    /// surcharge : elles partagent toutes le même compte que le défaut, déjà couvert.
    func runOnce(store: PurchaseInvoiceStore, defaultCredentials: SuperPDPCredentials, credentialsBySociety: [UUID: SuperPDPCredentials]) async {
        var totalReceived = 0
        var totalImported = 0
        var totalErrors = 0
        var firstError: String?
        var queriedCompanies: Set<UUID?> = []

        if defaultCredentials.usePDP, defaultCredentials.isConfigured {
            queriedCompanies.insert(nil)
            let (received, imported, errors, error) = await receive(store: store, credentials: defaultCredentials, companyID: nil)
            totalReceived += received; totalImported += imported; totalErrors += errors
            if firstError == nil { firstError = error }
        }
        for (companyID, credentials) in credentialsBySociety where credentials.usePDP && credentials.isConfigured {
            queriedCompanies.insert(companyID)
            let (received, imported, errors, error) = await receive(store: store, credentials: credentials, companyID: companyID)
            totalReceived += received; totalImported += imported; totalErrors += errors
            if firstError == nil { firstError = error }
        }
        guard !Task.isCancelled else { return }
        failureJournal.forgetAccounts(of: .purchaseReception, except: queriedCompanies)

        lastRunAt = Date()
        // Un échec de la liste s'affichait « Aucune nouvelle facture reçue. » : la panne ne se
        // voyait nulle part ailleurs que dans le journal d'audit.
        var summary = totalReceived == 0
            ? (totalErrors == 0 ? "Aucune nouvelle facture reçue." : "Réception en échec.")
            : "\(totalReceived) facture(s) reçue(s), \(totalImported) importée(s)" + (totalErrors > 0 ? ", \(totalErrors) échec(s)" : "") + "."
        if let firstError { summary += " Erreur : \(SyncFailureJournal.brief(firstError))" }
        lastRunSummary = summary
    }

    /// Un seul compte SUPER PDP interrogé, les nouvelles factures reçues attribuées à
    /// `companyID` (celle dont le compte a été interrogé — `nil` pour le compte par défaut,
    /// partagé/ambigu par nature).
    private func receive(store: PurchaseInvoiceStore, credentials: SuperPDPCredentials, companyID: UUID?) async -> (received: Int, imported: Int, errors: Int, firstError: String?) {
        let alreadyKnownRemoteIDs = Set(store.invoices.compactMap { $0.invoice.superPDPRemoteID })
        var importedCount = 0
        var errorCount = 0
        var firstError: String?
        var cycle = SyncCycle(kind: .purchaseReception, companyID: companyID)
        do {
            let service = SuperPDPService()
            let submissions = try await service.listInvoices(direction: .received, credentials: credentials)
            cycle.recordSuccess()
            let newSubmissions = submissions.filter { sub in
                guard let rid = sub.remoteID, !rid.isEmpty else { return false }
                return !alreadyKnownRemoteIDs.contains(rid)
            }
            cycle.followedTargets = newSubmissions.compactMap(\.remoteID).map { SyncTarget(id: $0, code: $0) }
            for submission in newSubmissions {
                guard let remoteID = submission.remoteID else { continue }
                let target = SyncTarget(id: remoteID, code: remoteID)
                do {
                    let fileData = try await service.downloadInvoice(remoteID: remoteID, credentials: credentials)
                    let parsed = try CIIXMLParser.parseDepositedFile(fileData)
                    let record = store.ingest(remoteID: remoteID, parsed: parsed, companyID: companyID)
                    importedCount += 1
                    cycle.recordSuccess(target)
                    store.audit?.record(
                        actor: "system",
                        action: "purchase_invoice_received",
                        target: record.invoice.number,
                        details: "Facture reçue via SUPER PDP — id distant \(remoteID), fournisseur \(record.invoice.seller.name)",
                        objectType: .purchaseInvoice,
                        objectCode: record.invoice.number,
                        companyID: companyID
                    )
                } catch {
                    errorCount += 1
                    if firstError == nil { firstError = error.localizedDescription }
                    cycle.recordFailure(error, target: target)
                }
            }
            close(cycle, store: store)
            return (newSubmissions.count, importedCount, errorCount, firstError)
        } catch {
            cycle.recordFailure(error)
            close(cycle, store: store)
            return (0, 0, 1, error.localizedDescription)
        }
    }

    /// Moteur arrêté en plein cycle (bascule d'environnement) : rien n'est noté, les pannes en
    /// cours sont déjà celles du nouvel environnement.
    private func close(_ cycle: SyncCycle, store: PurchaseInvoiceStore) {
        guard !Task.isCancelled else { return }
        failureJournal.close(cycle, audit: store.audit)
    }
}
