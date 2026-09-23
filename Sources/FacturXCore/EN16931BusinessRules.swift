import Foundation

public enum BusinessRuleSeverity: String, Codable {
    case error
    case warning

    public var label: String { self == .error ? "Erreur" : "Avertissement" }
}

public struct BusinessRuleResult: Identifiable, Hashable {
    /// Identité pour `ForEach`, propre à chaque résultat. Le `ruleId` seul ne suffit pas :
    /// une même règle sort souvent plusieurs fois (les trois mentions BR-FR-05, une fois par
    /// ligne fautive, émetteur et destinataire…), et des identités en double font afficher
    /// à SwiftUI des lignes dupliquées ou manquantes. Dérivée du contenu plutôt que d'un
    /// UUID, elle reste stable d'une validation à l'autre. Elle suppose que les résultats
    /// d'une même règle ont des messages différents : une règle par ligne cite la ligne.
    public let id: String
    /// Partagé par plusieurs résultats : c'est lui, pas `id`, que le surlignage des champs
    /// en erreur utilise.
    public let ruleId: String
    public let severity: BusinessRuleSeverity
    public let message: String

    public init(ruleId: String, severity: BusinessRuleSeverity, message: String) {
        self.id = "\(ruleId)|\(severity.rawValue)|\(message)"
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

/// Identifiants de règle : ceux des Schematron officiels fournis avec le paquet `factur-x`
/// (EN 16931 : `facturx-en16931/Factur-X_1.09_EN16931.xsl`, dont les numéros à un chiffre
/// s'écrivent BR-01…BR-09 ; France CTC : `cii-schematron-fr-ctc/BR-FR-Flux2-Schematron-CII.xslt`),
/// pour qu'un contrôle local se rapproche directement du rejet qu'émettrait la PDP. Un contrôle
/// sans règle officielle correspondante porte un identifiant interne « BT-<n>-<MOTIF> »
/// (n = terme métier contrôlé, ex. BT-157-GTIN) : jamais un BR-xx, qui désignerait une autre
/// règle officielle.
public enum EN16931BusinessRules {

    /// Préfixe des règles EN 16931 propres à une catégorie de TVA : le code de la catégorie,
    /// sauf pour K (livraison intracommunautaire), dont les règles sont les BR-IC-xx.
    private static func rulePrefix(_ category: VATCategory) -> String {
        category == .intraCommunity ? "IC" : category.rawValue
    }

    /// BR-FR-16 : liste fermée `custom:is-valid-vat-rate` du Schematron France CTC, qui compare
    /// des chaînes (« 5.5 » et « 5.50 » passent, « 5.500 » non).
    private static let brFR16Rates: Set<String> = [
        "0", "0.0", "0.00", "10", "10.0", "10.00", "13", "13.0", "13.00", "20", "20.0", "20.00",
        "8.5", "8.50", "19.6", "19.60", "2.1", "2.10", "5.5", "5.50", "7", "7.0", "7.00",
        "20.6", "20.60", "1.05", "0.9", "0.90", "1.75", "9.2", "9.20", "9.6", "9.60",
    ]

    public static func evaluate(invoice: Invoice, context: EN16931RuleContext = .issued) -> [BusinessRuleResult] {
        var results: [BusinessRuleResult] = []

        let sellerName = invoice.seller.name.trimmingCharacters(in: .whitespaces)
        let buyerName = invoice.buyer.name.trimmingCharacters(in: .whitespaces)
        let invoiceNumber = invoice.number.trimmingCharacters(in: .whitespaces)
        let currency = invoice.currency.trimmingCharacters(in: .whitespaces)

        if invoiceNumber.isEmpty {
            results.append(BusinessRuleResult(ruleId: "BR-02", severity: .error,
                message: "BR-02 : Le numéro de facture (BT-1) est obligatoire."))
        }

        // Contrôle interne : aucune règle officielle n'interdit une date d'émission future.
        if invoice.issueDate > Date() + 86400 {
            results.append(BusinessRuleResult(ruleId: "BT-2-FUTURE", severity: .warning,
                message: "BT-2 : La date d'émission est postérieure à aujourd'hui."))
        }

        // BR-FR-CO-07 (Schematron France CTC, bloquant à la PDP) : l'échéance ne peut pas
        // précéder la date de facture, sauf sur un acompte (386) ou en cadre « déjà payée »
        // (B2/S2/M2), où elle est la date du paiement. Comparaison au jour près des dates
        // écrites dans le XML, comme le Schematron : une échéance du même jour est admise,
        // même à une heure antérieure.
        if !invoice.type.isDeposit && !invoice.billingMode.isAlreadyPaid {
            let issueDay = CIIXMLGenerator.xmlDate(invoice.issueDate)
            let dueDay = CIIXMLGenerator.xmlDate(invoice.dueDate)
            if dueDay < issueDay {
                results.append(BusinessRuleResult(ruleId: "BR-FR-CO-07", severity: .error,
                    message: "BR-FR-CO-07 : L'échéance (BT-9) du \(frenchDay(dueDay)) est antérieure à la date de facture (BT-2) du \(frenchDay(issueDay)) : la PDP rejetterait la facture. Une échéance antérieure n'est admise que pour une facture d'acompte (386) ou déjà payée (cadre B2, S2 ou M2)."))
            }
        }

        let knownCurrencies = Set(NormRefs.currencies.map { $0.code })
        // Présence : BR-05 ; format et liste ISO 4217 : BR-CL-04 (règle de liste de codes, sans
        // identifiant dans le Schematron Factur-X EN16931, nommée dans les artefacts CEN).
        if currency.isEmpty {
            results.append(BusinessRuleResult(ruleId: "BR-05", severity: .error,
                message: "BR-05 : La devise (BT-5) est obligatoire (code ISO 4217 à 3 lettres)."))
        } else if currency.count != 3 {
            results.append(BusinessRuleResult(ruleId: "BR-CL-04", severity: .error,
                message: "BR-CL-04 : La devise (BT-5) doit être un code ISO 4217 à 3 lettres."))
        } else if !knownCurrencies.contains(currency) {
            results.append(BusinessRuleResult(ruleId: "BR-CL-04", severity: .warning,
                message: "BR-CL-04 : La devise (BT-5) « \(currency) » n'est pas dans la liste de référence ISO 4217 ; vérifiez le code."))
        }

        if sellerName.isEmpty {
            results.append(BusinessRuleResult(ruleId: "BR-06", severity: .error,
                message: "BR-06 : Le nom de l'émetteur (BT-27) est obligatoire."))
        }
        if invoice.seller.country.trimmingCharacters(in: .whitespaces).isEmpty {
            results.append(BusinessRuleResult(ruleId: "BR-09", severity: .error,
                message: "BR-09 : Le pays de l'émetteur (BT-40) est obligatoire (code ISO à 2 lettres)."))
        }
        // Le générateur déduit l'adresse électronique (BT-34) du SIREN quand elle est vide :
        // l'un ou l'autre suffit à satisfaire BR-FR-13 (« Le BT-34 est obligatoire »).
        let sellerEndpoint = (invoice.seller.endpointID ?? "").trimmingCharacters(in: .whitespaces)
        let sellerSiren = (invoice.seller.siren ?? "").trimmingCharacters(in: .whitespaces)
        if sellerEndpoint.isEmpty && sellerSiren.isEmpty {
            results.append(BusinessRuleResult(ruleId: "BR-FR-13", severity: .error,
                message: "BR-FR-13 : L'émetteur doit avoir un SIREN ou un identifiant électronique (BT-34)."))
        }
        if !sellerSiren.isEmpty && !SireneValidator.isValidSiren(invoice.seller.siren) {
            results.append(BusinessRuleResult(ruleId: "BR-FR-10", severity: .warning,
                message: "BR-FR-10 : Le SIREN de l'émetteur (BT-30) doit comporter 9 chiffres et être valide (clé Luhn)."))
        }
        if let sellerSiret = invoice.seller.siret?.trimmingCharacters(in: .whitespaces), !sellerSiret.isEmpty,
           !SireneValidator.isValidSiret(invoice.seller.siret) {
            results.append(BusinessRuleResult(ruleId: "BR-FR-09", severity: .warning,
                message: "BR-FR-09 : Le SIRET de l'émetteur doit comporter 14 chiffres et être valide (clé Luhn)."))
        }
        let sellerVAT = (invoice.seller.vatNumber ?? "").trimmingCharacters(in: .whitespaces)
        let hasStandardRatedLine = invoice.lines.contains { $0.vatRate > 0 }
        if hasStandardRatedLine && sellerVAT.isEmpty {
            results.append(BusinessRuleResult(ruleId: "BR-S-02", severity: .error,
                message: "BR-S-02 : Une ligne à TVA standard (BT-151 = S) oblige l'émetteur à avoir un n° TVA (BT-31)."))
        }
        // Même famille de règle que BR-S-02 ci-dessus (BT-31 obligatoire pour l'émetteur),
        // pour la catégorie Exonérée (BT-151 = E) au lieu de Taux normal — pas détectée
        // localement avant cet ajout, découverte seulement au dépôt via la validation
        // distante SUPER PDP (BR-E-02).
        let hasExemptLine = invoice.lines.contains { $0.vatCategory == .exempt }
        if hasExemptLine && sellerVAT.isEmpty {
            results.append(BusinessRuleResult(ruleId: "BR-E-02", severity: .error,
                message: "BR-E-02 : Une ligne exonérée de TVA (BT-151 = E) oblige l'émetteur à avoir un n° TVA (BT-31)."))
        }
        // Catégorie « Hors champ de TVA » (BT-151 = O) : règles du Schematron EN16931, absentes
        // du Schematron EXTENDED. Une telle facture ne porte aucun n° TVA (BR-O-02) ni aucune
        // autre catégorie (BR-O-11 : une seule ventilation ; BR-O-12 : que des lignes O). Le
        // taux de ligne interdit par BR-O-05, lui, est simplement omis par le générateur.
        if invoice.profile != .extended && invoice.lines.contains(where: { $0.vatCategory == .outOfScope }) {
            let buyerVAT = (invoice.buyer.vatNumber ?? "").trimmingCharacters(in: .whitespaces)
            let presentVATNumbers = [sellerVAT.isEmpty ? nil : "de l'émetteur (BT-31)",
                                     buyerVAT.isEmpty ? nil : "de l'acheteur (BT-48)"].compactMap { $0 }
            if !presentVATNumbers.isEmpty {
                results.append(BusinessRuleResult(ruleId: "BR-O-02", severity: .error,
                    message: "BR-O-02 : Une facture comportant une ligne « Hors champ de TVA » (BT-151 = O) ne porte aucun n° TVA : retirez celui \(presentVATNumbers.joined(separator: " et celui ")) de la facture."))
            }
            let otherLines = invoice.lines.indices.filter { invoice.lines[$0].vatCategory != .outOfScope }
            if !otherLines.isEmpty {
                results.append(BusinessRuleResult(ruleId: "BR-O-12", severity: .error,
                    message: "BR-O-12 : Une facture comportant une ligne « Hors champ de TVA » (BT-151 = O) ne peut pas contenir de ligne d'une autre catégorie (ici ligne(s) \(otherLines.map { String($0 + 1) }.joined(separator: ", "))) : facturez-les séparément."))
            }
        }
        if !VATNumberValidator.hasValidCountryPrefix(invoice.seller.vatNumber) {
            results.append(BusinessRuleResult(ruleId: "BR-CO-09", severity: .error,
                message: "BR-CO-09 : Le n° TVA de l'émetteur (BT-31) doit commencer par un préfixe pays ISO 3166-1 alpha-2 (ex. FR, DE…) — la Grèce peut utiliser « EL »."))
        }

        if buyerName.isEmpty {
            results.append(BusinessRuleResult(ruleId: "BR-07", severity: .error,
                message: "BR-07 : Le nom du destinataire (BT-44) est obligatoire."))
        }
        if invoice.buyer.country.trimmingCharacters(in: .whitespaces).isEmpty {
            results.append(BusinessRuleResult(ruleId: "BR-11", severity: .error,
                message: "BR-11 : Le pays du destinataire (BT-55) est obligatoire (code ISO à 2 lettres)."))
        }
        // Même déduction que pour l'émetteur : à défaut d'adresse, le BT-49 vient du SIREN (BR-FR-12).
        let buyerEndpoint = (invoice.buyer.endpointID ?? "").trimmingCharacters(in: .whitespaces)
        let buyerSiren = (invoice.buyer.siren ?? "").trimmingCharacters(in: .whitespaces)
        if buyerEndpoint.isEmpty && buyerSiren.isEmpty {
            results.append(BusinessRuleResult(ruleId: "BR-FR-12", severity: .error,
                message: "BR-FR-12 : Le destinataire doit avoir un SIREN ou un identifiant électronique (BT-49)."))
        }
        // BR-FR-32 (tout identifiant légal de schéma 0002 : 9 chiffres) plutôt que BR-FR-11,
        // qui ne vaut qu'en présence d'une note BAR = B2B, que l'application n'émet pas.
        if !buyerSiren.isEmpty && !SireneValidator.isValidSiren(invoice.buyer.siren) {
            results.append(BusinessRuleResult(ruleId: "BR-FR-32", severity: .warning,
                message: "BR-FR-32 : Le SIREN du destinataire (BT-47) doit comporter 9 chiffres et être valide (clé Luhn)."))
        }
        if let buyerSiret = invoice.buyer.siret?.trimmingCharacters(in: .whitespaces), !buyerSiret.isEmpty,
           !SireneValidator.isValidSiret(invoice.buyer.siret) {
            results.append(BusinessRuleResult(ruleId: "BR-FR-09", severity: .warning,
                message: "BR-FR-09 : Le SIRET du destinataire doit comporter 14 chiffres et être valide (clé Luhn)."))
        }
        if !VATNumberValidator.hasValidCountryPrefix(invoice.buyer.vatNumber) {
            results.append(BusinessRuleResult(ruleId: "BR-CO-09", severity: .error,
                message: "BR-CO-09 : Le n° TVA du destinataire (BT-48) doit commencer par un préfixe pays ISO 3166-1 alpha-2 (ex. FR, DE…) — la Grèce peut utiliser « EL »."))
        }

        if invoice.lines.isEmpty {
            results.append(BusinessRuleResult(ruleId: "BR-16", severity: .error,
                message: "BR-16 : La facture doit contenir au moins une ligne (BG-25)."))
        }

        for (idx, line) in invoice.lines.enumerated() {
            let label = "Ligne \(idx + 1)"
            if line.name.trimmingCharacters(in: .whitespaces).isEmpty {
                results.append(BusinessRuleResult(ruleId: "BR-25", severity: .error,
                    message: "BR-25 : \(label) — la désignation (BT-153) est obligatoire."))
            }
            // Contrôle interne : EN 16931 admet une quantité nulle ou négative (BR-22 n'exige
            // que sa présence) ; l'application porte le sens d'un avoir par le type 381.
            if line.quantity <= 0 {
                results.append(BusinessRuleResult(ruleId: "BT-129-POSITIVE", severity: .error,
                    message: "BT-129 : \(label) — la quantité doit être positive."))
            }
            if line.unitPrice < 0 {
                results.append(BusinessRuleResult(ruleId: "BR-27", severity: .error,
                    message: "BR-27 : \(label) — le prix unitaire (BT-146) ne peut pas être négatif."))
            }
            if line.unit.trimmingCharacters(in: .whitespaces).isEmpty {
                results.append(BusinessRuleResult(ruleId: "BR-23", severity: .warning,
                    message: "BR-23 : \(label) — l'unité (BT-130) n'est pas renseignée (code UN/ECE, ex. C62, DAY)."))
            }
            // Contrôle interne : EN 16931 décrit ce calcul du montant net de ligne sans en
            // faire une règle BR.
            let computed = (line.quantity * line.unitPrice).rounded(toPlaces: 2)
            if (computed - line.lineTotal).rounded(toPlaces: 2) != 0 {
                results.append(BusinessRuleResult(ruleId: "BT-131-CALCUL", severity: .error,
                    message: "BT-131 : \(label) — le montant net de la ligne ≠ quantité × prix unitaire."))
            }
        }

        let computedLineTotal = invoice.lines.reduce(0) { $0 + $1.lineTotal }.rounded(toPlaces: 2)
        if (computedLineTotal - invoice.lineTotal).rounded(toPlaces: 2) != 0 {
            results.append(BusinessRuleResult(ruleId: "BR-CO-10", severity: .error,
                message: "BR-CO-10 : Le total HT (BT-106) ≠ somme des montants nets de ligne (BT-131)."))
        }

        let computedVat = invoice.vatBreakdown.reduce(0) { $0 + $1.amount }.rounded(toPlaces: 2)
        if (computedVat - invoice.taxTotal).rounded(toPlaces: 2) != 0 {
            results.append(BusinessRuleResult(ruleId: "BR-CO-14", severity: .error,
                message: "BR-CO-14 : Le total TVA (BT-110) ≠ somme des montants de TVA par taux (BT-117)."))
        }

        let computedGrand = (invoice.lineTotal + invoice.taxTotal).rounded(toPlaces: 2)
        if (computedGrand - invoice.grandTotal).rounded(toPlaces: 2) != 0 {
            results.append(BusinessRuleResult(ruleId: "BR-CO-15", severity: .error,
                message: "BR-CO-15 : Le total TTC (BT-112) ≠ total HT (BT-109) + total TVA (BT-110)."))
        }

        if invoice.type.requiresPrecedingInvoice {
            // France CTC : BR-FR-CO-04 pour une facture rectificative (384), BR-FR-CO-05 pour
            // un avoir (381). Aucune règle officielle pour la facture de solde, émise en 380 :
            // l'application y exige la référence de l'acompte (contrôle interne).
            let ruleId: String
            switch invoice.type {
            case .correction: ruleId = "BR-FR-CO-04"
            case .finalSettlement: ruleId = "BT-25-SOLDE"
            default: ruleId = "BR-FR-CO-05"
            }
            let ref = (invoice.precedingInvoiceRef ?? "").trimmingCharacters(in: .whitespaces)
            if ref.isEmpty {
                results.append(BusinessRuleResult(ruleId: ruleId, severity: .error,
                    message: "\(ruleId) / BT-25 : Ce type de facture doit référencer la facture antérieure (numéro + date)."))
            } else if invoice.precedingInvoiceDate == nil {
                results.append(BusinessRuleResult(ruleId: ruleId, severity: .error,
                    message: "\(ruleId) / BT-26 : La date de la facture antérieure référencée est obligatoire pour ce type de facture."))
            }
        }
        // Contrôle interne (aucune règle officielle ne l'exige).
        if invoice.type.isFinalSettlement, invoice.prepaidAmount <= 0 {
            results.append(BusinessRuleResult(ruleId: "BT-113-SOLDE", severity: .warning,
                message: "BT-113 : Une facture de solde devrait indiquer le montant des acomptes déjà payés."))
        }

        // Cadre de facturation (BT-23) : contrôles du Schematron France CTC, bloquants à la
        // PDP — signalés ici pour ne jamais générer un XML qu'elle rejetterait.
        let mode = invoice.billingMode
        if mode.isFinalAfterDeposit && invoice.type.isDeposit {
            results.append(BusinessRuleResult(ruleId: "BR-FR-CO-08", severity: .error,
                message: "BR-FR-CO-08 : Le cadre de facturation \(mode.rawValue) (facture définitive après acompte) est interdit sur une facture d'acompte (BT-3 = 386) ; utilisez \(mode.forDeposit.rawValue)."))
        }
        if mode.isAlreadyPaid {
            if (invoice.prepaidAmount - invoice.grandTotal).rounded(toPlaces: 2) != 0 {
                results.append(BusinessRuleResult(ruleId: "BR-FR-CO-09", severity: .error,
                    message: "BR-FR-CO-09 : Cadre \(mode.rawValue) (facture déjà payée) : le montant déjà payé (BT-113) doit être égal au total TTC (BT-112 = \(String(format: "%.2f", invoice.grandTotal)) \(invoice.currency)) pour un net à payer (BT-115) nul, et l'échéance (BT-9) doit être la date du paiement."))
            } else if context == .issued {
                results.append(BusinessRuleResult(ruleId: "BR-FR-CO-09", severity: .warning,
                    message: "BR-FR-CO-09 : Cadre \(mode.rawValue) (facture déjà payée) : vérifiez que la date d'échéance (BT-9) est bien la date du paiement."))
            }
        }
        // Propre à ce que notre générateur sait produire : sans objet sur un document reçu,
        // que son émetteur a pu construire avec les lignes de regroupement requises.
        if context == .issued && mode.requiresGroupLines {
            let isMultiVendor = mode.rawValue.hasSuffix("8")
            let ruleId = isMultiVendor ? "BR-FR-MV-02" : "BR-FR-BD-02"
            results.append(BusinessRuleResult(ruleId: ruleId, severity: .error,
                message: "\(ruleId) : Le cadre de facturation \(mode.rawValue) (facture \(isMultiVendor ? "multi-vendeurs" : "bidirectionnelle")) exige des lignes de regroupement par vendeur (sous-type GROUP) que l'application ne produit pas ; choisissez un autre cadre."))
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

        // Contrôle interne : BR-50/BR-61 n'exigent que la présence de l'identifiant du compte
        // (BT-84), aucune règle officielle ne vérifie la clé de l'IBAN.
        if let iban = invoice.paymentIBAN, !iban.trimmingCharacters(in: .whitespaces).isEmpty {
            if !IBANValidator.isValid(iban) {
                let cleaned = IBANValidator.normalize(iban)
                if cleaned.count < 15 || cleaned.count > 34 {
                    results.append(BusinessRuleResult(ruleId: "BT-84-IBAN", severity: .warning,
                        message: "BT-84 : L'IBAN semble avoir une longueur inhabituelle (15 à 34 caractères)."))
                } else if cleaned.uppercased() != cleaned {
                    results.append(BusinessRuleResult(ruleId: "BT-84-IBAN", severity: .warning,
                        message: "BT-84 : L'IBAN doit être en majuscules."))
                } else {
                    results.append(BusinessRuleResult(ruleId: "BT-84-IBAN", severity: .error,
                        message: "BT-84 : L'IBAN est invalide (clé de contrôle mod 97 incorrecte ou longueur pays inattendue)."))
                }
            }
        }

        for (idx, line) in invoice.lines.enumerated() {
            let label = "Ligne \(idx + 1)"
            // BR-FR-16 (France CTC, fatal) : on compare au Schematron la chaîne que le générateur
            // écrira en BT-152 (reprise en BT-119). Contrôle propre à l'émission : une facture
            // d'achat étrangère peut porter un autre taux (19 % allemand…), seul un taux négatif
            // y reste signalé.
            let rate = CIIXMLGenerator.xmlRate(line.vatRate)
            if context == .issued && !brFR16Rates.contains(rate) {
                results.append(BusinessRuleResult(ruleId: "BR-FR-16", severity: .error,
                    message: "BR-FR-16 : \(label) — le taux de TVA « \(rate) » (BT-152) ne fait pas partie des taux admis en France (0 ; 0,9 ; 1,05 ; 1,75 ; 2,1 ; 5,5 ; 7 ; 8,5 ; 9,2 ; 9,6 ; 10 ; 13 ; 19,6 ; 20 ; 20,6 %) : la PDP rejetterait la facture."))
            } else if context == .received && line.vatRate < 0 {
                results.append(BusinessRuleResult(ruleId: "BR-FR-16", severity: .warning,
                    message: "BR-FR-16 : \(label) — un taux de TVA négatif (BT-152) ne fait pas partie des taux admis en France ; vérifiez la catégorie de TVA (BT-151)."))
            }
            // Contrôle interne : simple rappel, un taux nul en catégorie Z est conforme, mais rare
            // en France, où une ligne à 0 % est le plus souvent exonérée (E, motif obligatoire).
            if line.vatRate == 0 && line.vatCategory == .zeroRated {
                results.append(BusinessRuleResult(ruleId: "BT-152-ZERO", severity: .warning,
                    message: "BT-152 : \(label) — taux nul en catégorie Z « Taux zéro » (BT-151), rare en France. Opération exonérée : choisissez la catégorie E « Exonérée » et indiquez son motif (BT-120). Opération taxable : vérifiez que le taux n'a pas été oublié."))
            }
            // Toute catégorie autre que "Standard" (Z, AE, K, G, E, O) implique un taux à 0 — sinon
            // le sous-total de TVA calculé pour ce groupe (BG-23) est non nul alors que sa catégorie
            // l'exige à zéro, rejeté par le validateur EN16931 officiel (confirmé en conditions
            // réelles via SUPER PDP : BR-Z-05/BR-Z-09 pour la catégorie Z). Règle BR-<catégorie>-05
            // du Schematron : BR-Z-05, BR-E-05, BR-AE-05, BR-IC-05 (K), BR-G-05, BR-O-05.
            if line.vatCategory != .standard && line.vatRate != 0 {
                let ruleId = "BR-\(rulePrefix(line.vatCategory))-05"
                results.append(BusinessRuleResult(ruleId: ruleId, severity: .error,
                    message: "\(ruleId) : \(label) — catégorie « \(line.vatCategory.label) » (BT-151=\(line.vatCategory.rawValue)) incompatible avec un taux non nul (BT-152=\(line.vatRate)) ; changez la catégorie ou repassez le taux à 0."))
            }
            // Motif d'exonération : BR-E-10, BR-AE-10, BR-IC-10 (K), BR-G-10, BR-O-10.
            if line.vatCategory.requiresExemptionReason,
               (line.vatExemptionReason ?? "").trimmingCharacters(in: .whitespaces).isEmpty {
                let ruleId = "BR-\(rulePrefix(line.vatCategory))-10"
                results.append(BusinessRuleResult(ruleId: ruleId, severity: .error,
                    message: "\(ruleId) : \(label) — catégorie de TVA « \(line.vatCategory.label) » (BT-151=\(line.vatCategory.rawValue)) : un motif d'exonération (BT-120) est obligatoire."))
            }
            // Contrôle interne (aucun Schematron officiel ne vérifie la clé) : le BT-157 est
            // émis avec le schéma 0160 (GTIN), une référence interne y serait mal qualifiée —
            // cas probable des valeurs saisies avant que le champ ne soit libellé « GTIN ».
            if let gtin = line.optionalFields.lazy
                .filter({ $0.tagName == "ram:GlobalID" })
                .map({ $0.value.trimmingCharacters(in: .whitespaces) })
                .first(where: { !$0.isEmpty }),
               !GTINValidator.isValid(gtin) {
                results.append(BusinessRuleResult(ruleId: "BT-157-GTIN", severity: .warning,
                    message: "BT-157 : \(label) — « \(gtin) » n'est pas un code GTIN/EAN valide (8, 12, 13 ou 14 chiffres avec clé de contrôle), alors qu'il est émis comme tel (schéma 0160) ; pour une référence interne, utilisez le BT-155 (Réf. article vendeur)."))
            }
        }

        // Profil (BT-24) : le générateur produit la structure EN 16931, que le XSD des profils
        // plus restreints rejette (voir `FacturXProfile`) — bloquant sur une facture qu'on émet.
        // Sans objet sur un document reçu : son émetteur a choisi le profil et produit le XML.
        if context == .issued, let rejection = xsdRejection(of: invoice.profile) {
            results.append(BusinessRuleResult(ruleId: "BR-PROFIL", severity: .error,
                message: "BR-PROFIL : Le profil \(invoice.profile.rawValue) (BT-24) n'est plus proposé à l'émission : l'application produit un XML de structure EN 16931, que le XSD du profil \(invoice.profile.rawValue) \(rejection). Repassez la facture en EN 16931 (ou EXTENDED)."))
        }

        results += deliveryRules(invoice)
        return results
    }

    /// Ce que le XSD du profil rejette dans le XML de `CIIXMLGenerator` (mesure du
    /// 2026-09-23), `nil` pour les profils où ce XML est conforme (`FacturXProfile.isIssuable`).
    private static func xsdRejection(of profile: FacturXProfile) -> String? {
        switch profile {
        case .minimum:
            return "le rejette toujours : ce profil ne comporte ni lignes, ni mentions légales, ni adresses électroniques (BT-34/BT-49), pourtant exigées en France"
        case .basicWL:
            return "le rejette toujours : ce profil ne comporte pas de lignes de facture"
        case .basic:
            return "le rejette dès qu'il contient notamment un contact, un IBAN (moyen de paiement « SEPA »), un BIC ou une description de ligne"
        case .en16931, .extended:
            return nil
        }
    }

    /// "20260923" (date du XML) → "23/09/2026", pour la citer telle quelle dans un message.
    private static func frenchDay(_ xmlDate: String) -> String {
        guard xmlDate.count == 8 else { return xmlDate }
        let c = Array(xmlDate)
        return String(c[6...7]) + "/" + String(c[4...5]) + "/" + String(c[0...3])
    }

    /// Pays de livraison (BT-80) et livraison intracommunautaire (catégorie K : règles BR-IC-*
    /// du Schematron EN16931, présentes aussi dans celui d'EXTENDED). Le générateur respecte
    /// de lui-même BR-IC-12 (BT-80 obligatoire), en émettant le pays de l'acheteur à défaut de
    /// pays de livraison saisi (`Invoice.effectiveDeliveryCountry`), et BR-IC-11 (date de
    /// livraison ou période), par la date de livraison (BT-72) qu'il émet toujours.
    private static func deliveryRules(_ invoice: Invoice) -> [BusinessRuleResult] {
        var results: [BusinessRuleResult] = []
        let entered = (invoice.deliveryCountry ?? "").trimmingCharacters(in: .whitespaces).uppercased()
        if !entered.isEmpty && !deliveryCountryCodes.contains(entered) {
            results.append(BusinessRuleResult(ruleId: "BR-CL-14", severity: .error,
                message: "BR-CL-14 : Le pays de livraison (BT-80) « \(entered) » n'est pas un code pays ISO 3166-1 à 2 lettres (ex. DE ; GR pour la Grèce et non EL, GB pour le Royaume-Uni et non UK)."))
        }

        guard invoice.lines.contains(where: { $0.vatCategory == .intraCommunity }) else { return results }

        // Le représentant fiscal du vendeur (BT-63), que BR-IC-02 admet à la place du BT-31,
        // n'est pas géré par l'application : le n° TVA de l'émetteur est donc exigé.
        let sellerVAT = (invoice.seller.vatNumber ?? "").trimmingCharacters(in: .whitespaces)
        let buyerVAT = (invoice.buyer.vatNumber ?? "").trimmingCharacters(in: .whitespaces)
        if sellerVAT.isEmpty || buyerVAT.isEmpty {
            let missing = sellerVAT.isEmpty && buyerVAT.isEmpty ? "les deux"
                : sellerVAT.isEmpty ? "celui de l'émetteur" : "celui de l'acheteur"
            results.append(BusinessRuleResult(ruleId: "BR-IC-02", severity: .error,
                message: "BR-IC-02 : Une livraison intracommunautaire (BT-151 = K) exige le n° de TVA intracommunautaire de l'émetteur (BT-31) et celui de l'acheteur (BT-48) ; il manque \(missing)."))
        }

        // Contrôle interne : un BT-80 conforme au Schematron peut rester incohérent avec la
        // catégorie K — c'est le cas du repli sur le pays d'un acheteur établi en France.
        if let country = invoice.effectiveDeliveryCountry, deliveryCountryCodes.contains(country) {
            let shown = invoice.deliveryCountry == nil ? "\(country) (pays de l'acheteur, émis faute de pays de livraison saisi)" : country
            let sellerCountry = invoice.seller.country.trimmingCharacters(in: .whitespaces).uppercased()
            if country == sellerCountry {
                results.append(BusinessRuleResult(ruleId: "BT-80-UE", severity: .warning,
                    message: "BT-80 : Livraison intracommunautaire (BT-151 = K) vers \(shown), le pays de l'émetteur, alors qu'elle suppose une expédition vers un autre État membre. Renseignez le pays de livraison (champ optionnel BT-80) s'il diffère de celui de l'acheteur, ou revoyez la catégorie de TVA."))
            } else if !intraCommunityDestinations.contains(country) {
                results.append(BusinessRuleResult(ruleId: "BT-80-UE", severity: .warning,
                    message: "BT-80 : Livraison intracommunautaire (BT-151 = K) vers \(shown), hors de l'Union européenne : une livraison hors UE relève de l'exportation (catégorie G). Vérifiez le pays de livraison (champ optionnel BT-80) ou la catégorie de TVA."))
            }
        }
        return results
    }

    /// Codes pays admis par le Schematron (codedb Factur-X, BR-CL-14) : ISO 3166-1, plus 1A
    /// (Kosovo) et XI (Irlande du Nord).
    private static let deliveryCountryCodes = VATNumberValidator.isoCountryCodes.union(["1A", "XI"])

    /// Destinations d'une livraison intracommunautaire : les 27 États membres (GR pour la
    /// Grèce) et l'Irlande du Nord (XI), qui reste soumise aux règles de l'UE pour les biens.
    private static let intraCommunityDestinations: Set<String> = [
        "AT", "BE", "BG", "CY", "CZ", "DE", "DK", "EE", "ES", "FI", "FR", "GR", "HR", "HU",
        "IE", "IT", "LT", "LU", "LV", "MT", "NL", "PL", "PT", "RO", "SE", "SI", "SK", "XI",
    ]
}
