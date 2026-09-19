import Foundation

/// Les emails automatiques que l'application peut envoyer au tiers concerné (client ou
/// fournisseur selon le document). La relance de facture existait déjà avant ce fichier
/// (3 paliers d'escalade, voir `PaymentReminderComposer`) avec un contenu spécifique à
/// chaque palier — elle garde ce fonctionnement dédié et n'a donc pas de sujet/corps
/// éditable ici, seulement l'activation. Les 4 autres sont de nouveaux emails simples
/// (un seul sujet/corps, avec variables) entièrement paramétrables.
public enum EmailTemplateKind: String, Codable, CaseIterable, Identifiable {
    case quoteSent
    case orderConfirmation
    case deliveryNotice
    case invoiceSent
    case invoiceReminder

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .quoteSent: return "Envoi d'un devis"
        case .orderConfirmation: return "Confirmation de commande"
        case .deliveryNotice: return "Avis de livraison"
        case .invoiceSent: return "Envoi de facture"
        case .invoiceReminder: return "Relance de facture"
        }
    }

    public var systemImage: String {
        switch self {
        case .quoteSent: return "doc.text.below.ecg"
        case .orderConfirmation: return "cart.fill"
        case .deliveryNotice: return "shippingbox.fill"
        case .invoiceSent: return "doc.text.fill"
        case .invoiceReminder: return "bell.fill"
        }
    }

    /// La relance a son propre contenu par palier (`PaymentReminderComposer`), pas de
    /// sujet/corps unique à éditer ici.
    public var hasEditableContent: Bool { self != .invoiceReminder }

    public var defaultSubject: String {
        switch self {
        case .quoteSent: return "Votre devis {{numero}}"
        case .orderConfirmation: return "Confirmation de votre commande {{numero}}"
        case .deliveryNotice: return "Avis de livraison — commande {{numero}}"
        case .invoiceSent: return "Votre facture {{numero}}"
        case .invoiceReminder: return ""
        }
    }

    public var defaultBody: String {
        switch self {
        case .quoteSent:
            return """
            Bonjour,

            Veuillez trouver ci-joint notre devis n° {{numero}}, d'un montant de {{montant}}, valable jusqu'au {{date}}.

            N'hésitez pas à nous contacter pour toute question.

            Cordialement,
            {{societe}}
            """
        case .orderConfirmation:
            return """
            Bonjour,

            Nous vous confirmons la bonne prise en compte de votre commande n° {{numero}}, d'un montant de {{montant}}.

            Cordialement,
            {{societe}}
            """
        case .deliveryNotice:
            return """
            Bonjour,

            Nous vous informons que votre commande n° {{numero}} est en cours de livraison.

            Cordialement,
            {{societe}}
            """
        case .invoiceSent:
            return """
            Bonjour,

            Veuillez trouver ci-joint notre facture n° {{numero}}, d'un montant de {{montant}}, à régler avant le {{date}}.

            Cordialement,
            {{societe}}
            """
        case .invoiceReminder:
            return ""
        }
    }

    /// Placeholders disponibles dans le sujet/corps, substitués à l'envoi. Affichés dans
    /// Réglages pour rappeler à l'utilisateur ce qu'il peut utiliser.
    public static let placeholderHelp = "Variables disponibles : {{numero}}, {{client}}, {{societe}}, {{montant}}, {{date}}"
}

/// Réglage d'un email automatique : activé/désactivé et, pour les types qui en ont un,
/// son sujet/corps. Un type absent de `EmailTemplateStore.templates` (première installation,
/// ou nouveau type ajouté après coup) retombe sur `EmailTemplateKind.default*` — voir
/// `EmailTemplateStore.template(for:)`.
public struct EmailTemplate: Codable, Hashable, Identifiable {
    public var kind: EmailTemplateKind
    public var enabled: Bool
    public var subject: String
    public var body: String

    public var id: String { kind.rawValue }

    public init(kind: EmailTemplateKind, enabled: Bool = true, subject: String? = nil, body: String? = nil) {
        self.kind = kind
        self.enabled = enabled
        self.subject = subject ?? kind.defaultSubject
        self.body = body ?? kind.defaultBody
    }

    private enum CodingKeys: String, CodingKey {
        case kind, enabled, subject, body
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Décodé en String d'abord : decodeIfPresent(EmailTemplateKind.self, ...) lèverait
        // toujours une erreur sur une valeur inconnue (ex. un type ajouté par une version plus
        // récente puis rouverte dans une version plus ancienne) au lieu de retomber sur un défaut.
        let kindRaw = try c.decodeIfPresent(String.self, forKey: .kind) ?? EmailTemplateKind.quoteSent.rawValue
        let decodedKind = EmailTemplateKind(rawValue: kindRaw) ?? .quoteSent
        kind = decodedKind
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        subject = try c.decodeIfPresent(String.self, forKey: .subject) ?? decodedKind.defaultSubject
        body = try c.decodeIfPresent(String.self, forKey: .body) ?? decodedKind.defaultBody
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(kind, forKey: .kind)
        try c.encode(enabled, forKey: .enabled)
        try c.encode(subject, forKey: .subject)
        try c.encode(body, forKey: .body)
    }
}

public final class EmailTemplateStore: ObservableObject {
    public static let shared = EmailTemplateStore()

