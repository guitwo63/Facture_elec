import Foundation

public struct InvoiceStatusOverride: Codable, Hashable, Identifiable {
    public var id: String
    public var label: String
    public var systemImage: String
    public var hexColor: String
    public var reformCode: String?
    public var transitionCodes: [String]

    public init(id: String, label: String, systemImage: String, hexColor: String, reformCode: String? = nil, transitionCodes: [String] = []) {
        self.id = id
        self.label = label
        self.systemImage = systemImage
        self.hexColor = hexColor
        self.reformCode = reformCode
        self.transitionCodes = transitionCodes
    }

    public var isReformStatus: Bool { reformCode != nil }
}

public final class InvoiceStatusStore: ObservableObject {
    public static let shared = InvoiceStatusStore()

    @Published public var overrides: [InvoiceStatusOverride]

    private let defaults = UserDefaults.standard
    private let env = AppEnvironment.shared
    private var storageKey: String { env.key("facturx.invoiceStatuses.v1") }

    public static var defaults: [InvoiceStatusOverride] {
        InvoiceStatus.allCases.map { s in
            InvoiceStatusOverride(
                id: s.rawValue,
                label: s.label,
                systemImage: s.systemImage,
                hexColor: s.hexColor,
                reformCode: InvoiceStatusStore.reformCode(for: s),
                transitionCodes: s.allowedTransitions().map { $0.rawValue }
            )
        }
    }

    /// Code d'événement SUPER PDP envoyé quand ce statut fonctionnel est atteint (table
    /// officielle "Meaning of fr:* statuses" de la doc SUPER PDP —
    /// https://superpdp.tech/openapi — et Spécifications Externes AIFE chapitres 5-6).
    /// Non modifiable par l'utilisateur : c'est cette table, et non la donnée persistée,
    /// qui fait foi (voir `load()`). Chaque code ici est bien dans l'énumération
    /// `status_code_create` documentée par SUPER PDP (donc réellement envoyable) — c'est
    /// le pendant "envoi" de `PDPStatusMapper.functionalTransition(for:)` (réception),
    /// dans `SuperPDPStatusSync.swift`. `draft`/`issued`/`cancelled` n'ont pas de code :
    /// purement locaux (aucun équivalent "Annulée" dans la table officielle — voir la doc
    /// de l'enum `InvoiceStatus`).
    static func reformCode(for status: InvoiceStatus) -> String? {
        switch status {
        case .sent: return "200"          // Déposée — jamais envoyé isolément, voir notifyPDPStatusChange
        case .accepted: return "fr:205"   // Acceptée (AIFE "APPROUVEE")
        case .disputed: return "fr:207"   // Contestée (AIFE "LITIGEE")
        case .refused: return "fr:210"    // Refusée (AIFE "REFUSEE")
        case .paid: return "fr:212"       // Paiement reçu (AIFE "ENCAISSEE")
        default: return nil
        }
    }

    public init() {
        self.overrides = InvoiceStatusStore.defaults
        load()
    }

    public func load() {
        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([InvoiceStatusOverride].self, from: data),
           !decoded.isEmpty {
            var byID = Dictionary(uniqueKeysWithValues: decoded.map { ($0.id, $0) })
            for d in InvoiceStatusStore.defaults where byID[d.id] == nil {
                byID[d.id] = d
            }
            // Le code réforme n'est pas éditable : on le réaligne toujours sur la table
            // officielle, y compris pour une donnée déjà persistée (corrige d'anciennes
            // valeurs erronées comme fr:310/fr:311, qui n'existent pas côté SUPER PDP).
            for s in InvoiceStatus.allCases {
                byID[s.rawValue]?.reformCode = InvoiceStatusStore.reformCode(for: s)
            }
            // Un id qui ne correspond à aucun cas actuel de l'enum — un ancien statut
            // retiré d'une version précédente (ex. "sentToPDP"/"rejected" avant le passage
            // au modèle réduit à 8 statuts) — ne doit jamais réapparaître : il ne peut de
            // toute façon jamais être assigné à une facture (`Invoice.status` est typé sur
            // l'enum actuel). Avant ce correctif, ces entrées orphelines étaient traitées
            // comme des valeurs "personnalisées" et resurgissaient indéfiniment.
            overrides = InvoiceStatus.allCases.compactMap { byID[$0.rawValue] }
            save()
        }
    }

    public func override(for status: InvoiceStatus) -> InvoiceStatusOverride {
        overrides.first { $0.id == status.rawValue }
            ?? InvoiceStatusOverride(id: status.rawValue, label: status.label, systemImage: status.systemImage, hexColor: status.hexColor)
    }

    /// Transitions autorisées pour un statut donné, lues depuis la configuration
    /// (paramétrable dans Réglages > Statuts). Un administrateur peut en plus forcer
    /// n'importe quel autre statut standard, indépendamment du graphe configuré.
    public func allowedTransitions(from status: InvoiceStatus, isAdmin: Bool) -> [InvoiceStatus] {
        let configured = override(for: status).transitionCodes.compactMap { InvoiceStatus(rawValue: $0) }
        guard isAdmin else { return configured }
        var extended = configured
        for s in InvoiceStatus.allCases where s != status && !extended.contains(s) {
            extended.append(s)
        }
        return extended
    }

    public func save() {
        if let data = try? JSONEncoder().encode(overrides) {
            defaults.set(data, forKey: storageKey)
        }
    }

    public func reset() {
        overrides = InvoiceStatusStore.defaults
        defaults.removeObject(forKey: storageKey)
    }

    public func remove(at idx: Int) {
        guard overrides.indices.contains(idx) else { return }
        guard !overrides[idx].isReformStatus else { return }
        overrides.remove(at: idx)
        save()
    }

    public func append(_ override: InvoiceStatusOverride) {
        overrides.append(override)
        save()
    }
}
