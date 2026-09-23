import Foundation

// Libellés de TVA des PDF lisibles de facture et de commande (`InvoicePDFRenderer`,
// `OrderPDFRenderer`). Hors taux normal (S), le code de catégorie UNTDID 5305, celui du
// sélecteur de l'éditeur (« E — Exonérée »), suit le taux dans la colonne « TVA% » des lignes
// et dans le libellé du sous-total. Avec le taux seul, une ligne exonérée et une livraison
// intracommunautaire affichaient toutes deux « 0 » sans dire à quel sous-total elles allaient.
// L'écran de l'éditeur garde `VATBreakdownEntry.label`, sans code.

extension VATCategory {
    /// « (E) », « (AE) »… ; nil en S, qui n'est pas nommée non plus dans `VATBreakdownEntry.label`.
    var pdfCodeSuffix: String? {
        self == .standard ? nil : "(\(rawValue))"
    }
}

extension InvoiceLine {
    /// Cellule « TVA% » du tableau des lignes : « 20 », « 5.5 », « 0 (E) ». Le taux est sans
    /// décimale superflue : formaté sans décimale, il donnait « 6 » pour 5,5 %, alors que le XML
    /// porte 5.50.
    var pdfVATRate: String {
        [String(format: "%g", vatRate), vatCategory.pdfCodeSuffix].compactMap { $0 }.joined(separator: " ")
    }
}

extension VATBreakdownEntry {
    /// Libellé du sous-total dans le bloc des totaux : « TVA 20% », « TVA 0% — Exonérée (E) ».
    var pdfLabel: String {
        [label, category.pdfCodeSuffix].compactMap { $0 }.joined(separator: " ")
    }

    /// Mention d'exonération du pied de page, au format des mentions légales :
    /// « TVA 0% — Exonérée (E) : Exonération de TVA, article 261 du CGI ». Une facture doit citer
    /// le texte qui fonde l'exonération, ou porter « Autoliquidation » (CGI, annexe II,
    /// art. 242 nonies A), et seul le XML portait ce motif (BT-120). C'est celui du sous-total,
    /// donc celui du XML. nil pour une catégorie sans motif (S, Z : le motif resté sur une ligne
    /// repassée de E à Z, champ masqué, ne s'imprime pas) ou quand le motif n'est pas saisi.
    var pdfExemptionMention: String? {
        guard category.requiresExemptionReason,
              let reason = exemptionReason?.trimmingCharacters(in: .whitespacesAndNewlines), !reason.isEmpty
        else { return nil }
        return "\(pdfLabel) : \(reason)"
    }
}
