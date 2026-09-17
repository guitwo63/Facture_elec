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

    /// Interprète un nombre au format français ou anglo-saxon (« 1 234,56 »,
    /// « 1234.56 », « 1.234,56 », « 56 »…). `nil` si la chaîne ne contient aucun chiffre.
    public static func parseAmount(_ raw: String) -> Double? {
        var s = raw.trimmingCharacters(in: .whitespaces)
        for token in ["€", "EUR", "eur"] { s = s.replacingOccurrences(of: token, with: "") }
        s = s.replacingOccurrences(of: "\u{202F}", with: "")
            .replacingOccurrences(of: "\u{00A0}", with: "")
            .replacingOccurrences(of: " ", with: "")
            .trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return nil }
        if let commaIdx = s.lastIndex(of: ",") {
            let intPart = s[..<commaIdx].filter(\.isNumber)
            let decPart = s[s.index(after: commaIdx)...].filter(\.isNumber)
            guard !intPart.isEmpty else { return nil }
            return Double("\(intPart).\(decPart.isEmpty ? "0" : decPart)")
        }
        // Pas de virgule : un point final suivi d'exactement 1-2 chiffres est décimal
        // (« 56.5 », « 1234.56 ») ; sinon les points sont des séparateurs de milliers.
        let dotParts = s.split(separator: ".")
        if dotParts.count == 2, (1...2).contains(dotParts[1].count) {
            return Double(s)
        }
        let digitsOnly = s.filter(\.isNumber)
        guard !digitsOnly.isEmpty else { return nil }
        return Double(digitsOnly)
    }

    /// Trouve un montant total dans le texte, en priorisant les libellés les moins
    /// ambigus (« net à payer », « total ttc ») avant un simple « total » qui pourrait
    /// n'être qu'un sous-total HT.
    public static func extractTotal(from text: String) -> Double? {
        let keywords = ["net à payer", "total à payer", "total ttc", "montant total", "total"]
        let lines = text.components(separatedBy: .newlines)
        guard let regex = try? NSRegularExpression(pattern: trailingAmountPattern, options: [.caseInsensitive]) else { return nil }
        for keyword in keywords {
            for line in lines {
                guard line.lowercased().contains(keyword) else { continue }
                let range = NSRange(line.startIndex..<line.endIndex, in: line)
                guard let match = regex.firstMatch(in: line, options: [], range: range),
                      let group = Range(match.range(at: 1), in: line),
                      let amount = parseAmount(String(line[group])) else { continue }
                return amount
            }
        }
        return nil
    }

    /// Un nombre en fin de ligne, avec ses séparateurs éventuels (espace/point/virgule),
    /// suivi optionnellement d'un symbole monétaire.
    private static let trailingAmountPattern = #"([0-9](?:[0-9 .,]{0,15})[0-9])\s*(?:€|eur)?\s*$"#

    /// Heuristique de reconnaissance des lignes de prestations : une ligne se terminant
    /// par un montant devient une ligne de facture, avec une quantité en tête si détectée
    /// (« 2 x… », « 3 unités… »), sinon quantité 1. Les lignes de sous-totaux/TVA sont
    /// écartées pour ne pas dupliquer ce que `extractTotal` doit traiter séparément.
    /// Comme le reste de ce parseur : à confirmer par l'utilisateur, jamais appliqué tel quel.
    public static func extractLineItems(from text: String) -> [InvoiceLine] {
        let excludedKeywords = ["total", "tva", "ttc", "sous-total", "sous total", "net à payer", "acompte", "remise", "escompte"]
        guard let amountRegex = try? NSRegularExpression(pattern: trailingAmountPattern, options: [.caseInsensitive]) else { return [] }
        let qtyPattern = #"^(\d{1,3}(?:[.,]\d+)?)\s*(?:x\b|unités?\b|u\.\s|u\s)"#
        let qtyRegex = try? NSRegularExpression(pattern: qtyPattern, options: [.caseInsensitive])

        var result: [InvoiceLine] = []
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.count >= 4 else { continue }
            let lower = line.lowercased()
            guard !excludedKeywords.contains(where: { lower.contains($0) }) else { continue }

            let fullRange = NSRange(line.startIndex..<line.endIndex, in: line)
            guard let match = amountRegex.firstMatch(in: line, options: [], range: fullRange),
                  let amountRange = Range(match.range(at: 1), in: line),
                  let amount = parseAmount(String(line[amountRange])), amount > 0 else { continue }

            var description = String(line[line.startIndex..<amountRange.lowerBound]).trimmingCharacters(in: .whitespaces)
            guard description.count >= 2 else { continue }

            var quantity = 1.0
            if let qtyRegex,
               let qtyMatch = qtyRegex.firstMatch(in: description, range: NSRange(description.startIndex..<description.endIndex, in: description)),
               let qtyValueRange = Range(qtyMatch.range(at: 1), in: description),
               let fullQtyRange = Range(qtyMatch.range(at: 0), in: description),
               let qty = parseAmount(String(description[qtyValueRange])), qty > 0 {
                quantity = qty
                description = String(description[fullQtyRange.upperBound...]).trimmingCharacters(in: .whitespaces)
            }
            guard !description.isEmpty else { continue }
            let unitPrice = ((amount / quantity) * 100).rounded() / 100
            result.append(InvoiceLine(name: description, quantity: quantity, unitPrice: unitPrice, vatRate: 20))
        }
        return result
    }

    /// Compare le total extrait à la somme des lignes extraites, HT *et* TTC (le document
    /// scanné peut afficher l'un ou l'autre sans que ce soit toujours explicite) : `true`
    /// si l'un des deux correspond à une tolérance près, `false` sinon. `nil` s'il n'y a
    /// rien à contrôler (aucun total trouvé dans le texte).
    public static func totalMatches(lines: [InvoiceLine], extractedTotal: Double?) -> Bool? {
        guard let extractedTotal else { return nil }
        let sumHT = lines.reduce(0.0) { $0 + $1.lineTotal }.rounded(toPlaces: 2)
        let sumTTC = lines.reduce(0.0) { $0 + $1.lineTotal * (1 + $1.vatRate / 100) }.rounded(toPlaces: 2)
        let tolerance = max(0.02, extractedTotal * 0.01)
        return abs(sumHT - extractedTotal) <= tolerance || abs(sumTTC - extractedTotal) <= tolerance
    }
}
