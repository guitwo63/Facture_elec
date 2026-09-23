import Foundation

public struct FacturXValidationResult {
    public let isValid: Bool
    public let errors: [String]
    public let warnings: [String]
    public let businessRules: [BusinessRuleResult]

    public init(isValid: Bool, errors: [String] = [], warnings: [String] = [], businessRules: [BusinessRuleResult] = []) {
        self.isValid = isValid
        self.errors = errors
        self.warnings = warnings
        self.businessRules = businessRules
    }

    /// Nombre total d'erreurs bloquantes, `errors` et `businessRules` confondus — `isValid`
    /// tient compte des deux (`errors.isEmpty && !hasRuleErrors`), donc tout message qui
    /// annonce un décompte d'erreurs doit faire de même sous peine d'afficher "0 erreur(s)"
    /// alors que la validation a bien échoué (le cas si seul `businessRules` en contient).
    public var totalErrorCount: Int {
        errors.count + businessRules.filter { $0.severity == .error }.count
    }
}

public struct FacturXValidator {
    public init() {}

    public func validate(invoice: Invoice) -> FacturXValidationResult {
        let rules = EN16931BusinessRules.evaluate(invoice: invoice)
        var errors: [String] = []
        var warnings: [String] = []

        if invoice.number.trimmingCharacters(in: .whitespaces).isEmpty {
            errors.append("Le numéro de facture est obligatoire.")
        }

        if invoice.seller.name.trimmingCharacters(in: .whitespaces).isEmpty {
            errors.append("Le nom de l'émetteur (vendeur) est obligatoire.")
        }
        if invoice.seller.country.trimmingCharacters(in: .whitespaces).isEmpty {
            errors.append("Le pays de l'émetteur est obligatoire (code ISO à 2 lettres, ex. FR).")
        }
        let sellerHasEndpoint = (invoice.seller.endpointID?.trimmingCharacters(in: .whitespaces).isEmpty ?? true) == false
        let sellerHasSiren = (invoice.seller.siren?.trimmingCharacters(in: .whitespaces).isEmpty ?? true) == false
        if !sellerHasEndpoint && !sellerHasSiren {
            errors.append("L'émetteur doit avoir un SIREN ou un identifiant électronique (BT-49).")
        }

        if invoice.buyer.name.trimmingCharacters(in: .whitespaces).isEmpty {
            errors.append("Le nom du destinataire (acheteur) est obligatoire.")
        }
        if invoice.buyer.country.trimmingCharacters(in: .whitespaces).isEmpty {
            errors.append("Le pays du destinataire est obligatoire (code ISO à 2 lettres, ex. FR).")
        }
        let buyerHasEndpoint = (invoice.buyer.endpointID?.trimmingCharacters(in: .whitespaces).isEmpty ?? true) == false
        let buyerHasSiren = (invoice.buyer.siren?.trimmingCharacters(in: .whitespaces).isEmpty ?? true) == false
        if !buyerHasEndpoint && !buyerHasSiren {
            errors.append("Le destinataire doit avoir un SIREN ou un identifiant électronique (BT-34).")
        }

        if invoice.lines.isEmpty {
            errors.append("La facture doit contenir au moins une ligne.")
        } else {
            for (idx, line) in invoice.lines.enumerated() {
                if line.name.trimmingCharacters(in: .whitespaces).isEmpty {
                    errors.append("Ligne \(idx + 1) : la désignation est obligatoire.")
                }
                if line.quantity <= 0 {
                    errors.append("Ligne \(idx + 1) : la quantité doit être positive.")
                }
                if line.unitPrice < 0 {
                    errors.append("Ligne \(idx + 1) : le prix unitaire ne peut pas être négatif.")
                }
                if line.unit.trimmingCharacters(in: .whitespaces).isEmpty {
                    warnings.append("Ligne \(idx + 1) : unité non renseignée (utilisez un code UN/ECE, ex. C62, DAY).")
                }
            }
        }

        if invoice.currency.trimmingCharacters(in: .whitespaces).isEmpty {
            errors.append("La devise est obligatoire (ex. EUR).")
        } else if invoice.currency.count != 3 {
            errors.append("La devise doit être un code ISO 4217 à 3 lettres (ex. EUR).")
        }

        if invoice.seller.endpointID == nil || (invoice.seller.endpointID ?? "").trimmingCharacters(in: .whitespaces).isEmpty {
            if (invoice.seller.siren ?? "").trimmingCharacters(in: .whitespaces).isEmpty {
                warnings.append("L'identifiant électronique de l'émetteur (BT-49) sera déduit du SIREN si renseigné.")
            }
        }
        if invoice.buyer.endpointID == nil || (invoice.buyer.endpointID ?? "").trimmingCharacters(in: .whitespaces).isEmpty {
            if (invoice.buyer.siren ?? "").trimmingCharacters(in: .whitespaces).isEmpty {
                warnings.append("L'identifiant électronique du destinataire (BT-34) sera déduit du SIREN si renseigné.")
            }
        }

        if invoice.legalNotePMT.trimmingCharacters(in: .whitespaces).isEmpty {
            warnings.append("La mention sur les frais de recouvrement (note avec SubjectCode PMT) est obligatoire en France (BR-FR-05).")
        }
        if invoice.legalNotePMD.trimmingCharacters(in: .whitespaces).isEmpty {
            warnings.append("La mention sur les pénalités de retard (note avec SubjectCode PMD) est obligatoire en France (BR-FR-05).")
        }
        if invoice.legalNoteAAB.trimmingCharacters(in: .whitespaces).isEmpty {
            warnings.append("La mention sur l'escompte (note avec SubjectCode AAB) est obligatoire en France (BR-FR-05).")
        }

        if let iban = invoice.paymentIBAN, !iban.trimmingCharacters(in: .whitespaces).isEmpty {
            if !IBANValidator.isValid(iban) {
                let cleaned = IBANValidator.normalize(iban)
                if cleaned.count < 15 || cleaned.count > 34 {
                    warnings.append("L'IBAN semble avoir une longueur inhabituelle (15 à 34 caractères attendus).")
                } else if cleaned.uppercased() != cleaned {
                    warnings.append("L'IBAN devrait être en majuscules.")
                } else {
                    errors.append("L'IBAN est invalide (clé de contrôle mod 97 incorrecte ou longueur pays inattendue).")
                }
            }
        }

        switch invoice.profile {
        case .minimum, .basicWL, .basic:
            warnings.append("Le profil \(invoice.profile.rawValue) est limité ; le profil EN 16931 est recommandé pour la réforme française.")
        case .en16931, .extended:
            break
        }

        let hasRuleErrors = rules.contains { $0.severity == .error }
        return FacturXValidationResult(
            isValid: errors.isEmpty && !hasRuleErrors,
            errors: errors,
            warnings: warnings,
            businessRules: rules
        )
    }

