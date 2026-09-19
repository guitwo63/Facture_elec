import Foundation

/// Contrôle du préfixe pays d'un numéro de TVA intracommunautaire — BR-CO-09 (EN16931) :
/// les 2 premiers caractères doivent être un code pays ISO 3166-1 alpha-2, à l'exception de
/// la Grèce qui peut utiliser "EL" au lieu de "GR". Ne valide que le préfixe, pas le reste
/// du numéro (format propre à chaque pays, hors périmètre de cette règle).
public enum VATNumberValidator {

    /// Codes ISO 3166-1 alpha-2 actuellement attribués.
    public static let isoCountryCodes: Set<String> = [
        "AD", "AE", "AF", "AG", "AI", "AL", "AM", "AO", "AQ", "AR", "AS", "AT", "AU", "AW", "AX", "AZ",
        "BA", "BB", "BD", "BE", "BF", "BG", "BH", "BI", "BJ", "BL", "BM", "BN", "BO", "BQ", "BR", "BS", "BT", "BV", "BW", "BY", "BZ",
        "CA", "CC", "CD", "CF", "CG", "CH", "CI", "CK", "CL", "CM", "CN", "CO", "CR", "CU", "CV", "CW", "CX", "CY", "CZ",
        "DE", "DJ", "DK", "DM", "DO", "DZ",
        "EC", "EE", "EG", "EH", "ER", "ES", "ET",
        "FI", "FJ", "FK", "FM", "FO", "FR",
        "GA", "GB", "GD", "GE", "GF", "GG", "GH", "GI", "GL", "GM", "GN", "GP", "GQ", "GR", "GS", "GT", "GU", "GW", "GY",
        "HK", "HM", "HN", "HR", "HT", "HU",
        "ID", "IE", "IL", "IM", "IN", "IO", "IQ", "IR", "IS", "IT",
        "JE", "JM", "JO", "JP",
        "KE", "KG", "KH", "KI", "KM", "KN", "KP", "KR", "KW", "KY", "KZ",
        "LA", "LB", "LC", "LI", "LK", "LR", "LS", "LT", "LU", "LV", "LY",
        "MA", "MC", "MD", "ME", "MF", "MG", "MH", "MK", "ML", "MM", "MN", "MO", "MP", "MQ", "MR", "MS", "MT", "MU", "MV", "MW", "MX", "MY", "MZ",
        "NA", "NC", "NE", "NF", "NG", "NI", "NL", "NO", "NP", "NR", "NU", "NZ",
        "OM",
        "PA", "PE", "PF", "PG", "PH", "PK", "PL", "PM", "PN", "PR", "PS", "PT", "PW", "PY",
        "QA",
        "RE", "RO", "RS", "RU", "RW",
        "SA", "SB", "SC", "SD", "SE", "SG", "SH", "SI", "SJ", "SK", "SL", "SM", "SN", "SO", "SR", "SS", "ST", "SV", "SX", "SY", "SZ",
        "TC", "TD", "TF", "TG", "TH", "TJ", "TK", "TL", "TM", "TN", "TO", "TR", "TT", "TV", "TW", "TZ",
        "UA", "UG", "UM", "US", "UY", "UZ",
        "VA", "VC", "VE", "VG", "VI", "VN", "VU",
        "WF", "WS",
        "YE", "YT",
        "ZA", "ZM", "ZW",
    ]

    /// Seule exception prévue par la règle BR-CO-09 elle-même (pas une extension arbitraire :
    /// le texte de la règle cite explicitement "EL" pour la Grèce, au lieu du code ISO "GR").
    private static let additionalAllowedPrefixes: Set<String> = ["EL"]

    /// Vrai si absent/vide (rien à valider ici — l'obligation de présence relève d'autres
    /// règles, ex. BR-S-02/BR-E-02) ou si les 2 premiers caractères sont un préfixe pays valide.
    public static func hasValidCountryPrefix(_ vatNumber: String?) -> Bool {
        guard let value = vatNumber?.trimmingCharacters(in: .whitespaces), !value.isEmpty else { return true }
        guard value.count >= 2 else { return false }
        let prefix = String(value.prefix(2)).uppercased()
        return isoCountryCodes.contains(prefix) || additionalAllowedPrefixes.contains(prefix)
    }
}
