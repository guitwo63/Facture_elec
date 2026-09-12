import Foundation

public struct FacturXValidationResult {
    public let isValid: Bool
    public let errors: [String]
    public let warnings: [String]

    public init(isValid: Bool, errors: [String] = [], warnings: [String] = []) {
        self.isValid = isValid
        self.errors = errors
        self.warnings = warnings
    }
}

public struct FacturXValidator {
    public init() {}

    public func validate(invoice: Invoice) -> FacturXValidationResult {
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

        if invoice.buyer.name.trimmingCharacters(in: .whitespaces).isEmpty {
            errors.append("Le nom du destinataire (acheteur) est obligatoire.")
        }
        if invoice.buyer.country.trimmingCharacters(in: .whitespaces).isEmpty {
            errors.append("Le pays du destinataire est obligatoire (code ISO à 2 lettres, ex. FR).")
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

        if invoice.issueDate > invoice.dueDate {
            warnings.append("La date d'échéance est antérieure à la date d'émission.")
        }

        if let iban = invoice.paymentIBAN, !iban.isEmpty {
            let cleaned = iban.replacingOccurrences(of: " ", with: "")
            if cleaned.count < 15 || cleaned.count > 34 {
                warnings.append("L'IBAN semble avoir une longueur inhabituelle (15 à 34 caractères attendus).")
            }
            if cleaned.uppercased() != cleaned {
                warnings.append("L'IBAN devrait être en majuscules.")
            }
        }

        switch invoice.profile {
        case .minimum, .basicWL, .basic:
            warnings.append("Le profil \(invoice.profile.rawValue) est limité ; le profil EN 16931 est recommandé pour la réforme française.")
        case .en16931, .extended:
            break
        }

        return FacturXValidationResult(
            isValid: errors.isEmpty,
            errors: errors,
            warnings: warnings
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
            warnings: allWarnings
        )
    }
}
