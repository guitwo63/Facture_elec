import Foundation

/// Préréglages de conditions de paiement proposés sur la fiche société, pour
/// éviter de ressaisir le même texte à chaque nouvelle société. Configurables
/// dans Réglages > Tables (comme les statuts ou les tags), pas figés dans le
/// code : le champ stocké (`InvoiceParty.paymentTerms`) reste du texte libre
/// (BT-20 est une mention libre en Factur-X, sans structure normée) — un
/// préréglage n'est qu'une aide de saisie qui écrit ce texte.
public struct PaymentTermsPreset: Codable, Hashable, Identifiable {
    public var id: String
    public var label: String
    public var text: String

    public init(id: String = UUID().uuidString, label: String, text: String) {
        self.id = id
        self.label = label
        self.text = text
    }
}

public final class PaymentTermsPresetStore: ObservableObject {
    public static let shared = PaymentTermsPresetStore()

    @Published public var presets: [PaymentTermsPreset]

    private let defaults = UserDefaults.standard
    private let env = AppEnvironment.shared
    private var storageKey: String { env.key("facturx.paymentTermsPresets.v1") }

    public static var defaults: [PaymentTermsPreset] {
        [
            PaymentTermsPreset(id: "comptant", label: "Comptant", text: "Comptant"),
            PaymentTermsPreset(id: "net30", label: "30 jours net", text: "Paiement à 30 jours"),
            PaymentTermsPreset(id: "finDeMois30", label: "30 jours fin de mois", text: "Paiement à 30 jours fin de mois"),
            PaymentTermsPreset(id: "aReception", label: "À réception", text: "Paiement à réception")
        ]
    }

    public init() {
        self.presets = PaymentTermsPresetStore.defaults
        load()
    }

    public func load() {
        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([PaymentTermsPreset].self, from: data),
           !decoded.isEmpty {
            presets = decoded
        }
    }

    public func save() {
        if let data = try? JSONEncoder().encode(presets) {
            defaults.set(data, forKey: storageKey)
        }
    }

    public func append(_ preset: PaymentTermsPreset) {
        presets.append(preset)
        save()
    }

    public func upsert(_ preset: PaymentTermsPreset) {
        if let idx = presets.firstIndex(where: { $0.id == preset.id }) {
            presets[idx] = preset
        } else {
            presets.append(preset)
        }
        save()
    }

    public func remove(at idx: Int) {
        guard presets.indices.contains(idx) else { return }
        presets.remove(at: idx)
        save()
    }

    public func reset() {
        presets = PaymentTermsPresetStore.defaults
        defaults.removeObject(forKey: storageKey)
    }

    /// Retrouve le préréglage correspondant à un texte existant, pour
    /// présélectionner le bon item du menu à l'ouverture de la fiche.
    /// `nil` = aucun préréglage ne correspond (saisie libre, "Personnalisé").
    public func matchingPresetID(for text: String?) -> String? {
        let trimmed = text?.trimmingCharacters(in: .whitespaces) ?? ""
        guard !trimmed.isEmpty else { return nil }
        return presets.first { $0.text == trimmed }?.id
    }
}
