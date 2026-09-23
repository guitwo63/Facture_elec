import Foundation

/// Code article GS1 (GTIN-8, -12, -13 ou -14, ex-EAN/UPC) : la valeur attendue dans le BT-157
/// (`ram:GlobalID`), que `CIIXMLGenerator` émet avec le schéma 0160 (GTIN).
public enum GTINValidator {
    /// Longueur admise et clé de contrôle GS1 : en partant de la droite, hors clé, les
    /// chiffres sont pondérés 3, 1, 3, 1… ; la clé complète la somme à la dizaine supérieure.
    public static func isValid(_ value: String) -> Bool {
        guard [8, 12, 13, 14].contains(value.count),
              value.allSatisfy({ $0.isASCII && $0.isNumber }) else { return false }
        let digits = value.compactMap { $0.wholeNumberValue }
        let sum = digits.dropLast().reversed().enumerated().reduce(0) { total, item in
            total + item.element * (item.offset % 2 == 0 ? 3 : 1)
        }
        return (10 - sum % 10) % 10 == digits.last
    }
}
