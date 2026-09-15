import Foundation

/// Validation et formatage d'un IBAN (norme ISO 13616).
/// Sans dépendance externe : contrôle la structure (2 lettres pays + 2 chiffres
/// de contrôle + BBAN) et la clé de contrôle (mod 97 sur l'entier réarrangé).
public enum IBANValidator {

    /// Longueur attendue par code pays (ISO 13616). Permet de valider la
    /// longueur du BBAN indépendamment du calcul de la clé de contrôle.
    public static let lengthsByCountry: [String: Int] = [
        "AD": 24, "AE": 23, "AL": 28, "AT": 20, "AZ": 28, "BA": 20, "BE": 16,
        "BG": 22, "BH": 22, "BR": 29, "BY": 28, "CH": 21, "CR": 22, "CY": 28,
        "CZ": 24, "DE": 22, "DK": 18, "DO": 28, "EE": 20, "EG": 29, "ES": 24,
        "FI": 18, "FO": 18, "FR": 27, "GB": 22, "GE": 22, "GI": 23, "GL": 18,
        "GR": 27, "GT": 28, "HR": 21, "HU": 28, "IE": 22, "IL": 23, "IQ": 23,
        "IS": 26, "IT": 27, "JO": 30, "KW": 30, "KZ": 20, "LB": 28, "LC": 32,
        "LI": 21, "LT": 20, "LU": 20, "LV": 21, "LY": 25, "MC": 27, "MD": 24,
        "ME": 22, "MK": 19, "MR": 27, "MT": 31, "NL": 18, "NO": 15, "PK": 24,
        "PL": 28, "PS": 29, "PT": 25, "QA": 29, "RO": 24, "RS": 22, "SA": 24,
        "SC": 31, "SE": 24, "SI": 19, "SK": 24, "SM": 27, "ST": 25, "SV": 28,
        "TL": 23, "TN": 24, "TR": 26, "UA": 29, "VA": 22, "VG": 24, "XK": 20
    ]

    /// Nettoie un IBAN : retire espaces et séparateurs, met en majuscules.
    public static func normalize(_ iban: String) -> String {
        iban
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "\t", with: "")
            .uppercased()
    }

    /// Valide la structure et la clé de contrôle d'un IBAN.
    /// - Accepte `nil` ou chaîne vide comme « non renseigné » (retourne `false`
    ///   car la validation métier est gérée ailleurs pour l'obligation).
    public static func isValid(_ iban: String?) -> Bool {
        guard let value = iban, !value.trimmingCharacters(in: .whitespaces).isEmpty else {
            return false
        }
        let cleaned = normalize(value)
        guard cleaned.count >= 5 else { return false }
        let country = String(cleaned.prefix(2))
        guard country.unicodeScalars.allSatisfy({ $0.value >= 65 && $0.value <= 90 }) else { return false }
        if let expected = lengthsByCountry[country], cleaned.count != expected {
            return false
        }
        guard cleaned.dropFirst(4).allSatisfy({ $0.isNumber }) else { return false }
        guard let checkDigits = Int(cleaned.dropFirst(2).prefix(2)), (0...99).contains(checkDigits) else {
            return false
        }
        let rearranged = cleaned.dropFirst(4) + cleaned.prefix(4)
        let numeric = rearranged.map { charToDigit($0) }.joined()
        guard let n = Decimal(string: numeric) else { return false }
        let remainder = (n % 97)
        return remainder == 1
    }

    /// Formate un IBAN par blocs de 4 caractères, en majuscules.
    /// Ex. « FR76 3000 6000 ... ». Retourne la chaîne nettoyée si invalide.
    public static func formatted(_ iban: String?) -> String {
        let cleaned = normalize(iban ?? "")
        guard !cleaned.isEmpty else { return "" }
        var result = ""
        for (i, ch) in cleaned.enumerated() {
            if i > 0 && i % 4 == 0 { result.append(" ") }
            result.append(ch)
        }
        return result
    }

    /// Extrait le code pays (2 premières lettres) si l'IBAN est assez long.
    public static func countryCode(_ iban: String?) -> String? {
        let cleaned = normalize(iban ?? "")
        guard cleaned.count >= 2 else { return nil }
        return String(cleaned.prefix(2))
    }

    /// Convertit un caractère alphanumérique en chiffre (A=10 ... Z=35).
    private static func charToDigit(_ ch: Character) -> String {
        if let d = ch.wholeNumberValue { return String(d) }
        let scalar = ch.uppercased().unicodeScalars.first?.value ?? 0
        return String(scalar - 55)
    }
}
