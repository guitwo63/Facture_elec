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
    /// de l'API SUPER PDP — cf. docs/integrations-superpdp.md). Non modifiable par
    /// l'utilisateur : c'est cette table, et non la donnée persistée, qui fait foi
    /// (voir `load()`), pour éviter qu'une valeur erronée reste bloquée en local.
    static func reformCode(for status: InvoiceStatus) -> String? {
        switch status {
        case .paid: return "fr:212"       // Facture encaissée
        case .cancelled: return "fr:320"  // Facture annulée
        case .accepted: return "fr:207"   // Accepté par le destinataire
        case .rejected: return "fr:206"   // Refusé par le destinataire
        case .sentToPDP: return "200"
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
