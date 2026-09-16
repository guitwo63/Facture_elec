import Foundation

/// Heuristiques d'extraction sur le texte brut issu d'un OCR (scan/photo d'un
/// document papier — bon de commande, devis fournisseur…). Ne prétend jamais
/// être fiable à 100% : chaque suggestion doit être confirmée par l'utilisateur
/// avant création de la commande, jamais appliquée silencieusement.
public enum ScannedDocumentParser {

    /// Cherche une référence de commande/devis à proximité d'un mot-clé
    /// (« commande », « réf »/« référence », « order », « devis »).
    public static func extractReference(from text: String) -> String? {
        // Le lookahead exige un chiffre dans la valeur capturée : sans lui, un mot-clé
        // suivi d'un simple mot (ex. « BON DE COMMANDE » en en-tête, avant la vraie
        // ligne « Commande n° BC-2026-0451 ») serait pris à tort pour la référence.
        let pattern = #"(?:commande|réf(?:érence)?|order|devis)\s*n?[°ºo]?\s*[:\-]?\s*((?=[A-Z0-9\-\/\.]*\d)[A-Z0-9][A-Z0-9\-\/\.]{2,19})"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              let group = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[group])
    }

    /// Première date au format JJ/MM/AAAA (ou avec « . »/« - » comme séparateur) trouvée.
    public static func extractDate(from text: String, calendar: Calendar = .current) -> Date? {
        let pattern = #"\b(\d{1,2})[\/\.\-](\d{1,2})[\/\.\-](\d{2,4})\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range) else { return nil }
        func intGroup(_ idx: Int) -> Int? {
            guard let r = Range(match.range(at: idx), in: text) else { return nil }
            return Int(text[r])
        }
        guard var day = intGroup(1), var month = intGroup(2), var year = intGroup(3) else { return nil }
        if day > 31 || month > 12 { swap(&day, &month) }
        guard day >= 1, day <= 31, month >= 1, month <= 12 else { return nil }
        if year < 100 { year += 2000 }
        var comps = DateComponents()
        comps.day = day; comps.month = month; comps.year = year
        return calendar.date(from: comps)
    }

    /// Premier numéro à 9 chiffres (SIREN) trouvé, espaces/points ignorés.
    /// Ne vérifie pas la clé de contrôle : simple candidat à confirmer.
    public static func extractSIREN(from text: String) -> String? {
        // Bornes larges (7 à 14 caractères de séparateurs/chiffres entre le premier et
        // le dernier chiffre) pour couvrir aussi bien "123456789" que "123 456 789" ou
        // "123.456.789" ; le filtre sur le nombre de chiffres élimine les faux positifs.
        let pattern = #"\b(\d[\d \.]{7,14}\d)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        for match in regex.matches(in: text, options: [], range: range) {
            guard let group = Range(match.range(at: 1), in: text) else { continue }
            let digits = text[group].filter(\.isNumber)
            if digits.count == 9 { return String(digits) }
        }
        return nil
    }
}
