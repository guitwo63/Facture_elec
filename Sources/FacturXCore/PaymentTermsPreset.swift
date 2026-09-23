import Foundation

/// Règle de calcul de la date d'échéance (BT-9) associée à un préréglage de
/// conditions de paiement. Purement une aide de saisie côté UI : BT-9 reste
/// un champ structuré normal. Une règle à délai (jours nets, fin de mois + jours)
/// calcule l'échéance depuis la date de facture, et l'éditeur grise alors le champ ;
/// `.none` la met à la date de facture et le laisse modifiable. Pour saisir une
/// autre échéance, l'utilisateur choisit « Personnalisé » (voir `PaymentTermsPresetSelection`).
public enum PaymentTermsDueRule: Codable, Hashable {
    case none
    case days(Int)
    case endOfMonthPlusDays(Int)

    /// Vrai si la règle fixe un délai (jours nets, fin de mois + jours) : l'échéance qu'elle
    /// calcule grise le champ Échéance de l'éditeur de facture. Faux pour `.none`.
    public var computesDueDate: Bool {
        if case .none = self { return false }
        return true
    }

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
    /// Surcharge éparse par société (Réglages > Tables) — voir `SocietyScopedCatalog`.
    @Published public var presetsBySociety: [UUID: [PaymentTermsPreset]] = [:]

    private let defaults = AppPersistence.defaults
    private let env = AppEnvironment.shared
    private var storageKey: String { env.key("facturx.paymentTermsPresets.v1") }
    private var presetsBySocietyKey: String { env.key("facturx.paymentTermsPresets.bysociety.v1") }

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
        if let data = defaults.data(forKey: presetsBySocietyKey),
           let decoded = try? JSONDecoder().decode([UUID: [PaymentTermsPreset]].self, from: data) {
            presetsBySociety = decoded
        }
    }

    public func save() {
        if let data = try? JSONEncoder().encode(presets) {
            defaults.set(data, forKey: storageKey)
        }
        if let data = try? JSONEncoder().encode(presetsBySociety) {
            defaults.set(data, forKey: presetsBySocietyKey)
        }
    }

    /// Liste effective pour une société : le réglage global, avec les préréglages de la
    /// société superposés par id. `companyID == nil` résout sur la société principale si une
    /// a été désignée (voir `PartyDirectory.principaleSocieteID`), sinon le réglage global.
    public func list(for companyID: UUID?) -> [PaymentTermsPreset] {
        guard let effectiveID = companyID ?? PartyDirectory.shared.principaleSocieteID else { return presets }
        return SocietyScopedCatalog.resolvedList(global: presets, overrideForSociety: presetsBySociety[effectiveID])
    }

    /// Commence (ou remplace) la personnalisation de ce préréglage pour cette société.
    public func setOverride(_ preset: PaymentTermsPreset, companyID: UUID) {
        var list = presetsBySociety[companyID] ?? []
        if let idx = list.firstIndex(where: { $0.id == preset.id }) {
            list[idx] = preset
        } else {
            list.append(preset)
        }
        presetsBySociety[companyID] = list
        save()
    }

    /// Revient au réglage global pour ce préréglage sur cette société.
    public func removeOverride(id: String, companyID: UUID) {
        presetsBySociety[companyID]?.removeAll { $0.id == id }
        if presetsBySociety[companyID]?.isEmpty == true {
            presetsBySociety.removeValue(forKey: companyID)
        }
        save()
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
        matchingPresetID(for: text, companyID: nil)
    }

    /// Variante par société — cherche aussi parmi les préréglages propres à `companyID`.
    public func matchingPresetID(for text: String?, companyID: UUID?) -> String? {
        matchingPreset(for: text, companyID: companyID)?.id
    }

    /// Le préréglage actif d'un texte de conditions de paiement, tel que `companyID` l'a
    /// personnalisé (texte et règle d'échéance lus dans `list(for:)`, jamais dans le réglage
    /// global seul). `nil` = aucun préréglage de cette société ne correspond ("Personnalisé").
    public func matchingPreset(for text: String?, companyID: UUID?) -> PaymentTermsPreset? {
        let trimmed = text?.trimmingCharacters(in: .whitespaces) ?? ""
        guard !trimmed.isEmpty else { return nil }
        return list(for: companyID).first { $0.text == trimmed }
    }

    /// Un préréglage par id dans la liste effective de `companyID` — pour appliquer le choix
    /// fait dans un menu construit sur `list(for: companyID)`, y compris un préréglage propre
    /// à cette société.
    public func preset(id: String, companyID: UUID?) -> PaymentTermsPreset? {
        list(for: companyID).first { $0.id == id }
    }

    /// Le préréglage que suit une facture : celui de sa société qui a son texte (BT-20), à
    /// condition que l'échéance (BT-9) soit, au jour près, celle qu'il calcule depuis la date
    /// de facture. Un préréglage sans règle ne fixe pas l'échéance : son texte suffit.
    /// `nil` = conditions « Personnalisé », dont une échéance saisie à la main.
    public func matchingPreset(for invoice: Invoice, calendar: Calendar = .current) -> PaymentTermsPreset? {
        guard let preset = matchingPreset(for: invoice.paymentTerms, companyID: invoice.companyID) else { return nil }
        guard preset.dueRule.computesDueDate else { return preset }
        let computed = preset.dueRule.dueDate(from: invoice.issueDate, calendar: calendar)
        return calendar.isDate(invoice.dueDate, inSameDayAs: computed) ? preset : nil
    }
}

