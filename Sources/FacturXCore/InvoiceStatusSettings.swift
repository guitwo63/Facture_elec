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
    /// Surcharge éparse par société (Réglages > Tables) : une société ne stocke que les
    /// statuts qu'elle personnalise réellement — voir `SocietyScopedCatalog`.
    @Published public var overridesBySociety: [UUID: [InvoiceStatusOverride]] = [:]

    private let defaults = UserDefaults.standard
    private let env = AppEnvironment.shared
    private var storageKey: String { env.key("facturx.invoiceStatuses.v1") }
    private var overridesBySocietyKey: String { env.key("facturx.invoiceStatuses.bysociety.v1") }

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
        // Même code que .paid : la table officielle fr:2XX n'a qu'un événement générique
        // "Paiement reçu" (AIFE distingue PAYEE_PARTIELLEMENT/PAYEE_TOTALEMENT côté
        // fonctionnel, mais pas par un code réseau séparé). Le montant réel se distingue
        // via les données déclarées (`reportedData`) jointes à l'envoi, pas par le code.
        case .partiallyPaid: return "fr:212"
        case .paid: return "fr:212"       // Paiement reçu (AIFE "ENCAISSEE")
        default: return nil
        }
    }

    public init() {
        self.overrides = InvoiceStatusStore.defaults
        load()
    }

    public func load() {
        // Chargé avant tout appel à save() plus bas dans cette méthode (qui persiste aussi
        // overridesBySociety) — sinon ce save() écraserait la surcharge par société avec un
        // dictionnaire encore vide, avant qu'elle n'ait eu la chance d'être lue.
        if let data = defaults.data(forKey: overridesBySocietyKey),
           let decoded = try? JSONDecoder().decode([UUID: [InvoiceStatusOverride]].self, from: data) {
            overridesBySociety = decoded
        }
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

    /// Variante par société : la surcharge de `companyID` pour ce statut si elle existe,
    /// sinon le réglage global (`override(for:)` ci-dessus, avec son propre repli sur le
    /// défaut codé en dur). `companyID == nil` retombe toujours sur le réglage global.
    public func override(for status: InvoiceStatus, companyID: UUID?) -> InvoiceStatusOverride {
        if let companyID,
           let resolved = SocietyScopedCatalog.resolvedElement(id: status.rawValue, overrideForSociety: overridesBySociety[companyID]) {
            return resolved
        }
        return override(for: status)
    }

    /// Transitions autorisées pour un statut donné, lues depuis la configuration
    /// (paramétrable dans Réglages > Statuts). Un administrateur peut en plus forcer
    /// n'importe quel autre statut standard, indépendamment du graphe configuré.
    public func allowedTransitions(from status: InvoiceStatus, isAdmin: Bool) -> [InvoiceStatus] {
        allowedTransitions(from: status, companyID: nil, isAdmin: isAdmin)
    }

    /// Variante par société : lit le graphe de transitions depuis la surcharge de
    /// `companyID` si elle existe pour ce statut, sinon depuis le réglage global.
    public func allowedTransitions(from status: InvoiceStatus, companyID: UUID?, isAdmin: Bool) -> [InvoiceStatus] {
        let configured = override(for: status, companyID: companyID).transitionCodes.compactMap { InvoiceStatus(rawValue: $0) }
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
        if let data = try? JSONEncoder().encode(overridesBySociety) {
            defaults.set(data, forKey: overridesBySocietyKey)
        }
    }

    /// Commence (ou remplace) la personnalisation de ce statut pour cette société — pré-
    /// remplie avec le réglage global actuel comme point de départ, comme "Personnaliser
    /// pour cette société" le fait déjà pour le format de numérotation.
    public func setOverride(_ override: InvoiceStatusOverride, companyID: UUID) {
        var list = overridesBySociety[companyID] ?? []
        if let idx = list.firstIndex(where: { $0.id == override.id }) {
            list[idx] = override
        } else {
            list.append(override)
        }
        overridesBySociety[companyID] = list
        save()
    }

    /// Revient au réglage global pour ce statut sur cette société.
    public func removeOverride(for status: InvoiceStatus, companyID: UUID) {
        overridesBySociety[companyID]?.removeAll { $0.id == status.rawValue }
        if overridesBySociety[companyID]?.isEmpty == true {
            overridesBySociety.removeValue(forKey: companyID)
        }
        save()
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