    public func validate(pdf: Data) -> FacturXValidationResult {
        var errors: [String] = []
        var warnings: [String] = []

        let s = String(data: pdf, encoding: .isoLatin1) ?? ""

        if s.isEmpty {
            return FacturXValidationResult(isValid: false, errors: ["Le PDF généré est vide."])
        }

        if !s.contains("factur-x.xml") {
            errors.append("Le fichier embarqué « factur-x.xml » est introuvable dans le PDF.")
        }

        if !s.contains("/AFRelationship /Alternative") {
            errors.append("La relation /AFRelationship /Alternative est absente (requise par Factur-X).")
        }

        if !s.contains("/EmbeddedFiles") {
            errors.append("L'arbre /Names /EmbeddedFiles est absent du catalogue PDF.")
        }

        if !s.contains("/AF ") && !s.contains("/AF[") && !s.contains("/AF\n") {
            errors.append("La clé /AF est absente du catalogue (référence au fichier embarqué requise).")
        }

        if !s.contains("/Metadata") {
            warnings.append("Le flux de métadonnées XMP est absent.")
        }

        if !s.contains("urn:factur-x:pdfa:CrossIndustryDocument:invoice:1p0#") {
            warnings.append("L'espace de noms XMP Factur-X (fx:) est absent.")
        }

        if !s.contains("<pdfaid:part>3</pdfaid:part>") {
            warnings.append("L'identifiant PDF/A-3 (pdfaid:part=3) est absent des métadonnées XMP.")
        }

        let xmlCount = s.components(separatedBy: "factur-x.xml").count - 1
        if xmlCount == 0 {
            errors.append("Aucun fichier factur-x.xml embarqué détecté.")
        }

        return FacturXValidationResult(
            isValid: errors.isEmpty,
            errors: errors,
            warnings: warnings
        )
    }

    public func validate(invoice: Invoice, pdf: Data) -> FacturXValidationResult {
        let r1 = validate(invoice: invoice)
        let r2 = validate(pdf: pdf)
        let allErrors = r1.errors + r2.errors
        let allWarnings = r1.warnings + r2.warnings
        return FacturXValidationResult(
            isValid: allErrors.isEmpty,
            errors: allErrors,
            warnings: allWarnings,
            businessRules: r1.businessRules
        )
    }
}
