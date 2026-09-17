import Foundation

public struct QuoteStatusOverride: Codable, Hashable, Identifiable {
    public var id: String
    public var label: String
    public var systemImage: String
    public var hexColor: String
    public var transitionCodes: [String]

    public init(id: String, label: String, systemImage: String, hexColor: String, transitionCodes: [String] = []) {
        self.id = id
        self.label = label
        self.systemImage = systemImage
        self.hexColor = hexColor
        self.transitionCodes = transitionCodes
    }

    private enum CodingKeys: String, CodingKey {
        case id, label, systemImage, hexColor, transitionCodes
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        label = try c.decode(String.self, forKey: .label)
        systemImage = try c.decode(String.self, forKey: .systemImage)
        hexColor = try c.decode(String.self, forKey: .hexColor)
        transitionCodes = try c.decodeIfPresent([String].self, forKey: .transitionCodes) ?? []
    }
}

/// Paramétrable comme InvoiceStatusStore/OrderStatusStore, mais volontairement plus
/// simple : un devis n'a pas de cycle de vie imposé par un tiers externe (SUPER PDP)
/// à court-circuiter, donc pas de statuts « verrouillés » ni de forçage admin — chaque
/// statut standard reste éditable (libellé, icône, couleur, transitions).
public final class QuoteStatusStore: ObservableObject {
    public static let shared = QuoteStatusStore()

    @Published public var overrides: [QuoteStatusOverride]

    private let defaults = UserDefaults.standard
    private let env = AppEnvironment.shared
    private var storageKey: String { env.key("facturx.quotestatuses.v1") }

    public static var defaultOverrides: [QuoteStatusOverride] {
        QuoteStatus.allCases.map { s in
            QuoteStatusOverride(
                id: s.rawValue, label: s.label, systemImage: s.systemImage, hexColor: s.hexColor,
                transitionCodes: s.allowedTransitions().map { $0.rawValue }
            )
        }
    }

    public init() {
        self.overrides = QuoteStatusStore.defaultOverrides
        load()
    }

    public func load() {
        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([QuoteStatusOverride].self, from: data),
           !decoded.isEmpty {
            var byID = Dictionary(uniqueKeysWithValues: decoded.map { ($0.id, $0) })
            for d in QuoteStatusStore.defaultOverrides where byID[d.id] == nil {
                byID[d.id] = d
            }
            overrides = QuoteStatus.allCases.compactMap { byID[$0.rawValue] }
        }
    }

    public func save() {
        if let data = try? JSONEncoder().encode(overrides) {
            defaults.set(data, forKey: storageKey)
        }
    }

    public func reset() {
        overrides = QuoteStatusStore.defaultOverrides
        defaults.removeObject(forKey: storageKey)
    }

    public func override(for status: QuoteStatus) -> QuoteStatusOverride {
        overrides.first { $0.id == status.rawValue }
            ?? QuoteStatusOverride(id: status.rawValue, label: status.label, systemImage: status.systemImage, hexColor: status.hexColor)
    }

    /// Transitions autorisées depuis un statut, lues depuis la configuration
    /// (Réglages > Tables > Statuts des devis).
    public func allowedTransitions(from status: QuoteStatus) -> [QuoteStatus] {
        override(for: status).transitionCodes.compactMap { QuoteStatus(rawValue: $0) }
    }
}
