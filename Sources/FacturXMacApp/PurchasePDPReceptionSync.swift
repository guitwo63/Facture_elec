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

    func start(store: PurchaseInvoiceStore, credentials: @escaping () -> SuperPDPCredentials) {
        guard task == nil else { return }
        isRunning = true
        task = Task { [weak self] in
            while !Task.isCancelled {
                let current = credentials()
                await self?.runOnce(store: store, credentials: current)
                let minutes = max(SuperPDPCredentials.minSyncIntervalMinutes, current.syncIntervalMinutes)
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
    func runOnce(store: PurchaseInvoiceStore, credentials: SuperPDPCredentials) async {
        guard credentials.usePDP, credentials.isConfigured else { return }
        let alreadyKnownRemoteIDs = Set(store.invoices.compactMap { $0.invoice.superPDPRemoteID })
        var receivedCount = 0
        var importedCount = 0
        var errorCount = 0
        do {
            let service = SuperPDPService()
            let submissions = try await service.listInvoices(direction: .received, credentials: credentials)
            let newSubmissions = submissions.filter { sub in
                guard let rid = sub.remoteID, !rid.isEmpty else { return false }
                return !alreadyKnownRemoteIDs.contains(rid)
            }
            receivedCount = newSubmissions.count
            for submission in newSubmissions {
                guard let remoteID = submission.remoteID else { continue }
                do {
                    let fileData = try await service.downloadInvoice(remoteID: remoteID, credentials: credentials)
                    let parsed = try CIIXMLParser.parseDepositedFile(fileData)
                    let record = store.ingest(remoteID: remoteID, parsed: parsed, companyID: nil)
                    importedCount += 1
                    store.audit?.record(
                        actor: "system",
                        action: "purchase_invoice_received",
                        target: record.invoice.number,
                        details: "Facture reçue via SUPER PDP — id distant \(remoteID), fournisseur \(record.invoice.seller.name)",
                        objectType: .purchaseInvoice,
                        objectCode: record.invoice.number
                    )
                } catch {
                    errorCount += 1
                    store.audit?.record(
                        actor: "system",
                        action: "purchase_invoice_receive_error",
                        target: remoteID,
                        details: "Échec import facture d'achat (id distant \(remoteID)) : \(error.localizedDescription)",
                        objectType: .purchaseInvoice,
                        objectCode: remoteID
                    )
                }
            }
        } catch {
            errorCount += 1
            store.audit?.record(
                actor: "system",
                action: "purchase_invoice_list_error",
                target: "",
                details: "Échec de la liste des factures reçues sur SUPER PDP : \(error.localizedDescription)",
                objectType: .purchaseInvoice,
                objectCode: nil
            )
        }
        lastRunAt = Date()
        lastRunSummary = receivedCount == 0
            ? "Aucune nouvelle facture reçue."
            : "\(receivedCount) facture(s) reçue(s), \(importedCount) importée(s)" + (errorCount > 0 ? ", \(errorCount) échec(s)" : "") + "."
    }
}