    /// Interrupteur général : désactivé, tous les boutons d'envoi disparaissent de
    /// l'application, quel que soit l'état de chaque modèle individuel. Reste global (pas de
    /// surcharge par société) — c'est un coupe-circuit de la fonctionnalité entière, pas un
    /// contenu à personnaliser.
    @Published public var globalEnabled: Bool = true
    @Published public var templates: [EmailTemplate]
    /// Surcharge éparse par société (Réglages > Application > Emails automatiques) — voir
    /// `SocietyScopedCatalog`. `companyID == nil` résout sur la société principale si une a
    /// été désignée (voir `PartyDirectory.principaleSocieteID`), sinon `templates`.
    @Published public var templatesBySociety: [UUID: [EmailTemplate]] = [:]

    private let defaults = UserDefaults.standard
    private let env = AppEnvironment.shared
    private var globalKey: String { env.key("facturx.email.templates.enabled.v1") }
    private var templatesKey: String { env.key("facturx.email.templates.v1") }
    private var templatesBySocietyKey: String { env.key("facturx.email.templates.bysociety.v1") }

    public init() {
        self.templates = EmailTemplateKind.allCases.map { EmailTemplate(kind: $0) }
        load()
    }

    public func load() {
        globalEnabled = defaults.object(forKey: globalKey) as? Bool ?? true
        if let data = defaults.data(forKey: templatesKey),
           let decoded = try? JSONDecoder().decode([EmailTemplate].self, from: data),
           !decoded.isEmpty {
            templates = decoded
        }
        if let data = defaults.data(forKey: templatesBySocietyKey),
           let decoded = try? JSONDecoder().decode([UUID: [EmailTemplate]].self, from: data) {
            templatesBySociety = decoded
        }
    }

    public func save() {
        defaults.set(globalEnabled, forKey: globalKey)
        if let data = try? JSONEncoder().encode(templates) {
            defaults.set(data, forKey: templatesKey)
        }
        if let data = try? JSONEncoder().encode(templatesBySociety) {
            defaults.set(data, forKey: templatesBySocietyKey)
        }
    }

    /// Le modèle pour un type donné, ou un modèle par défaut si absent (nouveau type
    /// ajouté après coup, jamais persisté chez cet utilisateur).
    public func template(for kind: EmailTemplateKind) -> EmailTemplate {
        templates.first { $0.kind == kind } ?? EmailTemplate(kind: kind)
    }

    /// Variante par société : la surcharge de `companyID` pour ce type si elle existe, sinon
    /// celle de la société principale, sinon le réglage global.
    public func template(for kind: EmailTemplateKind, companyID: UUID?) -> EmailTemplate {
        let effectiveID = companyID ?? PartyDirectory.shared.principaleSocieteID
        if let effectiveID,
           let resolved = SocietyScopedCatalog.resolvedElement(id: kind.rawValue, overrideForSociety: templatesBySociety[effectiveID]) {
            return resolved
        }
        return template(for: kind)
    }

    /// Liste effective pour une société : le réglage global, avec les modèles de la société
    /// superposés par type. `companyID == nil` résout sur la société principale si une a été
    /// désignée, sinon le réglage global.
    public func list(for companyID: UUID?) -> [EmailTemplate] {
        guard let effectiveID = companyID ?? PartyDirectory.shared.principaleSocieteID else { return templates }
        return SocietyScopedCatalog.resolvedList(global: templates, overrideForSociety: templatesBySociety[effectiveID])
    }

    public func upsert(_ template: EmailTemplate) {
        if let idx = templates.firstIndex(where: { $0.kind == template.kind }) {
            templates[idx] = template
        } else {
            templates.append(template)
        }
        save()
    }

    /// Commence (ou remplace) la personnalisation de ce modèle pour cette société.
    public func setOverride(_ template: EmailTemplate, companyID: UUID) {
        var list = templatesBySociety[companyID] ?? []
        if let idx = list.firstIndex(where: { $0.kind == template.kind }) {
            list[idx] = template
        } else {
            list.append(template)
        }
        templatesBySociety[companyID] = list
        save()
    }

    /// Revient au réglage hérité (société principale, ou global) pour ce modèle sur cette société.
    public func removeOverride(kind: EmailTemplateKind, companyID: UUID) {
        templatesBySociety[companyID]?.removeAll { $0.kind == kind }
        if templatesBySociety[companyID]?.isEmpty == true {
            templatesBySociety.removeValue(forKey: companyID)
        }
        save()
    }

    /// Ce que doit lire un bouton d'envoi : `true` seulement si l'interrupteur général
    /// ET le modèle concerné sont tous les deux actifs.
    public func isSendEnabled(_ kind: EmailTemplateKind) -> Bool {
        globalEnabled && template(for: kind).enabled
    }

    /// Variante par société — voir `template(for:companyID:)`.
    public func isSendEnabled(_ kind: EmailTemplateKind, companyID: UUID?) -> Bool {
        globalEnabled && template(for: kind, companyID: companyID).enabled
    }
}

/// Substitue les variables `{{nom}}` d'un modèle par leurs valeurs. Une variable non
/// fournie est laissée telle quelle plutôt que de faire échouer l'envoi — mieux vaut un
/// email un peu maladroit qu'un email bloqué.
public enum EmailComposer {
    public static func compose(template: EmailTemplate, variables: [String: String]) -> (subject: String, body: String) {
        func substitute(_ s: String) -> String {
            var result = s
            for (key, value) in variables {
                result = result.replacingOccurrences(of: "{{\(key)}}", with: value)
            }
            return result
        }
        return (substitute(template.subject), substitute(template.body))
    }
}
