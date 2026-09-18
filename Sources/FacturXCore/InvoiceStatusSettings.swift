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

    /// Code d'événement SUPER PDP associé à chaque statut standard (table officielle
    /// "Meaning of fr:* statuses" de la doc SUPER PDP — https://superpdp.tech/openapi —
    /// et Spécifications Externes AIFE chapitres 5-6). Non modifiable par l'utilisateur :
    /// c'est cette table, et non la donnée persistée, qui fait foi (voir `load()`), pour
    /// éviter qu'une valeur erronée reste bloquée en local. `accepted`/`rejected`/
    /// `cancelled` gardent volontairement leurs codes déjà en usage avant cette évolution
    /// (fr:207/fr:206/fr:320) — la correction vers les codes officiellement exacts
    /// (fr:205 pour "Acceptée" ; pas d'équivalent réforme pour "Annulée" ; et `rejected`
    /// recouvre déjà, une fois corrigé, le même sens que `technicallyRejected` — à
    /// clarifier dans ce même chantier) est volontairement séparée de celui-ci.
    static func reformCode(for status: InvoiceStatus) -> String? {
        switch status {
        case .sentToPDP: return "200"            // Déposée — jamais envoyé isolément, voir notifyPDPStatusChange
        case .sentToRecipient: return "fr:201"   // Envoyée — réseau, non créable via l'API
        case .receivedByRecipient: return "fr:202" // Reçue — réseau, non créable via l'API
        case .madeAvailable: return "fr:203"     // Mise à disposition — réseau, non créable via l'API
        case .acknowledged: return "fr:204"      // Accusé de réception
        case .onHold: return "fr:208"            // En attente
        case .accepted: return "fr:207"          // Accepté par le destinataire (code à corriger, voir doc de l'enum)
        case .rejected: return "fr:206"          // Refusé par le destinataire (code à corriger, voir doc de l'enum)
        case .refused: return "fr:210"           // Refusée par le destinataire (AIFE "REFUSEE")
        case .technicallyRejected: return "fr:213" // Rejetée, validation technique — réseau, non créable via l'API
        case .completed: return "fr:209"         // Complétée
        case .paymentSent: return "fr:211"       // Paiement envoyé
        case .paid: return "fr:212"              // Facture encaissée
        case .cancelled: return "fr:320"         // Facture annulée (code invalide côté réforme, voir doc de l'enum)
        default: return nil
        }
    }

    /// Codes réseau que SUPER PDP rapporte automatiquement (déposée exceptée, portée par
    /// le dépôt lui-même) mais que l'API ne permet pas de créer via `POST /invoice_events`
    /// (absents de l'énumération `status_code_create` documentée). Un statut associé à l'un
    /// de ces codes n'est donc jamais envoyé manuellement — seulement reçu en synchronisation.
    public static let networkOnlyReformCodes: Set<String> = ["200", "fr:200", "fr:201", "fr:202", "fr:203", "fr:213"]

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
            overrides = InvoiceStatus.allCases.compactMap { byID[$0.rawValue] }
            let standard = Set(InvoiceStatus.allCases.map { $0.rawValue })
            overrides.append(contentsOf: decoded.filter { !standard.contains($0.id) })
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
