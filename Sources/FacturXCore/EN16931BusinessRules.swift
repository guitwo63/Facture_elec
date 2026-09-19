import Foundation

public enum BusinessRuleSeverity: String, Codable {
    case error
    case warning

    public var label: String { self == .error ? "Erreur" : "Avertissement" }
}

public struct BusinessRuleResult: Identifiable, Hashable {
    public let id: String
    public let ruleId: String
    public let severity: BusinessRuleSeverity
    public let message: String

    public init(ruleId: String, severity: BusinessRuleSeverity, message: String) {
        self.id = ruleId
        self.ruleId = ruleId
        self.severity = severity
        self.message = message
    }
}

/// Distingue une facture qu'on émet (`issued`, le cas par défaut — inchangé pour tous les
/// appels existants) d'une facture reçue d'un tiers (`received`, factures d'achat) : les
/// contrôles purement liés à l'émission (mentions légales françaises qu'on est censé avoir
/// rédigées nous-mêmes, recommandation de profil qu'on n'a pas choisi) n'ont pas de sens sur
/// un document que quelqu'un d'autre a produit — il n'y a rien à corriger de notre côté.
/// Tout le reste (arithmétique, structure, qualité des données des deux parties) reste
/// vérifié dans les deux cas : ce sont des indicateurs de qualité de données génériques,
/// pas des obligations propres à l'émetteur.
public enum EN16931RuleContext {
    case issued
    case received
}

public enum EN16931BusinessRules {

