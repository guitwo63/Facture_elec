import Foundation

/// Préréglages de conditions de paiement proposés sur la fiche société, pour
/// éviter de ressaisir le même texte à chaque nouvelle société. Le champ
/// stocké (`InvoiceParty.paymentTerms`) reste du texte libre (BT-20 est une
/// mention libre en Factur-X, sans structure normée) : un préréglage n'est
/// qu'une aide de saisie qui écrit ce texte, jamais un nouveau type de donnée.
public enum PaymentTermsPreset: String, CaseIterable, Identifiable, Hashable {
    case comptant
    case net30
    case finDeMois30
    case aReception
    case personnalise

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .comptant: return "Comptant"
        case .net30: return "30 jours net"
        case .finDeMois30: return "30 jours fin de mois"
        case .aReception: return "À réception"
        case .personnalise: return "Personnalisé"
        }
    }

    /// Texte à écrire dans `paymentTerms` ; `nil` pour "Personnalisé" puisque
    /// ce cas laisse le texte existant tel quel (saisie libre).
    public var text: String? {
        switch self {
        case .comptant: return "Comptant"
        case .net30: return "Paiement à 30 jours"
        case .finDeMois30: return "Paiement à 30 jours fin de mois"
        case .aReception: return "Paiement à réception"
        case .personnalise: return nil
        }
    }

    /// Retrouve le préréglage correspondant à un texte existant, pour
    /// présélectionner le bon item du menu à l'ouverture de la fiche.
    /// Un texte vide ou qui ne correspond à aucun préréglage connu est
    /// traité comme "Personnalisé" plutôt que de forcer une valeur par défaut.
    public static func matching(_ text: String?) -> PaymentTermsPreset {
        let trimmed = text?.trimmingCharacters(in: .whitespaces) ?? ""
        guard !trimmed.isEmpty else { return .personnalise }
        return allCases.first { $0.text == trimmed } ?? .personnalise
    }
}
