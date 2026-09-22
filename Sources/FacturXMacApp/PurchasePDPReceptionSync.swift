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

        if defaultCredentials.usePDP, defaultCredentials.isConfigured {
            let (received, imported, errors) = await receive(store: store, credentials: defaultCredentials, companyID: nil)
            totalReceived += received; totalImported += imported; totalErrors += errors
        }
        for (companyID, credentials) in credentialsBySociety where credentials.usePDP && credentials.isConfigured {
            let (received, imported, errors) = await receive(store: store, credentials: credentials, companyID: companyID)
            totalReceived += received; totalImported += imported; totalErrors += errors
        }

        lastRunAt = Date()
        lastRunSummary = totalReceived == 0
            ? "Aucune nouvelle facture reçue."
            : "\(totalReceived) facture(s) reçue(s), \(totalImported) importée(s)" + (totalErrors > 0 ? ", \(totalErrors) échec(s)" : "") + "."
    }

    /// Un seul compte SUPER PDP interrogé, les nouvelles factures reçues attribuées à
    /// `companyID` (celle dont le compte a été interrogé — `nil` pour le compte par défaut,
    /// partagé/ambigu par nature).
    private func receive(store: PurchaseInvoiceStore, credentials: SuperPDPCredentials, companyID: UUID?) async -> (received: Int, imported: Int, errors: Int) {
        let alreadyKnownRemoteIDs = Set(store.invoices.compactMap { $0.invoice.superPDPRemoteID })
        var importedCount = 0
        var errorCount = 0
        do {
            let service = SuperPDPService()
            let submissions = try await service.listInvoices(direction: .received, credentials: credentials)
            let newSubmissions = submissions.filter { sub in
                guard let rid = sub.remoteID, !rid.isEmpty else { return false }
                return !alreadyKnownRemoteIDs.contains(rid)
            }
            for submission in newSubmissions {
                guard let remoteID = submission.remoteID else { continue }
                do {
                    let fileData = try await service.downloadInvoice(remoteID: remoteID, credentials: credentials)
                    let parsed = try CIIXMLParser.parseDepositedFile(fileData)
                    let record = store.ingest(remoteID: remoteID, parsed: parsed, companyID: companyID)
                    importedCount += 1
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
                    store.audit?.record(
                        actor: "system",
                        action: "purchase_invoice_receive_error",
                        target: remoteID,
                        details: "Échec import facture d'achat (id distant \(remoteID)) : \(error.localizedDescription)",
                        objectType: .purchaseInvoice,
                        objectCode: remoteID,
                        companyID: companyID
                    )
                }
            }
            return (newSubmissions.count, importedCount, errorCount)
        } catch {
            store.audit?.record(
                actor: "system",
                action: "purchase_invoice_list_error",
                target: "",
                details: "Échec de la liste des factures reçues sur SUPER PDP : \(error.localizedDescription)",
                objectType: .purchaseInvoice,
                objectCode: nil,
                companyID: companyID
            )
            return (0, 0, 1)
        }
    }
}
