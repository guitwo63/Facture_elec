import Foundation

public struct OrderXValidator {
    public init() {}

    public func validate(order: SalesOrder) -> FacturXValidationResult {
        var errors: [String] = []
        var warnings: [String] = []

        if order.number.trimmingCharacters(in: .whitespaces).isEmpty {
            errors.append("Le numéro de commande est obligatoire.")
        }

        if order.buyer.name.trimmingCharacters(in: .whitespaces).isEmpty {
            errors.append("Le nom de l'acheteur est obligatoire.")
        }
        if order.buyer.country.trimmingCharacters(in: .whitespaces).isEmpty {
            errors.append("Le pays de l'acheteur est obligatoire (code ISO à 2 lettres, ex. FR).")
        }
        let buyerHasEndpoint = (order.buyer.endpointID?.trimmingCharacters(in: .whitespaces).isEmpty ?? true) == false
        let buyerHasSiren = (order.buyer.siren?.trimmingCharacters(in: .whitespaces).isEmpty ?? true) == false
        if !buyerHasEndpoint && !buyerHasSiren {
            errors.append("L'acheteur doit avoir un SIREN ou un identifiant électronique.")
        }

        if order.seller.name.trimmingCharacters(in: .whitespaces).isEmpty {
            errors.append("Le nom du client est obligatoire.")
        }
        if order.seller.country.trimmingCharacters(in: .whitespaces).isEmpty {
            errors.append("Le pays du client est obligatoire (code ISO à 2 lettres, ex. FR).")
        }
        let sellerHasEndpoint = (order.seller.endpointID?.trimmingCharacters(in: .whitespaces).isEmpty ?? true) == false
        let sellerHasSiren = (order.seller.siren?.trimmingCharacters(in: .whitespaces).isEmpty ?? true) == false
        if !sellerHasEndpoint && !sellerHasSiren {
            errors.append("Le client doit avoir un SIREN ou un identifiant électronique.")
        }

        if order.lines.isEmpty {
            errors.append("La commande doit contenir au moins une ligne.")
        } else {
            for (idx, line) in order.lines.enumerated() {
                if line.name.trimmingCharacters(in: .whitespaces).isEmpty {
                    errors.append("Ligne \(idx + 1) : la désignation est obligatoire.")
                }
                if line.quantity <= 0 {
                    errors.append("Ligne \(idx + 1) : la quantité demandée doit être positive.")
                }
                if line.unitPrice < 0 {
                    errors.append("Ligne \(idx + 1) : le prix unitaire ne peut pas être négatif.")
                }
                if line.unit.trimmingCharacters(in: .whitespaces).isEmpty {
                    warnings.append("Ligne \(idx + 1) : unité non renseignée (utilisez un code UN/ECE, ex. C62, DAY).")
                }
            }
        }

        if order.currency.trimmingCharacters(in: .whitespaces).isEmpty {
            errors.append("La devise est obligatoire (ex. EUR).")
        } else if order.currency.count != 3 {
            errors.append("La devise doit être un code ISO 4217 à 3 lettres (ex. EUR).")
        }

        if order.requestedDeliveryDate < order.issueDate {
            warnings.append("La date de livraison souhaitée est antérieure à la date d'émission de la commande.")
        }

        switch order.profile {
        case .basic:
            warnings.append("Le profil BASIC est limité ; le profil COMFORT est recommandé pour Order-X.")
        case .comfort, .extended:
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

        if !s.contains("order-x.xml") {
            errors.append("Le fichier embarqué « order-x.xml » est introuvable dans le PDF.")
        }

        if !s.contains("/AFRelationship /Alternative") {
            errors.append("La relation /AFRelationship /Alternative est absente (requise par Order-X).")
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

        if !s.contains("urn:factur-x:pdfa:CrossIndustryDocument:1p0#") {
            warnings.append("L'espace de noms XMP Order-X (fx:) est absent.")
        }

        if !s.contains("fx:DocumentType>ORDER") {
            warnings.append("Le type de document XMP (fx:DocumentType=ORDER) est absent.")
        }

        if !s.contains("<pdfaid:part>3</pdfaid:part>") {
            warnings.append("L'identifiant PDF/A-3 (pdfaid:part=3) est absent des métadonnées XMP.")
        }

        let xmlCount = s.components(separatedBy: "order-x.xml").count - 1
        if xmlCount == 0 {
            errors.append("Aucun fichier order-x.xml embarqué détecté.")
        }

        return FacturXValidationResult(
            isValid: errors.isEmpty,
            errors: errors,
            warnings: warnings
        )
    }

    public func validate(order: SalesOrder, pdf: Data) -> FacturXValidationResult {
        let r1 = validate(order: order)
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