/// Ce qu'affiche un menu « Conditions de paiement » (éditeur de facture, fiche société) : un
/// préréglage, ou « Personnalisé » (saisie libre du texte et, sur une facture, de l'échéance).
///
/// Seul le texte est enregistré (BT-20 est une mention libre) : le menu affiche le préréglage
/// qui a ce texte (sur une facture, voir `PaymentTermsPresetStore.matchingPreset(for:)`).
/// Choisir « Personnalisé » ne change ni le texte ni l'échéance, points de départ de la
/// saisie. Le menu retomberait donc aussitôt sur le préréglage, texte en lecture seule et
/// échéance grisée. Ce choix est retenu ici jusqu'à ce que l'utilisateur re-choisisse un
/// préréglage. C'est un état d'édition local, jamais enregistré, propre à l'instance
/// d'éditeur : une par document (`.id(id)` dans les onglets, une feuille par fiche dans
/// l'annuaire). Une échéance modifiée, elle, reste en « Personnalisé » après changement de
/// document ou redémarrage : la facture ne correspond plus au préréglage.
///
/// Une saisie en « Personnalisé » retient aussi ce mode : le menu ne doit pas basculer en
/// pleine frappe quand le texte passe par celui d'un préréglage (« Paiement à 30 jours » est
/// le début de « Paiement à 30 jours fin de mois »), ni griser l'échéance quand la date
/// saisie passe par celle qu'il calcule.
public struct PaymentTermsPresetSelection {
    /// Vrai une fois « Personnalisé » choisi (ou une saisie faite dans ce mode), jusqu'au
    /// choix d'un préréglage.
    public private(set) var isCustom = false

    public init() {}

    /// Retient « Personnalisé » jusqu'au prochain choix d'un préréglage — à appeler avant
    /// d'écrire le texte saisi dans ce mode.
    public mutating func keepCustom() {
        isCustom = true
    }

    /// Préréglage affiché pour ce texte (fiche société), résolu dans la liste de `companyID` ;
    /// `nil` = « Personnalisé ».
    public func activePreset(for text: String?, companyID: UUID?, in store: PaymentTermsPresetStore) -> PaymentTermsPreset? {
        isCustom ? nil : store.matchingPreset(for: text, companyID: companyID)
    }

    /// Préréglage affiché pour cette facture ; `nil` = « Personnalisé ».
    public func activePreset(for invoice: Invoice, in store: PaymentTermsPresetStore, calendar: Calendar = .current) -> PaymentTermsPreset? {
        isCustom ? nil : store.matchingPreset(for: invoice, calendar: calendar)
    }

    /// Choix dans le menu. Un préréglage met fin à « Personnalisé » et est renvoyé : à
    /// l'appelant d'en écrire le texte. « Personnalisé » (`nil`) est retenu et ne renvoie
    /// rien : le document ne change pas. Un id absent de la liste de `companyID` ne change rien.
    public mutating func select(_ presetID: String?, companyID: UUID?, in store: PaymentTermsPresetStore) -> PaymentTermsPreset? {
        guard let presetID else {
            isCustom = true
            return nil
        }
        guard let preset = store.preset(id: presetID, companyID: companyID) else { return nil }
        isCustom = false
        return preset
    }

    /// Choix dans le menu d'une facture. Un préréglage réécrit le texte et recalcule
    /// l'échéance depuis la date de facture : la facture modifiée est renvoyée, pour une seule
    /// écriture. « Personnalisé » (`nil`) renvoie `nil` : la facture ne change pas.
    public mutating func select(_ presetID: String?, for invoice: Invoice, in store: PaymentTermsPresetStore, calendar: Calendar = .current) -> Invoice? {
        guard let preset = select(presetID, companyID: invoice.companyID, in: store) else { return nil }
        var updated = invoice
        updated.paymentTerms = preset.text
        updated.dueDate = preset.dueRule.dueDate(from: invoice.issueDate, calendar: calendar)
        return updated
    }

    /// À appeler avant d'écrire une échéance saisie par l'utilisateur : si le menu affiche
    /// « Personnalisé », ce mode est retenu (voir le type). Un préréglage sans règle, dont
    /// l'échéance reste modifiable, reste affiché.
    public mutating func keepCustomIfShown(for invoice: Invoice, in store: PaymentTermsPresetStore, calendar: Calendar = .current) {
        if activePreset(for: invoice, in: store, calendar: calendar) == nil {
            isCustom = true
        }
    }
}
