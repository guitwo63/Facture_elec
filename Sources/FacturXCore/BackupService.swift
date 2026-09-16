import Foundation

/// Sauvegarde complète en un seul fichier JSON — plus simple qu'une archive
/// multi-fichiers. Couvre les données métier (factures, commandes, tiers) ;
/// les identifiants/clés API restent volontairement exclus (propres à chaque
/// poste et environnement, jamais à faire transiter vers un stockage cloud).
public struct BackupBundle: Codable {
    public var createdAt: Date
    public var appVersion: String
    public var invoices: [Invoice]
    public var orders: [SalesOrder]
    public var parties: [DirectoryEntry]

    public init(
        createdAt: Date = Date(),
        appVersion: String = AppVersion.current,
        invoices: [Invoice],
        orders: [SalesOrder],
        parties: [DirectoryEntry]
    ) {
        self.createdAt = createdAt
        self.appVersion = appVersion
        self.invoices = invoices
        self.orders = orders
        self.parties = parties
    }

    private enum CodingKeys: String, CodingKey {
        case createdAt, appVersion, invoices, orders, parties
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        appVersion = try c.decodeIfPresent(String.self, forKey: .appVersion) ?? ""
        invoices = try c.decodeIfPresent([Invoice].self, forKey: .invoices) ?? []
        orders = try c.decodeIfPresent([SalesOrder].self, forKey: .orders) ?? []
        parties = try c.decodeIfPresent([DirectoryEntry].self, forKey: .parties) ?? []
    }

    /// Nom de fichier suggéré, horodaté, pour éviter d'écraser une sauvegarde précédente.
    public static func suggestedFilename(date: Date = Date()) -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd_HHmm"
        return "facture_elec_sauvegarde_\(df.string(from: date)).json"
    }
}

public enum BackupService {
    public static func capture(
        invoiceStore: InvoiceStore,
        orderStore: OrderStore,
        directory: PartyDirectory
    ) -> BackupBundle {
        BackupBundle(
            invoices: invoiceStore.invoices,
            orders: orderStore.orders,
            parties: directory.entries
        )
    }

    /// Restauration additive (upsert) — jamais destructive : les enregistrements
    /// existants ne sont ni vidés ni écrasés en masse avant restauration, seuls
    /// les éléments du fichier de sauvegarde sont ajoutés/mis à jour par id.
    public static func restore(
        _ bundle: BackupBundle,
        invoiceStore: InvoiceStore,
        orderStore: OrderStore,
        directory: PartyDirectory
    ) {
        bundle.invoices.forEach(invoiceStore.upsert)
        bundle.orders.forEach(orderStore.upsert)
        bundle.parties.forEach(directory.upsert)
    }

    public static func encode(_ bundle: BackupBundle) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(bundle)
    }

    public static func decode(_ data: Data) throws -> BackupBundle {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(BackupBundle.self, from: data)
    }
}

/// Exécute une sauvegarde complète en respectant la stratégie configurée
/// (rétention pCloud + copie locale optionnelle, elle-même soumise à la
/// même rétention) — réutilisable aussi bien depuis le bouton manuel que
/// depuis un futur déclenchement automatique au lancement de l'app.
public enum BackupRunner {
    public static func run(
        bundle: BackupBundle,
        pcloudCredentials: PCloudCredentials,
        strategy: BackupStrategySettings
    ) async throws -> String {
        let data = try BackupService.encode(bundle)
        let filename = BackupBundle.suggestedFilename()
        var parts: [String] = []

        let service = PCloudService()
        let auth = try await service.login(credentials: pcloudCredentials)
        let uploaded = try await service.upload(data: data, filename: filename, credentials: pcloudCredentials, auth: auth)
        parts.append("pCloud : \(uploaded.name)")
        await applyPCloudRetention(service: service, credentials: pcloudCredentials, auth: auth, keep: strategy.retentionCount)

        if let folder = strategy.localBackupFolderPath?.trimmingCharacters(in: .whitespaces), !folder.isEmpty {
            try writeLocal(data: data, filename: filename, folderPath: folder)
            applyLocalRetention(folderPath: folder, keep: strategy.retentionCount)
            parts.append("copie locale : \(folder)")
        }

        return "Sauvegarde réussie — " + parts.joined(separator: " ; ")
    }

    private static func applyPCloudRetention(service: PCloudService, credentials: PCloudCredentials, auth: String, keep: Int) async {
        guard let files = try? await service.listBackups(credentials: credentials, auth: auth) else { return }
        let toDelete = Set(BackupRetention.namesToDelete(sortedDescendingNames: files.map(\.name), keep: keep))
        for file in files where toDelete.contains(file.name) {
            try? await service.delete(fileID: file.fileID, credentials: credentials, auth: auth)
        }
    }

    private static func writeLocal(data: Data, filename: String, folderPath: String) throws {
        let folderURL = URL(fileURLWithPath: folderPath, isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        try data.write(to: folderURL.appendingPathComponent(filename))
    }

    private static func applyLocalRetention(folderPath: String, keep: Int) {
        let folderURL = URL(fileURLWithPath: folderPath, isDirectory: true)
        guard let files = try? FileManager.default.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil) else { return }
        let names = files.map(\.lastPathComponent)
            .filter { $0.hasPrefix("facture_elec_sauvegarde_") && $0.hasSuffix(".json") }
            .sorted(by: >)
        for name in BackupRetention.namesToDelete(sortedDescendingNames: names, keep: keep) {
            try? FileManager.default.removeItem(at: folderURL.appendingPathComponent(name))
        }
    }
}
