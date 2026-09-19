import Foundation

/// Une ligne de la table de paramétrage des codes d'événement SUPER PDP (Réglages > Tables
/// > Statuts SUPER PDP) : le libellé français affiché pour ce code (dans le journal SUPER
/// PDP de chaque facture), et la règle de mise à jour qu'il déclenche côté statut
/// fonctionnel de la facture (`InvoiceStatus`), le cas échéant.
public struct PDPEventCodeOverride: Codable, Hashable, Identifiable {
    public var id: String
    public var label: String
    /// `rawValue` d'un `InvoiceStatus` si ce code doit faire avancer le statut fonctionnel
    /// de la facture quand il est reçu (ou envoyé) ; `nil` si le code est purement
    /// informationnel (visible dans le journal SUPER PDP, sans effet sur le statut).
    public var functionalTransition: String?
    /// `true` pour les codes officiels connus par défaut (non supprimables — seuls le
    /// libellé et la règle de mise à jour sont modifiables) ; `false` pour un code ajouté
    /// manuellement par l'administrateur (ex. un nouveau code SUPER PDP pas encore
    /// documenté par l'app), librement supprimable.
    public var isSystemDefined: Bool

    public init(id: String, label: String, functionalTransition: String? = nil, isSystemDefined: Bool = false) {
        self.id = id
        self.label = label
        self.functionalTransition = functionalTransition
        self.isSystemDefined = isSystemDefined
    }
}

/// Table de paramétrage des codes d'événement SUPER PDP (`fr:2XX`, table officielle
/// "Meaning of fr:* statuses" — https://superpdp.tech/openapi — et Spécifications
/// Externes AIFE chapitres 5-6). Remplace le switch codé en dur qui vivait dans
/// `PDPStatusMapper.functionalTransition(for:)` (`SuperPDPStatusSync.swift`, côté app) :
/// l'administrateur peut désormais ajuster les libellés et la règle de mise à jour sans
/// modification de code, et ajouter un nouveau code SUPER PDP dès que sa signification
/// est connue (ex. fr:220, ajouté par SUPER PDP en 1.33.0 mais pas encore documenté au
/// moment de l'écriture de cette table).
public final class SuperPDPStatusCodeStore: ObservableObject {
    public static let shared = SuperPDPStatusCodeStore()

    @Published public var overrides: [PDPEventCodeOverride]
    /// Surcharge éparse par société (Réglages > Tables) — voir `SocietyScopedCatalog`.
    @Published public var overridesBySociety: [UUID: [PDPEventCodeOverride]] = [:]

    private let defaults = UserDefaults.standard
    private let env = AppEnvironment.shared
    private var storageKey: String { env.key("facturx.superpdp.statusCodes.v1") }
    private var overridesBySocietyKey: String { env.key("facturx.superpdp.statusCodes.bysociety.v1") }

    public static let defaultCodes: [PDPEventCodeOverride] = [
        PDPEventCodeOverride(id: "fr:200", label: "Déposée", isSystemDefined: true),
        PDPEventCodeOverride(id: "fr:201", label: "Envoyée", isSystemDefined: true),
        PDPEventCodeOverride(id: "fr:202", label: "Reçue", isSystemDefined: true),
        PDPEventCodeOverride(id: "fr:203", label: "Mise à disposition", isSystemDefined: true),
        PDPEventCodeOverride(id: "fr:204", label: "Accusé de réception", isSystemDefined: true),
        PDPEventCodeOverride(id: "fr:205", label: "Acceptée", functionalTransition: InvoiceStatus.accepted.rawValue, isSystemDefined: true),
        PDPEventCodeOverride(id: "fr:206", label: "Partiellement acceptée", functionalTransition: InvoiceStatus.refused.rawValue, isSystemDefined: true),
        PDPEventCodeOverride(id: "fr:207", label: "Contestée", functionalTransition: InvoiceStatus.disputed.rawValue, isSystemDefined: true),
        PDPEventCodeOverride(id: "fr:208", label: "En attente", isSystemDefined: true),
        PDPEventCodeOverride(id: "fr:209", label: "Complétée", isSystemDefined: true),
        PDPEventCodeOverride(id: "fr:210", label: "Refusée", functionalTransition: InvoiceStatus.refused.rawValue, isSystemDefined: true),
        PDPEventCodeOverride(id: "fr:211", label: "Paiement envoyé", isSystemDefined: true),
        // fr:212 reçu resout toujours vers .paid (paiement total) : le statut réseau seul
        // ne dit pas si le montant reçu couvre la facture en entier ou non. `.partiallyPaid`
        // reste donc un statut posé localement par le comptable (jamais déduit d'un
        // événement PDP reçu) ; réglable ici si SUPER PDP précise un jour la distinction.
        PDPEventCodeOverride(id: "fr:212", label: "Paiement reçu", functionalTransition: InvoiceStatus.paid.rawValue, isSystemDefined: true),
        PDPEventCodeOverride(id: "fr:213", label: "Rejetée (validation technique)", functionalTransition: InvoiceStatus.refused.rawValue, isSystemDefined: true),
        PDPEventCodeOverride(id: "fr:220", label: "Fr:220 (nouveau, signification non encore documentée par SUPER PDP)", isSystemDefined: true),
        PDPEventCodeOverride(id: "fr:501", label: "Irrecevable", functionalTransition: InvoiceStatus.refused.rawValue, isSystemDefined: true),
    ]

