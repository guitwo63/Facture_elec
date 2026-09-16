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
}
