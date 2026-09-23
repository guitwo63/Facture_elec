import Foundation

/// Active/désactive des modules optionnels de l'application. Annuaire et
/// Factures restent toujours actifs (cœur de l'app, rien ne fonctionne sans
/// eux) ; Devis, Ventes (commandes) et Achats peuvent être désactivés par une TPE qui
/// facture directement sans passer par ces étapes.
public struct ModuleSettings: Codable, Equatable {
    public var ordersEnabled: Bool
    public var quotesEnabled: Bool
    public var purchasesEnabled: Bool

    public init(ordersEnabled: Bool = true, quotesEnabled: Bool = true, purchasesEnabled: Bool = true) {
        self.ordersEnabled = ordersEnabled
        self.quotesEnabled = quotesEnabled
        self.purchasesEnabled = purchasesEnabled
    }

    private enum CodingKeys: String, CodingKey {
        case ordersEnabled, quotesEnabled, purchasesEnabled
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ordersEnabled = try c.decodeIfPresent(Bool.self, forKey: .ordersEnabled) ?? true
        quotesEnabled = try c.decodeIfPresent(Bool.self, forKey: .quotesEnabled) ?? true
        purchasesEnabled = try c.decodeIfPresent(Bool.self, forKey: .purchasesEnabled) ?? true
    }
}

public final class ModuleStore: ObservableObject {
    public static let shared = ModuleStore()

    @Published public var settings: ModuleSettings

    private let defaults = AppPersistence.defaults
    private let env = AppEnvironment.shared
    private var storageKey: String { env.key("facturx.modules.v1") }

    public init() {
        if let data = defaults.data(forKey: env.key("facturx.modules.v1")),
           let decoded = try? JSONDecoder().decode(ModuleSettings.self, from: data) {
            settings = decoded
        } else {
            settings = ModuleSettings()
        }
    }

    public func load() {
        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode(ModuleSettings.self, from: data) {
            settings = decoded
        } else {
            settings = ModuleSettings()
        }
    }

    public func save() {
        if let data = try? JSONEncoder().encode(settings) {
            defaults.set(data, forKey: storageKey)
        }
    }
}
