import Foundation

/// Règle de calcul de la date d'échéance (BT-9) associée à un préréglage de
/// conditions de paiement. Purement une aide de saisie côté UI : BT-9 reste
/// un champ structuré normal, `.none` laisse la date telle quelle (l'utilisateur
/// la renseigne/modifie toujours manuellement ensuite, aucun champ n'est verrouillé).
public enum PaymentTermsDueRule: Codable, Hashable {
    case none
    case days(Int)
    case endOfMonthPlusDays(Int)

    public func dueDate(from issueDate: Date, calendar: Calendar = .current) -> Date {
        switch self {
        case .none:
            return issueDate
        case .days(let n):
            return calendar.date(byAdding: .day, value: n, to: issueDate) ?? issueDate
        case .endOfMonthPlusDays(let n):
            guard let lastDay = calendar.range(of: .day, in: .month, for: issueDate)?.last else { return issueDate }
            var comps = calendar.dateComponents([.year, .month], from: issueDate)
            comps.day = lastDay
            let endOfMonth = calendar.date(from: comps) ?? issueDate
            return calendar.date(byAdding: .day, value: n, to: endOfMonth) ?? issueDate
        }
    }
}

/// Préréglages de conditions de paiement proposés sur la fiche société, pour
/// éviter de ressaisir le même texte à chaque nouvelle société. Configurables
/// dans Réglages > Tables (comme les statuts ou les tags), pas figés dans le
/// code : le champ stocké (`InvoiceParty.paymentTerms`) reste du texte libre
/// (BT-20 est une mention libre en Factur-X, sans structure normée) — un
/// préréglage n'est qu'une aide de saisie qui écrit ce texte. `dueRule` est
/// une deuxième aide de saisie du même ordre, pour BT-9 (échéance).
public struct PaymentTermsPreset: Codable, Hashable, Identifiable {
    public var id: String
    public var label: String
    public var text: String
    public var dueRule: PaymentTermsDueRule

    public init(id: String = UUID().uuidString, label: String, text: String, dueRule: PaymentTermsDueRule = .none) {
        self.id = id
        self.label = label
        self.text = text
        self.dueRule = dueRule
    }

    private enum CodingKeys: String, CodingKey {
        case id, label, text, dueRule
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        dueRule = try c.decodeIfPresent(PaymentTermsDueRule.self, forKey: .dueRule) ?? .none
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(label, forKey: .label)
        try c.encode(text, forKey: .text)
        try c.encode(dueRule, forKey: .dueRule)
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
            PaymentTermsPreset(id: "comptant", label: "Comptant", text: "Comptant", dueRule: .none),
            PaymentTermsPreset(id: "net30", label: "30 jours net", text: "Paiement à 30 jours", dueRule: .days(30)),
            PaymentTermsPreset(id: "finDeMois30", label: "30 jours fin de mois", text: "Paiement à 30 jours fin de mois", dueRule: .endOfMonthPlusDays(30)),
            PaymentTermsPreset(id: "aReception", label: "À réception", text: "Paiement à réception", dueRule: .none)
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
