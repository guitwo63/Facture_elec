import Foundation

public struct PurchaseInvoiceStatusOverride: Codable, Hashable, Identifiable {
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

/// Pendant de `InvoiceStatusStore` côté achats — même architecture (table de réglages
/// éditable, code réforme non modifiable toujours réaligné, entrées orphelines purgées au
/// chargement). Voir la doc de `InvoiceStatusStore` pour le détail de chaque garantie ;
/// reproduite ici à l'identique, retypée sur `PurchaseInvoiceStatus`.
public final class PurchaseInvoiceStatusStore: ObservableObject {
    public static let shared = PurchaseInvoiceStatusStore()

    @Published public var overrides: [PurchaseInvoiceStatusOverride]
    /// Surcharge éparse par société (Réglages > Tables) — voir `SocietyScopedCatalog`.
    @Published public var overridesBySociety: [UUID: [PurchaseInvoiceStatusOverride]] = [:]

    private let defaults = AppPersistence.defaults
    private let env = AppEnvironment.shared
    private var storageKey: String { env.key("facturx.purchaseInvoiceStatuses.v1") }
    private var overridesBySocietyKey: String { env.key("facturx.purchaseInvoiceStatuses.bysociety.v1") }

    public static var defaults: [PurchaseInvoiceStatusOverride] {
        PurchaseInvoiceStatus.allCases.map { s in
            PurchaseInvoiceStatusOverride(
                id: s.rawValue,
                label: s.label,
                systemImage: s.systemImage,
                hexColor: s.hexColor,
                reformCode: PurchaseInvoiceStatusStore.reformCode(for: s),
                transitionCodes: s.allowedTransitions().map { $0.rawValue }
            )
        }
    }

    /// Code d'événement SUPER PDP envoyé au fournisseur quand ce statut fonctionnel est
    /// atteint — le pendant "achat" de `InvoiceStatusStore.reformCode(for:)`. `fr:211`
    /// (Paiement envoyé) est le premier usage réel de ce code : côté ventes, seul son
    /// pendant réception `fr:212` (Paiement reçu) est utilisé. Non modifiable par
    /// l'utilisateur : réaligné à chaque chargement, voir `load()`.
    static func reformCode(for status: PurchaseInvoiceStatus) -> String? {
        switch status {
        case .validated: return "fr:205"  // Validée (AIFE "APPROUVEE")
        case .disputed: return "fr:207"   // Contestée (AIFE "LITIGEE")
        case .refused: return "fr:210"    // Refusée (AIFE "REFUSEE")
        case .paid: return "fr:211"       // Paiement envoyé (nous payons le fournisseur)
        default: return nil
        }
    }

    public init() {
        self.overrides = PurchaseInvoiceStatusStore.defaults
        load()
    }

    public func load() {
        // Chargé avant le save() plus bas (qui persiste aussi overridesBySociety) — voir
        // InvoiceStatusStore.load() pour l'explication complète de cet ordre.
        if let data = defaults.data(forKey: overridesBySocietyKey),
           let decoded = try? JSONDecoder().decode([UUID: [PurchaseInvoiceStatusOverride]].self, from: data) {
            overridesBySociety = decoded
        }
        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([PurchaseInvoiceStatusOverride].self, from: data),
           !decoded.isEmpty {
            var byID = Dictionary(uniqueKeysWithValues: decoded.map { ($0.id, $0) })
            for d in PurchaseInvoiceStatusStore.defaults where byID[d.id] == nil {
                byID[d.id] = d
            }
            for s in PurchaseInvoiceStatus.allCases {
                byID[s.rawValue]?.reformCode = PurchaseInvoiceStatusStore.reformCode(for: s)
            }
            overrides = PurchaseInvoiceStatus.allCases.compactMap { byID[$0.rawValue] }
            save()
        }
    }

    public func override(for status: PurchaseInvoiceStatus) -> PurchaseInvoiceStatusOverride {
        overrides.first { $0.id == status.rawValue }
            ?? PurchaseInvoiceStatusOverride(id: status.rawValue, label: status.label, systemImage: status.systemImage, hexColor: status.hexColor)
    }

    /// Variante par société — voir `InvoiceStatusStore.override(for:companyID:)`.
    public func override(for status: PurchaseInvoiceStatus, companyID: UUID?) -> PurchaseInvoiceStatusOverride {
        let effectiveID = companyID ?? PartyDirectory.shared.principaleSocieteID
        if let effectiveID,
           let resolved = SocietyScopedCatalog.resolvedElement(id: status.rawValue, overrideForSociety: overridesBySociety[effectiveID]) {
            return resolved
        }
        return override(for: status)
    }

    /// Statut fonctionnel que ce code déclenche pour une facture d'achat déjà déposée sur
    /// SUPER PDP, `nil` si le statut n'a pas de code réforme (donc rien à envoyer — voir
    /// aussi le guard sur `superPDPRemoteID` côté UI, une facture saisie à la main n'a rien
    /// à notifier puisqu'elle n'a jamais été déposée par le fournisseur sur PDP).
    public func pdpFeedback(for status: PurchaseInvoiceStatus) -> String? {
        override(for: status).reformCode
    }

    public func allowedTransitions(from status: PurchaseInvoiceStatus, isAdmin: Bool) -> [PurchaseInvoiceStatus] {
        allowedTransitions(from: status, companyID: nil, isAdmin: isAdmin)
    }

    /// Variante par société — voir `InvoiceStatusStore.allowedTransitions(from:companyID:isAdmin:)`.
    public func allowedTransitions(from status: PurchaseInvoiceStatus, companyID: UUID?, isAdmin: Bool) -> [PurchaseInvoiceStatus] {
        let configured = override(for: status, companyID: companyID).transitionCodes.compactMap { PurchaseInvoiceStatus(rawValue: $0) }
        guard isAdmin else { return configured }
        var extended = configured
        for s in PurchaseInvoiceStatus.allCases where s != status && !extended.contains(s) {
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

    /// Commence (ou remplace) la personnalisation de ce statut pour cette société.
    public func setOverride(_ override: PurchaseInvoiceStatusOverride, companyID: UUID) {
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
    public func removeOverride(for status: PurchaseInvoiceStatus, companyID: UUID) {
        overridesBySociety[companyID]?.removeAll { $0.id == status.rawValue }
        if overridesBySociety[companyID]?.isEmpty == true {
            overridesBySociety.removeValue(forKey: companyID)
        }
        save()
    }

    public func reset() {
        overrides = PurchaseInvoiceStatusStore.defaults
        defaults.removeObject(forKey: storageKey)
    }

    public func remove(at idx: Int) {
        guard overrides.indices.contains(idx) else { return }
        guard !overrides[idx].isReformStatus else { return }
        overrides.remove(at: idx)
        save()
    }

    public func append(_ override: PurchaseInvoiceStatusOverride) {
        overrides.append(override)
        save()
    }
}