    public init() {
        self.overrides = Self.defaultCodes
        load()
    }

    public func load() {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([PDPEventCodeOverride].self, from: data),
              !decoded.isEmpty else {
            overrides = Self.defaultCodes
            return
        }
        // Garde tel quel ce qui est déjà persisté (personnalisations de libellé/règle de
        // mise à jour comprises, et les codes ajoutés manuellement par l'administrateur),
        // et complète avec les codes système apparus depuis (nouvelle version de l'app)
        // sans jamais écraser une donnée déjà là.
        var merged = decoded
        let knownIDs = Set(decoded.map(\.id))
        for d in Self.defaultCodes where !knownIDs.contains(d.id) {
            merged.append(d)
        }
        overrides = merged
        if let data = defaults.data(forKey: overridesBySocietyKey),
           let decoded = try? JSONDecoder().decode([UUID: [PDPEventCodeOverride]].self, from: data) {
            overridesBySociety = decoded
        }
    }

    public func save() {
        if let data = try? JSONEncoder().encode(overrides) {
            defaults.set(data, forKey: storageKey)
        }
        if let data = try? JSONEncoder().encode(overridesBySociety) {
            defaults.set(data, forKey: overridesBySocietyKey)
        }
    }

    /// Commence (ou remplace) la personnalisation de ce code pour cette société.
    public func setOverride(_ override: PDPEventCodeOverride, companyID: UUID) {
        var list = overridesBySociety[companyID] ?? []
        if let idx = list.firstIndex(where: { $0.id == override.id }) {
            list[idx] = override
        } else {
            list.append(override)
        }
        overridesBySociety[companyID] = list
        save()
    }

    /// Revient au réglage global pour ce code sur cette société.
    public func removeOverride(id: String, companyID: UUID) {
        overridesBySociety[companyID]?.removeAll { $0.id == id }
        if overridesBySociety[companyID]?.isEmpty == true {
            overridesBySociety.removeValue(forKey: companyID)
        }
        save()
    }

    public func override(for code: String) -> PDPEventCodeOverride? {
        let normalized = code.lowercased()
        return overrides.first { $0.id.lowercased() == normalized }
    }

    /// Variante par société — voir `InvoiceStatusStore.override(for:companyID:)`.
    public func override(for code: String, companyID: UUID?) -> PDPEventCodeOverride? {
        let normalized = code.lowercased()
        if let companyID, let overrides = overridesBySociety[companyID],
           let match = overrides.first(where: { $0.id.lowercased() == normalized }) {
            return match
        }
        return override(for: code)
    }

    /// Statut fonctionnel que ce code déclenche, s'il y en a un — c'est la passerelle
    /// utilisée par `PDPStatusMapper.functionalTransition(for:)`.
    public func functionalTransition(for code: String) -> InvoiceStatus? {
        guard let raw = override(for: code)?.functionalTransition else { return nil }
        return InvoiceStatus(rawValue: raw)
    }

    /// Variante par société.
    public func functionalTransition(for code: String, companyID: UUID?) -> InvoiceStatus? {
        guard let raw = override(for: code, companyID: companyID)?.functionalTransition else { return nil }
        return InvoiceStatus(rawValue: raw)
    }

    public func upsert(_ item: PDPEventCodeOverride) {
        if let idx = overrides.firstIndex(where: { $0.id == item.id }) {
            overrides[idx] = item
        } else {
            overrides.append(item)
        }
        save()
    }

    public func remove(_ item: PDPEventCodeOverride) {
        guard !item.isSystemDefined else { return }
        overrides.removeAll { $0.id == item.id }
        save()
    }

    public func resetToDefaults() {
        overrides = Self.defaultCodes
        save()
    }
}