    public static func evaluate(invoice: Invoice, context: EN16931RuleContext = .issued) -> [BusinessRuleResult] {
        var results: [BusinessRuleResult] = []

        let sellerName = invoice.seller.name.trimmingCharacters(in: .whitespaces)
        let buyerName = invoice.buyer.name.trimmingCharacters(in: .whitespaces)
        let invoiceNumber = invoice.number.trimmingCharacters(in: .whitespaces)
        let currency = invoice.currency.trimmingCharacters(in: .whitespaces)

        if invoiceNumber.isEmpty {
            results.append(BusinessRuleResult(ruleId: "BR-1", severity: .error,
                message: "BR-1 : Le numéro de facture (BT-1) est obligatoire."))
        }

        if invoice.issueDate > Date() + 86400 {
            results.append(BusinessRuleResult(ruleId: "BR-2", severity: .warning,
                message: "BR-2 : La date d'émission (BT-2) est postérieure à aujourd'hui."))
        }

        if invoice.dueDate < invoice.issueDate {
            results.append(BusinessRuleResult(ruleId: "BR-9", severity: .warning,
                message: "BR-9 : La date d'échéance (BT-9) est antérieure à la date d'émission (BT-2)."))
        }

        let knownCurrencies = Set(NormRefs.currencies.map { $0.code })
        if currency.isEmpty {
            results.append(BusinessRuleResult(ruleId: "BR-5", severity: .error,
                message: "BR-5 : La devise (BT-5) est obligatoire (code ISO 4217 à 3 lettres)."))
        } else if currency.count != 3 {
            results.append(BusinessRuleResult(ruleId: "BR-5", severity: .error,
                message: "BR-5 : La devise (BT-5) doit être un code ISO 4217 à 3 lettres."))
        } else if !knownCurrencies.contains(currency) {
            results.append(BusinessRuleResult(ruleId: "BR-5", severity: .warning,
                message: "BR-5 : La devise (BT-5) « \(currency) » n'est pas dans la liste de référence ISO 4217 ; vérifiez le code."))
        }

        if sellerName.isEmpty {
            results.append(BusinessRuleResult(ruleId: "BR-6", severity: .error,
                message: "BR-6 : Le nom de l'émetteur (BT-27) est obligatoire."))
        }
        if invoice.seller.country.trimmingCharacters(in: .whitespaces).isEmpty {
            results.append(BusinessRuleResult(ruleId: "BR-7", severity: .error,
                message: "BR-7 : Le pays de l'émetteur (BT-40) est obligatoire (code ISO à 2 lettres)."))
        }
        let sellerEndpoint = (invoice.seller.endpointID ?? "").trimmingCharacters(in: .whitespaces)
        let sellerSiren = (invoice.seller.siren ?? "").trimmingCharacters(in: .whitespaces)
        if sellerEndpoint.isEmpty && sellerSiren.isEmpty {
            results.append(BusinessRuleResult(ruleId: "BR-49", severity: .error,
                message: "BR-49 : L'émetteur doit avoir un SIREN ou un identifiant électronique (BT-49)."))
        }
        if !sellerSiren.isEmpty && !SireneValidator.isValidSiren(invoice.seller.siren) {
            results.append(BusinessRuleResult(ruleId: "BR-49", severity: .warning,
                message: "BR-49 : Le SIREN de l'émetteur (BT-29) doit comporter 9 chiffres et être valide (clé Luhn)."))
        }
        if let sellerSiret = invoice.seller.siret?.trimmingCharacters(in: .whitespaces), !sellerSiret.isEmpty,
           !SireneValidator.isValidSiret(invoice.seller.siret) {
            results.append(BusinessRuleResult(ruleId: "BR-49", severity: .warning,
                message: "BR-49 : Le SIRET de l'émetteur doit comporter 14 chiffres et être valide (clé Luhn)."))
        }
        let sellerVAT = (invoice.seller.vatNumber ?? "").trimmingCharacters(in: .whitespaces)
        let hasStandardRatedLine = invoice.lines.contains { $0.vatRate > 0 }
        if hasStandardRatedLine && sellerVAT.isEmpty {
            results.append(BusinessRuleResult(ruleId: "BR-S-02", severity: .error,
                message: "BR-S-02 : Une ligne à TVA standard (BT-151 = S) oblige l'émetteur à avoir un n° TVA (BT-31)."))
        }

        if buyerName.isEmpty {
            results.append(BusinessRuleResult(ruleId: "BR-25", severity: .error,
                message: "BR-25 : Le nom du destinataire (BT-44) est obligatoire."))
        }
        if invoice.buyer.country.trimmingCharacters(in: .whitespaces).isEmpty {
            results.append(BusinessRuleResult(ruleId: "BR-26", severity: .error,
                message: "BR-26 : Le pays du destinataire (BT-55) est obligatoire (code ISO à 2 lettres)."))
        }
        let buyerEndpoint = (invoice.buyer.endpointID ?? "").trimmingCharacters(in: .whitespaces)
        let buyerSiren = (invoice.buyer.siren ?? "").trimmingCharacters(in: .whitespaces)
        if buyerEndpoint.isEmpty && buyerSiren.isEmpty {
            results.append(BusinessRuleResult(ruleId: "BR-46", severity: .error,
                message: "BR-46 : Le destinataire doit avoir un SIREN ou un identifiant électronique (BT-34)."))
        }
        if !buyerSiren.isEmpty && !SireneValidator.isValidSiren(invoice.buyer.siren) {
            results.append(BusinessRuleResult(ruleId: "BR-46", severity: .warning,
                message: "BR-46 : Le SIREN du destinataire (BT-48) doit comporter 9 chiffres et être valide (clé Luhn)."))
        }
        if let buyerSiret = invoice.buyer.siret?.trimmingCharacters(in: .whitespaces), !buyerSiret.isEmpty,
           !SireneValidator.isValidSiret(invoice.buyer.siret) {
            results.append(BusinessRuleResult(ruleId: "BR-46", severity: .warning,
                message: "BR-46 : Le SIRET du destinataire doit comporter 14 chiffres et être valide (clé Luhn)."))
        }

        if invoice.lines.isEmpty {
            results.append(BusinessRuleResult(ruleId: "BR-15", severity: .error,
                message: "BR-15 : La facture doit contenir au moins une ligne (BG-25)."))
        }

        for (idx, line) in invoice.lines.enumerated() {
            let label = "Ligne \(idx + 1)"
            if line.name.trimmingCharacters(in: .whitespaces).isEmpty {
                results.append(BusinessRuleResult(ruleId: "BR-21", severity: .error,
                    message: "BR-21 : \(label) — la désignation (BT-153) est obligatoire."))
            }
            if line.quantity <= 0 {
                results.append(BusinessRuleResult(ruleId: "BR-16", severity: .error,
                    message: "BR-16 : \(label) — la quantité (BT-129) doit être positive."))
            }
            if line.unitPrice < 0 {
                results.append(BusinessRuleResult(ruleId: "BR-17", severity: .error,
                    message: "BR-17 : \(label) — le prix unitaire (BT-146) ne peut pas être négatif."))
            }
            if line.unit.trimmingCharacters(in: .whitespaces).isEmpty {
                results.append(BusinessRuleResult(ruleId: "BR-20", severity: .warning,
                    message: "BR-20 : \(label) — l'unité (BT-130) n'est pas renseignée (code UN/ECE, ex. C62, DAY)."))
            }
            let computed = (line.quantity * line.unitPrice).rounded(toPlaces: 2)
            if (computed - line.lineTotal).rounded(toPlaces: 2) != 0 {
                results.append(BusinessRuleResult(ruleId: "BR-27", severity: .error,
                    message: "BR-27 : \(label) — le total ligne (BT-149) ≠ quantité × prix unitaire."))
            }
        }

        let computedLineTotal = invoice.lines.reduce(0) { $0 + $1.lineTotal }.rounded(toPlaces: 2)
        if (computedLineTotal - invoice.lineTotal).rounded(toPlaces: 2) != 0 {
            results.append(BusinessRuleResult(ruleId: "BR-12", severity: .error,
                message: "BR-12 : Le total HT (BT-106) ≠ somme des totaux ligne."))
        }

        let computedVat = invoice.vatBreakdown.reduce(0) { $0 + $1.amount }.rounded(toPlaces: 2)
        if (computedVat - invoice.taxTotal).rounded(toPlaces: 2) != 0 {
            results.append(BusinessRuleResult(ruleId: "BR-53", severity: .error,
                message: "BR-53 : Le total TVA (BT-110) ≠ somme des montants de TVA par taux."))
        }

        let computedGrand = (invoice.lineTotal + invoice.taxTotal).rounded(toPlaces: 2)
        if (computedGrand - invoice.grandTotal).rounded(toPlaces: 2) != 0 {
            results.append(BusinessRuleResult(ruleId: "BR-13", severity: .error,
                message: "BR-13 : Le total TTC (BT-112) ≠ total HT + total TVA."))
        }

        if invoice.type.requiresPrecedingInvoice {
            let ref = (invoice.precedingInvoiceRef ?? "").trimmingCharacters(in: .whitespaces)
            if ref.isEmpty {
                results.append(BusinessRuleResult(ruleId: "BR-FR-CO-05", severity: .error,
                    message: "BR-FR-CO-05 / BT-25 : Ce type de facture doit référencer la facture antérieure (numéro + date)."))
            } else if invoice.precedingInvoiceDate == nil {
                results.append(BusinessRuleResult(ruleId: "BR-FR-CO-05", severity: .error,
                    message: "BR-FR-CO-05 / BT-26 : La date de la facture antérieure référencée est obligatoire pour ce type de facture."))
            }
        }
        if invoice.type.isFinalSettlement, invoice.prepaidAmount <= 0 {
            results.append(BusinessRuleResult(ruleId: "BR-AC-01", severity: .warning,
                message: "BR-AC-01 : Une facture de solde devrait indiquer le montant des acomptes déjà payés (PrepaidAmount)."))
        }

        // Mentions légales françaises : obligatoires sur une facture qu'on émet (BR-FR-05),
        // mais sans objet sur un document reçu — on ne les a pas rédigées, rien à corriger.
        if context == .issued {
            if invoice.legalNotePMT.trimmingCharacters(in: .whitespaces).isEmpty {
                results.append(BusinessRuleResult(ruleId: "BR-FR-05", severity: .warning,
                    message: "BR-FR-05 : La mention sur les frais de recouvrement (SubjectCode PMT) est obligatoire en France."))
            }
            if invoice.legalNotePMD.trimmingCharacters(in: .whitespaces).isEmpty {
                results.append(BusinessRuleResult(ruleId: "BR-FR-05", severity: .warning,
                    message: "BR-FR-05 : La mention sur les pénalités de retard (SubjectCode PMD) est obligatoire en France."))
            }
            if invoice.legalNoteAAB.trimmingCharacters(in: .whitespaces).isEmpty {
                results.append(BusinessRuleResult(ruleId: "BR-FR-05", severity: .warning,
                    message: "BR-FR-05 : La mention sur l'escompte (SubjectCode AAB) est obligatoire en France."))
            }
        }

        if let iban = invoice.paymentIBAN, !iban.trimmingCharacters(in: .whitespaces).isEmpty {
            if !IBANValidator.isValid(iban) {
                let cleaned = IBANValidator.normalize(iban)
                if cleaned.count < 15 || cleaned.count > 34 {
                    results.append(BusinessRuleResult(ruleId: "BR-50", severity: .warning,
                        message: "BR-50 : L'IBAN (BT-91) semble avoir une longueur inhabituelle (15 à 34 caractères)."))
                } else if cleaned.uppercased() != cleaned {
                    results.append(BusinessRuleResult(ruleId: "BR-50", severity: .warning,
                        message: "BR-50 : L'IBAN (BT-91) doit être en majuscules."))
                } else {
                    results.append(BusinessRuleResult(ruleId: "BR-50", severity: .error,
                        message: "BR-50 : L'IBAN (BT-91) est invalide (clé de contrôle mod 97 incorrecte ou longueur pays inattendue)."))
                }
            }
        }

        if invoice.lines.contains(where: { $0.vatRate < 0 }) {
            results.append(BusinessRuleResult(ruleId: "BR-FR-06", severity: .warning,
                message: "BR-FR-06 : Un taux de TVA négatif est inhabituel ; vérifiez la catégorie de TVA (BT-151)."))
        }

        for (idx, line) in invoice.lines.enumerated() {
            let label = "Ligne \(idx + 1)"
            if line.vatRate == 0 && line.vatCategory == .zeroRated {
                results.append(BusinessRuleResult(ruleId: "BR-CO-16", severity: .warning,
                    message: "BR-CO-16 : \(label) — taux nul (BT-151=Z) : vérifiez qu'il s'agit bien d'une exonération et non d'un oubli de taux."))
            }
            // Toute catégorie autre que "Standard" (Z, AE, K, G, E, O) implique un taux à 0 — sinon
            // le sous-total de TVA calculé pour ce groupe (BG-23) est non nul alors que sa catégorie
            // l'exige à zéro, rejeté par le validateur EN16931 officiel (confirmé en conditions
            // réelles via SUPER PDP : BR-Z-05/BR-Z-09 pour la catégorie Z). Le suffixe -RATE est
            // interne (pas un vrai numéro de règle officiel) pour les autres catégories, dont
            // l'identifiant exact de cette règle précise n'est pas vérifié ici.
            if line.vatCategory != .standard && line.vatRate != 0 {
                let ruleId = line.vatCategory == .zeroRated ? "BR-Z-05" : "BR-\(line.vatCategory.rawValue)-RATE"
                results.append(BusinessRuleResult(ruleId: ruleId, severity: .error,
                    message: "\(ruleId) : \(label) — catégorie « \(line.vatCategory.label) » (BT-151=\(line.vatCategory.rawValue)) incompatible avec un taux non nul (BT-152=\(line.vatRate)) ; changez la catégorie ou repassez le taux à 0."))
            }
            if line.vatCategory.requiresExemptionReason,
               (line.vatExemptionReason ?? "").trimmingCharacters(in: .whitespaces).isEmpty {
                results.append(BusinessRuleResult(ruleId: "BR-\(line.vatCategory.rawValue)-05", severity: .error,
                    message: "BR-\(line.vatCategory.rawValue)-05 : \(label) — catégorie de TVA « \(line.vatCategory.label) » (BT-151=\(line.vatCategory.rawValue)) : un motif d'exonération (BT-120) est obligatoire."))
            }
        }

        // Recommandation de profil : pertinente pour un choix qu'on fait nous-mêmes en
        // émettant, pas pour un profil déjà choisi par le fournisseur sur un document reçu.
        if context == .issued {
            switch invoice.profile {
            case .minimum, .basicWL, .basic:
                results.append(BusinessRuleResult(ruleId: "BR-PROFIL", severity: .warning,
                    message: "Le profil \(invoice.profile.rawValue) est limité ; EN 16931 est recommandé pour la réforme française."))
            case .en16931, .extended:
                break
            }
        }

        return results
    }
}
