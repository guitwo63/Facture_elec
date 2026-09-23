import Foundation

/// Cadre de facturation (BT-23) de la réforme française. La lettre donne la nature de la
/// facture — B = biens, S = services, M = facture double (biens et services qui ne sont pas
/// accessoires l'un de l'autre) — et le chiffre le cadre : 1 = dépôt d'une facture,
/// 2 = facture déjà payée, 4 = facture définitive après acompte, 3/5/6 = sous-traitance et
/// cotraitance, 7 = TVA déjà collectée (opération déjà transmise en e-reporting),
/// 8 = facture multi-vendeurs, 9 = facture bidirectionnelle. Libellés repris du dossier de
/// spécifications externes DGFiP (cas d'usage, v2.3) et du Schematron France CTC, qui admet
/// ces 20 codes (BR-FR-08) — les anciens libellés (« Facturation papier », « Portail
/// public », « Dématérialisation ») ne correspondaient à rien de tout cela.
public enum BillingMode: String, Codable, CaseIterable {
    case b1 = "B1", s1 = "S1", m1 = "M1"
    case b2 = "B2", s2 = "S2", m2 = "M2"
    case s3 = "S3"
    case b4 = "B4", s4 = "S4", m4 = "M4"
    case s5 = "S5", s6 = "S6"
    case b7 = "B7", s7 = "S7"
    case b8 = "B8", s8 = "S8", m8 = "M8"
    case b9 = "B9", s9 = "S9", m9 = "M9"

    public var label: String {
        switch self {
        case .b1: return "Biens : dépôt d'une facture (B1)"
        case .s1: return "Services : dépôt d'une facture (S1)"
        case .m1: return "Double : dépôt d'une facture (M1)"
        case .b2: return "Biens : facture déjà payée (B2)"
        case .s2: return "Services : facture déjà payée (S2)"
        case .m2: return "Double : facture déjà payée (M2)"
        case .s3: return "Services : sous-traitance, paiement direct (S3)"
        case .b4: return "Biens : définitive après acompte (B4)"
        case .s4: return "Services : définitive après acompte (S4)"
        case .m4: return "Double : définitive après acompte (M4)"
        case .s5: return "Services : dépôt par un sous-traitant (S5)"
        case .s6: return "Services : dépôt par un cotraitant (S6)"
        case .b7: return "Biens : TVA déjà collectée (B7)"
        case .s7: return "Services : TVA déjà collectée (S7)"
        case .b8: return "Biens : facture multi-vendeurs (B8)"
        case .s8: return "Services : facture multi-vendeurs (S8)"
        case .m8: return "Double : facture multi-vendeurs (M8)"
        case .b9: return "Biens : facture bidirectionnelle (B9)"
        case .s9: return "Services : facture bidirectionnelle (S9)"
        case .m9: return "Double : facture bidirectionnelle (M9)"
        }
    }

    /// B2/S2/M2 — BR-FR-CO-09 : le montant déjà payé (BT-113) doit égaler le total TTC
    /// (BT-112), le net à payer (BT-115) être nul et l'échéance (BT-9) être la date du paiement.
    public var isAlreadyPaid: Bool {
        self == .b2 || self == .s2 || self == .m2
    }

    /// B4/S4/M4 — BR-FR-CO-08 : interdit sur une facture d'acompte (386).
    public var isFinalAfterDeposit: Bool {
        self == .b4 || self == .s4 || self == .m4
    }

    /// Cadres 8 et 9 : le Schematron France CTC (BR-FR-MV-*, BR-FR-BD-*) exige des lignes de
    /// regroupement par vendeur (sous-type GROUP) que `CIIXMLGenerator` ne produit pas — un XML
    /// émis avec l'un de ces cadres serait toujours rejeté.
    public var requiresGroupLines: Bool {
        rawValue.hasSuffix("8") || rawValue.hasSuffix("9")
    }

    /// Cadres proposés à la saisie : tous sauf 8 et 9 (voir `requiresGroupLines`). `current`
    /// y est ajouté s'il en fait partie (facture plus ancienne ou reçue), pour que le
    /// sélecteur affiche toujours la valeur réellement enregistrée.
    public static func selectableCases(current: BillingMode? = nil) -> [BillingMode] {
        allCases.filter { !$0.requiresGroupLines || $0 == current }
    }

    /// Cadre d'une facture d'acompte créée depuis une facture de ce cadre : jamais 4
    /// (BR-FR-CO-08), la même nature en cadre 1 à la place.
    public var forDeposit: BillingMode {
        isFinalAfterDeposit ? withFramework("1") : self
    }

    /// Cadre d'une facture de solde, qui EST la facture définitive après acompte : la même
    /// nature en cadre 4 quand la facture d'origine est en cadre 1, inchangé sinon.
    public var forFinalSettlement: BillingMode {
        rawValue.hasSuffix("1") ? withFramework("4") : self
    }

    private func withFramework(_ digit: String) -> BillingMode {
        BillingMode(rawValue: String(rawValue.prefix(1)) + digit) ?? self
    }
}

public struct InvoiceParty: Codable, Hashable {
    public var name: String
    public var street: String
    public var postcode: String
    public var city: String
    public var country: String
    public var vatNumber: String?
    public var siren: String?
    public var siret: String?
    public var legalSchemeID: String
    public var contactName: String?
    public var contactEmail: String?
    public var contactPhone: String?
    public var endpointID: String?
    public var endpointSchemeID: String
    public var iban: String?
    public var bic: String?
    public var paymentTerms: String?

    public init(
        name: String,
        street: String,
        postcode: String,
        city: String,
        country: String = "FR",
        vatNumber: String? = nil,
        siren: String? = nil,
        siret: String? = nil,
        legalSchemeID: String = "0002",
        contactName: String? = nil,
        contactEmail: String? = nil,
        contactPhone: String? = nil,
        endpointID: String? = nil,
        endpointSchemeID: String = "0225",
        iban: String? = nil,
        bic: String? = nil,
        paymentTerms: String? = nil
    ) {
        self.name = name
        self.street = street
        self.postcode = postcode
        self.city = city
        self.country = country
        self.vatNumber = vatNumber
        self.siren = siren
        self.siret = siret
        self.legalSchemeID = legalSchemeID
        self.contactName = contactName
        self.contactEmail = contactEmail
        self.contactPhone = contactPhone
        self.endpointID = endpointID
        self.endpointSchemeID = endpointSchemeID
        self.iban = iban
        self.bic = bic
        self.paymentTerms = paymentTerms
    }

    private enum CodingKeys: String, CodingKey {
        case name, street, postcode, city, country, vatNumber, siren, siret, legalSchemeID
        case contactName, contactEmail, contactPhone, endpointID, endpointSchemeID, iban, bic, paymentTerms
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        street = try c.decodeIfPresent(String.self, forKey: .street) ?? ""
        postcode = try c.decodeIfPresent(String.self, forKey: .postcode) ?? ""
        city = try c.decodeIfPresent(String.self, forKey: .city) ?? ""
        country = try c.decodeIfPresent(String.self, forKey: .country) ?? "FR"
        vatNumber = try c.decodeIfPresent(String.self, forKey: .vatNumber)
        siren = try c.decodeIfPresent(String.self, forKey: .siren)
        siret = try c.decodeIfPresent(String.self, forKey: .siret)
        legalSchemeID = try c.decodeIfPresent(String.self, forKey: .legalSchemeID) ?? "0002"
        contactName = try c.decodeIfPresent(String.self, forKey: .contactName)
        contactEmail = try c.decodeIfPresent(String.self, forKey: .contactEmail)
        contactPhone = try c.decodeIfPresent(String.self, forKey: .contactPhone)
        endpointID = try c.decodeIfPresent(String.self, forKey: .endpointID)
        endpointSchemeID = try c.decodeIfPresent(String.self, forKey: .endpointSchemeID) ?? "0225"
        iban = try c.decodeIfPresent(String.self, forKey: .iban)
        bic = try c.decodeIfPresent(String.self, forKey: .bic)
        paymentTerms = try c.decodeIfPresent(String.self, forKey: .paymentTerms)
    }

    public var fullAddressLine: String {
        var parts: [String] = []
        if !street.trimmingCharacters(in: .whitespaces).isEmpty { parts.append(street) }
        if !postcode.trimmingCharacters(in: .whitespaces).isEmpty { parts.append(postcode) }
        if !city.trimmingCharacters(in: .whitespaces).isEmpty { parts.append(city) }
        if !country.trimmingCharacters(in: .whitespaces).isEmpty { parts.append(country) }
        return parts.joined(separator: ", ")
    }
}

public enum SireneValidator {
    public static func luhnCheck(_ digits: String) -> Bool {
        let numbers = digits.filter { $0.isNumber }
        guard numbers.count >= 2 else { return false }
        var sum = 0
        let reversed = numbers.reversed()
        var isSecond = false
        for ch in reversed {
            guard let v = ch.wholeNumberValue else { return false }
            var n = v
            if isSecond {
                n *= 2
                if n > 9 { n -= 9 }
            }
            sum += n
            isSecond.toggle()
        }
        return sum % 10 == 0
    }

    public static func isValidSiren(_ value: String?) -> Bool {
        let numbers = (value ?? "").filter { $0.isNumber }
        guard numbers.count == 9 else { return false }
        return luhnCheck(numbers)
    }

    public static func isValidSiret(_ value: String?) -> Bool {
        let numbers = (value ?? "").filter { $0.isNumber }
        guard numbers.count == 14 else { return false }
        return luhnCheck(numbers)
    }
}

public struct OptionalField: Codable, Hashable, Identifiable {
    public var id: UUID
    public var tagName: String
    public var value: String

    public init(id: UUID = UUID(), tagName: String, value: String) {
        self.id = id
        self.tagName = tagName
        self.value = value
    }
}

/// Pièce jointe libre (justificatif, devis signé, bon de livraison scanné…) attachée à un
/// document. Le contenu est embarqué en base64 dans le JSON persisté (UserDefaults), comme
/// le reste des données — pas de gestion de fichiers externes séparée. `maxSizeBytes` borne
/// la taille pour ne pas alourdir démesurément la sauvegarde/synchronisation pCloud.
public struct Attachment: Codable, Hashable, Identifiable {
    public var id: UUID
    public var fileName: String
    public var data: Data
    public var addedAt: Date

    public static let maxSizeBytes = 10 * 1024 * 1024 // 10 Mo

    public init(id: UUID = UUID(), fileName: String, data: Data, addedAt: Date = Date()) {
        self.id = id
        self.fileName = fileName
        self.data = data
        self.addedAt = addedAt
    }

    public var sizeDescription: String {
        ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)
    }
}

public enum OptionalFieldLocation: String, Codable, CaseIterable {
    case header
    case line
}

public struct OptionalFieldTemplate: Identifiable, Hashable {
    public let id: String
    public let bt: String
    public let label: String
    public let tagName: String
    public let location: OptionalFieldLocation
    public let help: String
    public init(_ bt: String, _ label: String, _ tagName: String, _ location: OptionalFieldLocation, _ help: String) {
        self.id = bt
        self.bt = bt
        self.label = label
        self.tagName = tagName
        self.location = location
        self.help = help
    }
}

/// Champs optionnels proposés à la saisie, tous émis par `CIIXMLGenerator`. Chaque entrée a
/// été vérifiée (2026-09-23), seule puis toutes ensemble, contre le XSD Factur-X 1.09
/// EN16931 et les Schematron EN16931 et France CTC : les numéros BT sont ceux de la norme
/// EN 16931, et les balises celles de sa syntaxe CII pour ce profil.
public enum OptionalFieldCatalogue {
    public static let header: [OptionalFieldTemplate] = [
        OptionalFieldTemplate("BT-10", "Réf. acheteur", "ram:BuyerReference", .header, "BT-10 - Référence acheteur (BuyerReference). Référence de routage/traitement attribuée par l'acheteur (ex. Leitweg-ID), distincte du numéro de commande (BT-13)."),
        OptionalFieldTemplate("BT-11", "Réf. projet", "ram:SpecifiedProcuringProject/ram:ID", .header, "BT-11 - Référence du projet (SpecifiedProcuringProject/ID). Le nom de projet, obligatoire en CII, est émis avec la valeur conventionnelle « Project reference »."),
        OptionalFieldTemplate("BT-12", "Réf. contrat", "ram:ContractReferencedDocument/ram:IssuerAssignedID", .header, "BT-12 - Référence du contrat (ContractReferencedDocument)."),
        OptionalFieldTemplate("BT-15", "Réf. bon de réception", "ram:ReceivingAdviceReferencedDocument/ram:IssuerAssignedID", .header, "BT-15 - Référence de l'avis de réception (ReceivingAdviceReferencedDocument)."),
        OptionalFieldTemplate("BT-16", "Réf. bon de livraison", "ram:DespatchAdviceReferencedDocument/ram:IssuerAssignedID", .header, "BT-16 - Référence de l'avis d'expédition (DespatchAdviceReferencedDocument)."),
        OptionalFieldTemplate("BT-17", "Réf. appel d'offres ou lot", "ram:AdditionalReferencedDocument/ram:IssuerAssignedID", .header, "BT-17 - Référence de l'appel d'offres ou du lot (AdditionalReferencedDocument, code type 50)."),
        OptionalFieldTemplate("BT-80", "Pays de livraison", "ram:ShipToTradeParty/ram:PostalTradeAddress/ram:CountryID", .header, "BT-80 - Pays de livraison (ShipToTradeParty/PostalTradeAddress/CountryID), code pays ISO 3166-1 à 2 lettres (ex. DE ; GR pour la Grèce, pas EL). Exigé pour une livraison intracommunautaire (catégorie K, BR-IC-12) : sans saisie, le pays de l'acheteur (BT-55) est émis."),
    ]
    public static let line: [OptionalFieldTemplate] = [
        OptionalFieldTemplate("BT-132", "N° ligne de commande", "ram:BuyerOrderReferencedDocument/ram:LineID", .line, "BT-132 - Numéro de la ligne concernée dans la commande de l'acheteur. Le numéro de la commande elle-même est le BT-13, en en-tête."),
        OptionalFieldTemplate("BT-155", "Réf. article vendeur", "ram:SellerAssignedID", .line, "BT-155 - Identifiant de l'article attribué par le vendeur (SellerAssignedID)."),
        OptionalFieldTemplate("BT-156", "Réf. article acheteur", "ram:BuyerAssignedID", .line, "BT-156 - Identifiant de l'article attribué par l'acheteur (BuyerAssignedID)."),
        OptionalFieldTemplate("BT-157", "Code GTIN (EAN)", "ram:GlobalID", .line, "BT-157 - Identifiant normalisé de l'article (GlobalID), émis avec le schéma 0160 (GTIN) : code GTIN/EAN de 8, 12, 13 ou 14 chiffres. Pour une référence interne, utiliser le BT-155."),
    ]

    /// Balises de ligne proposées par des versions antérieures, retirées parce qu'elles
    /// rendaient le XML non conforme au profil EN16931. Les valeurs déjà saisies restent
    /// enregistrées et affichées, mais ne sont plus émises dans le XML.
    public static let retiredLineTags: [String: String] = [
        "ram:ContractReferencedDocument/ram:IssuerAssignedID": "Ancien champ « Réf. contrat ligne » : le profil EN 16931 n'a pas de référence de contrat par ligne (XML rejeté par le XSD). Valeur conservée pour mémoire, non émise dans le XML ; utiliser la référence de contrat d'en-tête (BT-12).",
        "ram:BuyerOrderReferencedDocument/ram:IssuerAssignedID": "Ancien champ « Réf. commande ligne » : le profil EN 16931 n'admet, au niveau de la ligne, que le numéro de ligne de commande (BT-132). Valeur conservée pour mémoire, non émise dans le XML.",
    ]

    public static func templates(for location: OptionalFieldLocation) -> [OptionalFieldTemplate] {
        location == .header ? header : line
    }
    public static func template(forTag tagName: String, location: OptionalFieldLocation) -> OptionalFieldTemplate? {
        templates(for: location).first(where: { $0.tagName == tagName })
    }

    /// Aide affichée pour une balise : celle du catalogue, sinon l'explication d'une balise
    /// retirée, sinon le rappel qu'une balise libre n'est pas émise.
    public static func help(forTag tagName: String, location: OptionalFieldLocation) -> String {
        if let template = template(forTag: tagName, location: location) {
            return template.help
        }
        if location == .line, let note = retiredLineTags[tagName] {
            return note
        }
        return "Balise libre (non émise dans le XML CII)."
    }
}

/// Catégorie de TVA (BT-118/BT-151), liste UNTDID 5305 restreinte aux codes
/// pertinents pour une facture française. Avant cette version, la catégorie
/// était déduite uniquement du taux (0 % -> Z, sinon S) : impossible de
/// distinguer une autoliquidation, une exportation ou une exonération, qui
/// affichent toutes un taux à 0 % mais nécessitent un code et (sauf Z/S) un
/// motif d'exonération (BT-120) différents.
public enum VATCategory: String, Codable, CaseIterable {
    case standard = "S"
    case zeroRated = "Z"
    case exempt = "E"
    case reverseCharge = "AE"
    case intraCommunity = "K"
    case export = "G"
    case outOfScope = "O"

    public var label: String {
        switch self {
        case .standard: return "Taux normal"
        case .zeroRated: return "Taux zéro"
        case .exempt: return "Exonérée"
        case .reverseCharge: return "Autoliquidation"
        case .intraCommunity: return "Livraison intracommunautaire"
        case .export: return "Exportation hors UE"
        case .outOfScope: return "Hors champ de TVA"
        }
    }

    /// BR-E-10/BR-AE-10/BR-IC-10/BR-G-10/BR-O-10 (EN16931) : un motif
    /// d'exonération (BT-120) est obligatoire pour ces catégories.
    public var requiresExemptionReason: Bool {
        switch self {
        case .exempt, .reverseCharge, .intraCommunity, .export, .outOfScope: return true
        case .standard, .zeroRated: return false
        }
    }
}

public struct InvoiceLine: Codable, Hashable, Identifiable {
    public var id: UUID
    public var name: String
    public var description: String?
    public var quantity: Double
    public var unit: String
    public var unitPrice: Double
    public var vatRate: Double
    public var vatCategory: VATCategory
    public var vatExemptionReason: String?
    public var orderReference: String?
    public var optionalFields: [OptionalField]

    public init(
        id: UUID = UUID(),
        name: String,
        description: String? = nil,
        quantity: Double,
        unit: String = "C62",
        unitPrice: Double,
        vatRate: Double = 20.0,
        vatCategory: VATCategory? = nil,
        vatExemptionReason: String? = nil,
        orderReference: String? = nil,
        optionalFields: [OptionalField] = []
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.quantity = quantity
        self.unit = unit
        self.unitPrice = unitPrice
        self.vatRate = vatRate
        self.vatCategory = vatCategory ?? (vatRate == 0 ? .zeroRated : .standard)
        self.vatExemptionReason = vatExemptionReason
        self.orderReference = orderReference
        self.optionalFields = optionalFields
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, description, quantity, unit, unitPrice, vatRate, vatCategory, vatExemptionReason
        case orderReference, optionalFields
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        description = try c.decodeIfPresent(String.self, forKey: .description)
        quantity = try c.decodeIfPresent(Double.self, forKey: .quantity) ?? 0
        unit = try c.decodeIfPresent(String.self, forKey: .unit) ?? "C62"
        unitPrice = try c.decodeIfPresent(Double.self, forKey: .unitPrice) ?? 0
        vatRate = try c.decodeIfPresent(Double.self, forKey: .vatRate) ?? 20.0
        if let rawCategory = try c.decodeIfPresent(String.self, forKey: .vatCategory),
           let category = VATCategory(rawValue: rawCategory) {
            vatCategory = category
        } else {
            vatCategory = vatRate == 0 ? .zeroRated : .standard
        }
        vatExemptionReason = try c.decodeIfPresent(String.self, forKey: .vatExemptionReason)
        orderReference = try c.decodeIfPresent(String.self, forKey: .orderReference)
        optionalFields = try c.decodeIfPresent([OptionalField].self, forKey: .optionalFields) ?? []
    }

    public var lineTotal: Double {
        (quantity * unitPrice).rounded(toPlaces: 2)
    }
}

/// Un sous-total de TVA (BG-23) : les lignes d'un même couple (taux, catégorie). Deux lignes
/// à 0 % peuvent relever de catégories différentes (taux zéro, exonération, autoliquidation,
/// exportation…) et donnent alors deux sous-totaux distincts au même taux, chacun avec son
/// propre motif d'exonération le cas échéant. L'identité est donc le couple et non le taux
/// seul : un `ForEach(…, id: \.rate)` sur les totaux aurait deux lignes de même identité.
public struct VATBreakdownEntry: Hashable, Identifiable {
    /// Clé de regroupement, qui sert aussi d'identité : unique par construction dans une
    /// ventilation, et inchangée quand la base ou le motif du sous-total change.
    public struct Key: Hashable {
        public let rate: Double
        public let category: VATCategory
    }

    public let rate: Double
    public let category: VATCategory
    public let exemptionReason: String?
    public let basis: Double
    public let amount: Double

    public var id: Key { Key(rate: rate, category: category) }

    /// Ventilation commune aux factures, commandes et devis (`vatBreakdown`), triée par taux
    /// puis dans l'ordre de `VATCategory.allCases` (celui du sélecteur de catégorie). Sans ce
    /// second critère, deux catégories au même taux sortaient dans l'ordre d'itération d'un
    /// dictionnaire, qui change d'un lancement de l'app à l'autre (écran, PDF et XML).
    static func breakdown(of lines: [InvoiceLine]) -> [VATBreakdownEntry] {
        var basisByKey: [Key: Double] = [:]
        var reasonByKey: [Key: String] = [:]
        for line in lines {
            let key = Key(rate: line.vatRate, category: line.vatCategory)
            basisByKey[key, default: 0] += line.lineTotal
            if reasonByKey[key] == nil,
               let reason = line.vatExemptionReason?.trimmingCharacters(in: .whitespaces), !reason.isEmpty {
                reasonByKey[key] = reason
            }
        }
        func position(_ category: VATCategory) -> Int { VATCategory.allCases.firstIndex(of: category) ?? 0 }
        return basisByKey.map { (key, basis) in
            let basisR = basis.rounded(toPlaces: 2)
            let amount = (basisR * key.rate / 100).rounded(toPlaces: 2)
            return VATBreakdownEntry(rate: key.rate, category: key.category, exemptionReason: reasonByKey[key],
                                     basis: basisR, amount: amount)
        }.sorted { ($0.rate, position($0.category)) < ($1.rate, position($1.category)) }
    }
}

/// Profil Factur-X (BT-24). `CIIXMLGenerator` produit toujours la structure du profil
/// EN 16931 et ne change que l'URN : ce XML est conforme en EN 16931 et en EXTENDED, qui
/// l'englobe, mais pas dans les profils plus restreints. Mesuré le 2026-09-23 sur 36 cas
/// de facture, contre le XSD et le Schematron Factur-X 1.09 de chaque profil et le
/// Schematron France CTC : MINIMUM et BASIC WL rejettent les lignes dans tous les cas (et
/// MINIMUM les mentions légales et les adresses électroniques, exigées en France) ; BASIC
/// rejette notamment les contacts, le moyen de paiement « SEPA » émis avec tout IBAN, le BIC
/// et la description des lignes. Ces trois profils ne sont donc plus proposés à l'émission
/// (`selectableCases`) ; ils restent décodables pour les factures existantes et reçues.
public enum FacturXProfile: String, Codable, CaseIterable {
    case minimum = "MINIMUM"
    case basicWL = "BASIC WL"
    case basic = "BASIC"
    case en16931 = "EN 16931"
    case extended = "EXTENDED"

    /// Vrai si le XML de `CIIXMLGenerator` est conforme à ce profil. Une facture émise dans
    /// un autre profil est bloquée à l'export (BR-PROFIL).
    public var isIssuable: Bool {
        self == .en16931 || self == .extended
    }

    /// Profils proposés à la saisie : EN 16931 et EXTENDED. `current` y est ajouté s'il en
    /// fait partie (société ou facture plus ancienne), pour que le sélecteur affiche toujours
    /// la valeur réellement enregistrée.
    public static func selectableCases(current: FacturXProfile? = nil) -> [FacturXProfile] {
        allCases.filter { $0.isIssuable || $0 == current }
    }

    /// Profil d'une nouvelle facture créée à partir de ce profil (celui de la société, ou
    /// celui de la facture d'origine d'un doublon, avoir, acompte ou solde) : jamais un
    /// profil que le générateur ne respecte pas, EN 16931 à la place.
    public var forNewInvoice: FacturXProfile {
        isIssuable ? self : .en16931
    }

    public var urn: String {
        switch self {
        case .minimum: return "urn:factur-x.eu:1p0:minimum"
        case .basicWL: return "urn:factur-x.eu:1p0:basicwl"
        case .basic: return "urn:cen.eu:en16931:2017#compliant#urn:factur-x.eu:1p0:basic"
        case .en16931: return "urn:cen.eu:en16931:2017"
        case .extended: return "urn:cen.eu:en16931:2017#conformant#urn:factur-x.eu:1p0:extended"
        }
    }

    public var conformanceLevel: String {
        switch self {
        case .minimum: return "MINIMUM"
        case .basicWL: return "BASIC WL"
        case .basic: return "BASIC"
        case .en16931: return "EN 16931"
        case .extended: return "EXTENDED"
        }
    }
}

public enum InvoiceTypeCode: String, Codable, CaseIterable {
    case commercialInvoice = "380"
    case correction = "384"
    case creditNote = "381"
    case internalCreditNote = "INT"
    case deposit = "386"
    case finalSettlement = "387"

    public var label: String {
        switch self {
        case .commercialInvoice: return "Facture commerciale (380)"
        case .correction: return "Facture rectificative (384)"
        case .creditNote: return "Avoir (381)"
        case .internalCreditNote: return "Avoir interne (INT)"
        case .deposit: return "Facture d'acompte (386)"
        case .finalSettlement: return "Facture de solde (387)"
        }
    }

    public var isCreditNote: Bool {
        self == .creditNote || self == .internalCreditNote
    }

    public var isInternalCreditNote: Bool {
        self == .internalCreditNote
    }

    public var isDeposit: Bool {
        self == .deposit
    }

    public var isFinalSettlement: Bool {
        self == .finalSettlement
    }

    public var requiresPrecedingInvoice: Bool {
        self == .creditNote || self == .correction || self == .finalSettlement
    }

    /// Une facture d'acompte ou de solde ne doit être créée qu'à partir d'une facture
    /// commerciale ou rectificative — jamais depuis un avoir, un acompte ou un solde existant.
    public var allowsDepositCreation: Bool {
        self == .commercialInvoice || self == .correction
    }
}

/// Cycle de vie **fonctionnel** d'une facture — volontairement réduit et stable, distinct
/// du détail des événements SUPER PDP (codes `fr:2XX`). Choix d'architecture (2026-09-18) :
/// après avoir tenté de faire porter à cette enum à la fois le statut métier ET le détail
/// du cycle de vie réseau (15 cas, un temps), on est revenu à un modèle séparé — voir
/// `docs/integrations-superpdp.md` section 9. Raison : SUPER PDP documente elle-même que
/// son flux d'événements "is not a state machine" (la présence d'un événement indique
/// qu'il s'est produit, pas un statut actuel exclusif) ; le forcer dans un statut unique
/// rend chaque nouveau code coûteux à intégrer (verrouillage, rang, transitions à
/// rejuger) alors qu'il ne change souvent rien pour l'app.
///
/// Le détail des événements SUPER PDP (fr:200…fr:220, envoyés et reçus) vit dans le
/// journal SUPER PDP de la facture (`SuperPDPInvoiceEvent`/`listInvoiceEvents`), pas ici.
/// La passerelle entre les deux est `PDPStatusMapper.functionalTransition(for:)`
/// (`SuperPDPStatusSync.swift`) : elle seule sait quel code implique quel statut
/// fonctionnel, et c'est le seul endroit à modifier quand SUPER PDP ajoute/précise un code.
public enum InvoiceStatus: String, CaseIterable {
    case draft
    case issued
    case sent
    case accepted
    case disputed
    case refused
    case partiallyPaid
    case paid
    case cancelled

    public var label: String {
        switch self {
        case .draft: return "Brouillon"
        case .issued: return "Validée (non envoyée)"
        case .sent: return "Envoyée / en cours"
        case .accepted: return "Acceptée"
        case .disputed: return "Contestée"
        case .refused: return "Refusée"
        case .partiallyPaid: return "Payée partiellement"
        case .paid: return "Payée"
        case .cancelled: return "Annulée"
        }
    }

    public var systemImage: String {
        switch self {
        case .draft: return "doc"
        case .issued: return "doc.fill"
        case .sent: return "paperplane.fill"
        case .accepted: return "checkmark.seal.fill"
        case .disputed: return "exclamationmark.bubble.fill"
        case .refused: return "xmark.octagon.fill"
        case .partiallyPaid: return "circle.lefthalf.filled"
        case .paid: return "checkmark.circle.fill"
        case .cancelled: return "minus.circle.fill"
        }
    }

    public var hexColor: String {
        switch self {
        case .draft: return "6E6E73"
        case .issued: return "2A6EBB"
        case .sent: return "B07A2A"
        case .accepted: return "2E8B57"
        case .disputed: return "D35400"
        case .refused: return "C0392B"
        case .partiallyPaid: return "6FA287"
        case .paid: return "1E7E34"
        case .cancelled: return "8C8C8C"
        }
    }

    public var locksInvoice: Bool {
        switch self {
        case .draft, .refused: return false
        case .issued, .sent, .accepted, .disputed, .partiallyPaid, .paid, .cancelled: return true
        }
    }

    /// Ordre du cycle de vie (pour empêcher tout rapatriement rétrograde depuis la PDP).
    /// `accepted`/`disputed`/`refused` partagent le même rang : des issues différentes au
    /// même point du cycle, pas une progression linéaire entre elles. `partiallyPaid` est
    /// strictement après ce palier (un paiement partiel suppose une facture déjà acceptée)
    /// et strictement avant `paid`/`cancelled`, pour que recevoir un paiement total après un
    /// paiement partiel compte bien comme un avancement.
    public var lifecycleRank: Int {
        switch self {
        case .draft: return 0
        case .issued: return 1
        case .sent: return 2
        case .accepted: return 3
        case .disputed: return 3
        case .refused: return 3
        case .partiallyPaid: return 4
        case .paid: return 5
        case .cancelled: return 5
        }
    }

    /// Transitions par défaut (personnalisables ensuite dans Réglages > Tables > Statuts
    /// des factures). D'après le diagramme des Spécifications Externes AIFE : une facture
    /// acceptée peut encore être contestée tardivement, mais ne redevient jamais "refusée"
    /// directement (il faut alors passer par une contestation, ou un avoir).
    public func allowedTransitions() -> [InvoiceStatus] {
        switch self {
        case .draft:
            return [.issued]
        case .issued:
            return [.sent, .refused]
        case .sent:
            return [.accepted, .disputed, .refused]
        case .accepted:
            return [.disputed, .partiallyPaid, .paid]
        case .disputed:
            return [.accepted, .refused]
        case .partiallyPaid:
            return [.disputed, .paid]
        case .refused:
            return []
        case .paid:
            return []
        case .cancelled:
            return []
        }
    }

}

extension InvoiceStatus: Codable {
    /// Migration sûre depuis un modèle antérieur, plus détaillé, qui distinguait les étapes
    /// réseau (`sentToPDP`/`sentToRecipient`/`receivedByRecipient`/`madeAvailable`/
    /// `acknowledged`/`onHold`) et plusieurs variantes de rejet (`rejected`/
    /// `technicallyRejected`) ou d'aboutissement (`completed`/`paymentSent`). Toute donnée
    /// déjà persistée avec l'un de ces anciens statuts reste lisible, recalée sur son
    /// équivalent le plus proche dans le modèle réduit — sans quoi une facture existante
    /// deviendrait indécodable (perte silencieuse de toutes les factures du fichier).
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        if let match = InvoiceStatus(rawValue: raw) {
            self = match
            return
        }
        switch raw {
        case "sentToPDP", "sentToRecipient", "receivedByRecipient", "madeAvailable", "acknowledged", "onHold":
            self = .sent
        case "rejected", "technicallyRejected":
            self = .refused
        case "completed":
            self = .accepted
        case "paymentSent":
            self = .paid
        default:
            self = .draft
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// Cycle de vie **fonctionnel** d'une facture d'achat — pendant de `InvoiceStatus`, mais
/// orienté validation interne (a-t-on reçu la facture, l'acheteur l'a-t-il transmise, le
/// comptable l'a-t-il approuvée pour paiement) plutôt qu'acheminement réseau. Un achat n'a
/// personne à qui "envoyer" quoi que ce soit avant validation — c'est nous le destinataire.
/// Même choix d'architecture que côté ventes (voir la doc de `InvoiceStatus` et
/// `docs/integrations-superpdp.md` section 9) : petit enum fermé et stable, le détail des
/// événements SUPER PDP reste dans le journal PDP de la facture, pas ici.
public enum PurchaseInvoiceStatus: String, CaseIterable {
    case draft
    case received
    case toValidate
    case validated
    case disputed
    case refused
    case paid
    case cancelled

    public var label: String {
        switch self {
        case .draft: return "Brouillon"
        case .received: return "Reçue"
        case .toValidate: return "À valider"
        case .validated: return "Validée"
        case .disputed: return "Contestée"
        case .refused: return "Refusée"
        case .paid: return "Payée"
        case .cancelled: return "Annulée"
        }
    }

    public var systemImage: String {
        switch self {
        case .draft: return "doc"
        case .received: return "tray.and.arrow.down.fill"
        case .toValidate: return "hourglass"
        case .validated: return "checkmark.seal.fill"
        case .disputed: return "exclamationmark.bubble.fill"
        case .refused: return "xmark.octagon.fill"
        case .paid: return "checkmark.circle.fill"
        case .cancelled: return "minus.circle.fill"
        }
    }

    public var hexColor: String {
        switch self {
        case .draft: return "6E6E73"
        case .received: return "2A6EBB"
        case .toValidate: return "B07A2A"
        case .validated: return "2E8B57"
        case .disputed: return "D35400"
        case .refused: return "C0392B"
        case .paid: return "1E7E34"
        case .cancelled: return "8C8C8C"
        }
    }

    public var locksInvoice: Bool {
        switch self {
        case .draft, .refused: return false
        case .received, .toValidate, .validated, .disputed, .paid, .cancelled: return true
        }
    }

    /// Ordre du cycle de vie (même usage que `InvoiceStatus.lifecycleRank` : empêcher tout
    /// rapatriement rétrograde depuis PDP). `validated`/`disputed`/`refused` partagent le
    /// même rang : des issues différentes à la même étape de décision comptable.
    public var lifecycleRank: Int {
        switch self {
        case .draft: return 0
        case .received: return 1
        case .toValidate: return 2
        case .validated: return 3
        case .disputed: return 3
        case .refused: return 3
        case .paid: return 4
        case .cancelled: return 4
        }
    }

    /// Transitions par défaut (personnalisables dans Réglages > Tables > Statuts des
    /// factures d'achat). `draft` n'existe que pour une saisie manuelle en cours ; une
    /// facture reçue via SUPER PDP arrive directement à `received`, il n'y a rien à
    /// "brouillonner" sur un document déjà complet reçu d'un tiers.
    public func allowedTransitions() -> [PurchaseInvoiceStatus] {
        switch self {
        case .draft:
            return [.received]
        case .received:
            return [.toValidate]
        case .toValidate:
            return [.validated, .disputed, .refused]
        case .validated:
            return [.disputed, .paid]
        case .disputed:
            return [.validated, .refused]
        case .refused:
            return []
        case .paid:
            return []
        case .cancelled:
            return []
        }
    }
}

extension PurchaseInvoiceStatus: Codable {
    /// Pas de donnée héritée à migrer (nouveau statut) — le repli sûr sur `.draft` pour
    /// toute valeur inconnue est une protection anticipée, sur le même principe que
    /// `InvoiceStatus.init(from:)` : si un cas venait à être retiré plus tard, une facture
    /// d'achat déjà persistée avec ce statut ne doit jamais devenir indécodable.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = PurchaseInvoiceStatus(rawValue: raw) ?? .draft
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct Invoice: Codable, Hashable, Identifiable {
    public var id: UUID
    public var number: String
    public var type: InvoiceTypeCode
    public var status: InvoiceStatus
    public var issueDate: Date
    public var createdAt: Date
    public var dueDate: Date
    public var currency: String
    public var profile: FacturXProfile
    public var seller: InvoiceParty
    public var buyer: InvoiceParty
    public var companyID: UUID?
    public var purchaseOrderRef: String?
    public var precedingInvoiceRef: String?
    public var precedingInvoiceDate: Date?
    public var lines: [InvoiceLine]
    public var paymentIBAN: String?
    public var paymentBIC: String?
    public var paymentTerms: String?
    public var notes: String?
    public var billingMode: BillingMode
    public var legalNotePMT: String
    public var legalNotePMD: String
    public var legalNoteAAB: String
    public var prepaidAmount: Double
    public var superPDPRemoteID: String?
    public var optionalFields: [OptionalField]
    public var attachments: [Attachment]
    /// Distinct de `notes` (BT-22, imprimé sur le document) : remarque interne à l'équipe,
    /// jamais incluse dans le PDF/XML généré.
    public var internalComment: String?
    /// Date du dernier envoi par email au client — pour avertir avant un renvoi accidentel.
    public var lastEmailSentAt: Date?
    /// Purement interne (aide de saisie) : numéro de la facture de solde dans laquelle cet
    /// acompte a déjà été repris, le cas échéant. N'est jamais émis dans le XML EN16931/
    /// Factur-X ni imprimé sur le PDF — sert uniquement à avertir (sans bloquer) si le même
    /// acompte est repris dans plusieurs soldes.
    public var linkedSettlementRef: String?

    public init(
        id: UUID = UUID(),
        number: String,
        type: InvoiceTypeCode = .commercialInvoice,
        status: InvoiceStatus = .draft,
        issueDate: Date = Date(),
        createdAt: Date = Date(),
        dueDate: Date = Date().addingTimeInterval(30 * 86400),
        currency: String = "EUR",
        profile: FacturXProfile = .en16931,
        seller: InvoiceParty,
        buyer: InvoiceParty,
        companyID: UUID? = nil,
        buyerReference: String? = nil,
        purchaseOrderRef: String? = nil,
        precedingInvoiceRef: String? = nil,
        precedingInvoiceDate: Date? = nil,
        lines: [InvoiceLine] = [],
        paymentIBAN: String? = nil,
        paymentBIC: String? = nil,
        paymentTerms: String? = nil,
        notes: String? = nil,
        billingMode: BillingMode = .m1,
        legalNotePMT: String = "Indemnité forfaitaire pour frais de recouvrement due à compter du 1er jour de retard : 40 EUR",
        legalNotePMD: String = "Taux d'intérêt des pénalités de retard : 3 fois le taux légal en vigueur",
        legalNoteAAB: String = "Escompte pour paiement anticipé : aucun",
        prepaidAmount: Double = 0,
        superPDPRemoteID: String? = nil,
        optionalFields: [OptionalField] = [],
        attachments: [Attachment] = [],
        internalComment: String? = nil,
        lastEmailSentAt: Date? = nil,
        linkedSettlementRef: String? = nil
    ) {
        self.id = id
        self.number = number
        self.type = type
        self.status = status
        self.issueDate = issueDate
        self.createdAt = createdAt
        self.dueDate = dueDate
        self.currency = currency
        self.profile = profile
        self.seller = seller
        self.buyer = buyer
        self.companyID = companyID
        self.purchaseOrderRef = purchaseOrderRef
        self.precedingInvoiceRef = precedingInvoiceRef
        self.precedingInvoiceDate = precedingInvoiceDate
        self.lines = lines
        self.paymentIBAN = paymentIBAN
        self.paymentBIC = paymentBIC
        self.paymentTerms = paymentTerms
        self.notes = notes
        self.billingMode = billingMode
        self.legalNotePMT = legalNotePMT
        self.legalNotePMD = legalNotePMD
        self.legalNoteAAB = legalNoteAAB
        self.prepaidAmount = prepaidAmount
        self.superPDPRemoteID = superPDPRemoteID
        self.optionalFields = optionalFields
        self.attachments = attachments
        self.internalComment = internalComment
        self.lastEmailSentAt = lastEmailSentAt
        self.linkedSettlementRef = linkedSettlementRef
        self.buyerReference = buyerReference
    }

    public var buyerReference: String? {
        get { referenceField("ram:BuyerReference") }
        set { setReferenceField("ram:BuyerReference", newValue) }
    }

    public var contractRef: String? {
        get { referenceField("ram:ContractReferencedDocument/ram:IssuerAssignedID") }
        set { setReferenceField("ram:ContractReferencedDocument/ram:IssuerAssignedID", newValue) }
    }
    /// BT-17 : en syntaxe CII EN16931, un `AdditionalReferencedDocument` de code type 50 —
    /// `TendererReferencedDocument`, utilisé jusqu'ici, n'existe pas dans ce profil (XML
    /// rejeté par le XSD). Les factures enregistrées avec l'ancienne balise sont migrées au
    /// décodage (voir `init(from:)`).
    public var tenderRef: String? {
        get { referenceField("ram:AdditionalReferencedDocument/ram:IssuerAssignedID") }
        set { setReferenceField("ram:AdditionalReferencedDocument/ram:IssuerAssignedID", newValue) }
    }
    public var receivingAdviceRef: String? {
        get { referenceField("ram:ReceivingAdviceReferencedDocument/ram:IssuerAssignedID") }
        set { setReferenceField("ram:ReceivingAdviceReferencedDocument/ram:IssuerAssignedID", newValue) }
    }
    public var despatchAdviceRef: String? {
        get { referenceField("ram:DespatchAdviceReferencedDocument/ram:IssuerAssignedID") }
        set { setReferenceField("ram:DespatchAdviceReferencedDocument/ram:IssuerAssignedID", newValue) }
    }
    /// BT-80 : pays de livraison saisi (champ optionnel), tel quel. Voir `effectiveDeliveryCountry`
    /// pour celui qui est émis.
    public var deliveryCountry: String? {
        get { referenceField("ram:ShipToTradeParty/ram:PostalTradeAddress/ram:CountryID") }
        set { setReferenceField("ram:ShipToTradeParty/ram:PostalTradeAddress/ram:CountryID", newValue) }
    }

    /// Pays de livraison émis dans le XML (BT-80) : celui saisi, en majuscules ; à défaut, pour
    /// une livraison intracommunautaire (une ligne en catégorie K), le pays de l'acheteur
    /// (BT-55) — BR-IC-12 exige alors un BT-80, et le bien part en général à l'adresse de
    /// l'acheteur. `nil` : pas de BT-80 à émettre.
    public var effectiveDeliveryCountry: String? {
        if let entered = deliveryCountry {
            return entered.trimmingCharacters(in: .whitespaces).uppercased()
        }
        guard lines.contains(where: { $0.vatCategory == .intraCommunity }) else { return nil }
        let buyerCountry = buyer.country.trimmingCharacters(in: .whitespaces)
        return buyerCountry.isEmpty ? nil : buyerCountry
    }

    private func referenceField(_ tagName: String) -> String? {
        guard let v = optionalFields.first(where: { $0.tagName == tagName })?.value,
              !v.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return v
    }

    private mutating func setReferenceField(_ tagName: String, _ value: String?) {
        if let idx = optionalFields.firstIndex(where: { $0.tagName == tagName }) {
            if let value, !value.trimmingCharacters(in: .whitespaces).isEmpty {
                optionalFields[idx].value = value
            } else {
                optionalFields.remove(at: idx)
            }
        } else if let value, !value.trimmingCharacters(in: .whitespaces).isEmpty {
            optionalFields.append(OptionalField(tagName: tagName, value: value))
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id, number, type, status, issueDate, createdAt, dueDate, currency, profile, seller, buyer, companyID
        case purchaseOrderRef, precedingInvoiceRef, precedingInvoiceDate, lines, paymentIBAN, paymentBIC, paymentTerms, notes
        case billingMode, legalNotePMT, legalNotePMD, legalNoteAAB, prepaidAmount, superPDPRemoteID, optionalFields
        case attachments, internalComment, lastEmailSentAt, linkedSettlementRef
    }

    private enum LegacyReferenceKeys: String, CodingKey {
        case buyerReference, contractRef, tenderRef, receivingAdviceRef, despatchAdviceRef
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let lc = try decoder.container(keyedBy: LegacyReferenceKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        number = try c.decodeIfPresent(String.self, forKey: .number) ?? ""
        type = try c.decodeIfPresent(InvoiceTypeCode.self, forKey: .type) ?? .commercialInvoice
        status = try c.decodeIfPresent(InvoiceStatus.self, forKey: .status) ?? .draft
        issueDate = try c.decodeIfPresent(Date.self, forKey: .issueDate) ?? Date()
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        dueDate = try c.decodeIfPresent(Date.self, forKey: .dueDate) ?? Date().addingTimeInterval(30 * 86400)
        currency = try c.decodeIfPresent(String.self, forKey: .currency) ?? "EUR"
        profile = try c.decodeIfPresent(FacturXProfile.self, forKey: .profile) ?? .en16931
        seller = try c.decodeIfPresent(InvoiceParty.self, forKey: .seller) ?? InvoiceParty(name: "", street: "", postcode: "", city: "")
        buyer = try c.decodeIfPresent(InvoiceParty.self, forKey: .buyer) ?? InvoiceParty(name: "", street: "", postcode: "", city: "")
        companyID = try c.decodeIfPresent(UUID.self, forKey: .companyID)
        let legacyBuyerReference = try? lc.decodeIfPresent(String.self, forKey: .buyerReference)
        purchaseOrderRef = try c.decodeIfPresent(String.self, forKey: .purchaseOrderRef)
        precedingInvoiceRef = try c.decodeIfPresent(String.self, forKey: .precedingInvoiceRef)
        precedingInvoiceDate = try c.decodeIfPresent(Date.self, forKey: .precedingInvoiceDate)
        lines = try c.decodeIfPresent([InvoiceLine].self, forKey: .lines) ?? []
        paymentIBAN = try c.decodeIfPresent(String.self, forKey: .paymentIBAN)
        paymentBIC = try c.decodeIfPresent(String.self, forKey: .paymentBIC)
        paymentTerms = try c.decodeIfPresent(String.self, forKey: .paymentTerms)
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
        billingMode = try c.decodeIfPresent(BillingMode.self, forKey: .billingMode) ?? .m1
        legalNotePMT = try c.decodeIfPresent(String.self, forKey: .legalNotePMT) ?? "Indemnité forfaitaire pour frais de recouvrement due à compter du 1er jour de retard : 40 EUR"
        legalNotePMD = try c.decodeIfPresent(String.self, forKey: .legalNotePMD) ?? "Taux d'intérêt des pénalités de retard : 3 fois le taux légal en vigueur"
        legalNoteAAB = try c.decodeIfPresent(String.self, forKey: .legalNoteAAB) ?? "Escompte pour paiement anticipé : aucun"
        prepaidAmount = try c.decodeIfPresent(Double.self, forKey: .prepaidAmount) ?? 0
        superPDPRemoteID = try c.decodeIfPresent(String.self, forKey: .superPDPRemoteID)
        optionalFields = try c.decodeIfPresent([OptionalField].self, forKey: .optionalFields) ?? []
        attachments = try c.decodeIfPresent([Attachment].self, forKey: .attachments) ?? []
        internalComment = try c.decodeIfPresent(String.self, forKey: .internalComment)
        lastEmailSentAt = try c.decodeIfPresent(Date.self, forKey: .lastEmailSentAt)
        linkedSettlementRef = try c.decodeIfPresent(String.self, forKey: .linkedSettlementRef)
        migrateReference("ram:BuyerReference", legacyBuyerReference)
        migrateReference("ram:ContractReferencedDocument/ram:IssuerAssignedID", try? lc.decodeIfPresent(String.self, forKey: .contractRef))
        renameReferenceTag(from: "ram:TendererReferencedDocument/ram:IssuerAssignedID", to: "ram:AdditionalReferencedDocument/ram:IssuerAssignedID")
        migrateReference("ram:AdditionalReferencedDocument/ram:IssuerAssignedID", try? lc.decodeIfPresent(String.self, forKey: .tenderRef))
        migrateReference("ram:ReceivingAdviceReferencedDocument/ram:IssuerAssignedID", try? lc.decodeIfPresent(String.self, forKey: .receivingAdviceRef))
        migrateReference("ram:DespatchAdviceReferencedDocument/ram:IssuerAssignedID", try? lc.decodeIfPresent(String.self, forKey: .despatchAdviceRef))
    }

    private mutating func migrateReference(_ tagName: String, _ value: String?) {
        guard let value, !value.trimmingCharacters(in: .whitespaces).isEmpty,
              !optionalFields.contains(where: { $0.tagName == tagName }) else { return }
        optionalFields.append(OptionalField(tagName: tagName, value: value))
    }

    /// Même donnée, balise corrigée : le champ garde sa valeur et sa place dans la liste.
    /// Sans effet si la nouvelle balise est déjà renseignée (l'ancienne reste alors telle
    /// quelle, en balise libre non émise, plutôt que d'écraser l'une par l'autre).
    private mutating func renameReferenceTag(from oldTag: String, to newTag: String) {
        guard !optionalFields.contains(where: { $0.tagName == newTag }),
              let idx = optionalFields.firstIndex(where: { $0.tagName == oldTag }) else { return }
        optionalFields[idx].tagName = newTag
    }

    public var netToPay: Double {
        (grandTotal - prepaidAmount).rounded(toPlaces: 2)
    }

    /// Libellé du montant déjà payé (BT-113) sur l'écran et le PDF : un acompte déduit d'une
    /// facture de solde, ou la totalité de la facture en cadre « déjà payée » (B2/S2/M2).
    public var prepaidAmountLabel: String {
        billingMode.isAlreadyPaid ? "Montant déjà payé" : "Acompte déjà payé"
    }

    /// Aucun champ dédié : l'échéance est simplement dépassée et la facture non réglée.
    public var isOverdue: Bool {
        status != .paid && status != .cancelled && dueDate < Date()
    }

    public var overdueDays: Int {
        guard isOverdue else { return 0 }
        return Calendar.current.dateComponents([.day], from: dueDate, to: Date()).day ?? 0
    }

    public var lineTotal: Double {
        lines.reduce(0) { $0 + $1.lineTotal }.rounded(toPlaces: 2)
    }

    /// Un sous-total (BG-23) par couple (taux, catégorie) : voir `VATBreakdownEntry`.
    public var vatBreakdown: [VATBreakdownEntry] {
        VATBreakdownEntry.breakdown(of: lines)
    }

    public var taxTotal: Double {
        vatBreakdown.reduce(0) { $0 + $1.amount }.rounded(toPlaces: 2)
    }

    public var grandTotal: Double {
        (lineTotal + taxTotal).rounded(toPlaces: 2)
    }
}

public extension Double {
    /// Volontairement sans valeur par défaut pour `places` : avec `= 2`, un simple `x.rounded()`
    /// appelait cette méthode au lieu de l'arrondi à l'entier de la bibliothèque standard.
    func rounded(toPlaces places: Int) -> Double {
        let factor = pow(10.0, Double(places))
        return (self * factor).rounded(.toNearestOrEven) / factor
    }

    func formatted(amount: Bool = true) -> String {
        let value = String(format: "%.2f", self)
        return value
    }
}

public struct NormRef: Identifiable, Hashable {
    public let id: String
    public let code: String
    public let label: String
    public init(_ code: String, _ label: String) { self.id = code; self.code = code; self.label = label }
}

public enum NormRefs {
    public static let currencies: [NormRef] = [
        NormRef("EUR", "Euro (EUR)"),
        NormRef("USD", "Dollar américain (USD)"),
        NormRef("GBP", "Livre sterling (GBP)"),
        NormRef("CHF", "Franc suisse (CHF)"),
        NormRef("CAD", "Dollar canadien (CAD)"),
        NormRef("JPY", "Yen japonais (JPY)"),
        NormRef("CNY", "Yuan chinois (CNY)"),
    ]

    public static let units: [NormRef] = [
        NormRef("C62", "Unité (C62)"),
        NormRef("DAY", "Jour (DAY)"),
        NormRef("HUR", "Heure (HUR)"),
        NormRef("MIN", "Minute (MIN)"),
        NormRef("MON", "Mois (MON)"),
        NormRef("ANN", "Année (ANN)"),
        NormRef("KGM", "Kilogramme (KGM)"),
        NormRef("GRM", "Gramme (GRM)"),
        NormRef("MTR", "Mètre (MTR)"),
        NormRef("KTM", "Kilomètre (KTM)"),
        NormRef("MTQ", "Mètre cube (MTQ)"),
        NormRef("LTR", "Litre (LTR)"),
        NormRef("MTK", "Mètre carré (MTK)"),
        NormRef("SET", "Ensemble (SET)"),
        NormRef("PCE", "Pièce (PCE)"),
        NormRef("PR", "Paire (PR)"),
        NormRef("PCK", "Paquet (PCK)"),
        NormRef("BX", "Boîte (BX)"),
        NormRef("ROL", "Rouleau (ROL)"),
        NormRef("TNE", "Tonne (TNE)"),
    ]

    public static let countries: [NormRef] = [
        NormRef("FR", "France (FR)"),
        NormRef("DE", "Allemagne (DE)"),
        NormRef("BE", "Belgique (BE)"),
        NormRef("ES", "Espagne (ES)"),
        NormRef("IT", "Italie (IT)"),
        NormRef("NL", "Pays-Bas (NL)"),
        NormRef("LU", "Luxembourg (LU)"),
        NormRef("PT", "Portugal (PT)"),
        NormRef("CH", "Suisse (CH)"),
        NormRef("GB", "Royaume-Uni (GB)"),
        NormRef("IE", "Irlande (IE)"),
        NormRef("US", "États-Unis (US)"),
        NormRef("CA", "Canada (CA)"),
        NormRef("MA", "Maroc (MA)"),
        NormRef("DZ", "Algérie (DZ)"),
        NormRef("TN", "Tunisie (TN)"),
        NormRef("SN", "Sénégal (SN)"),
        NormRef("CI", "Côte d'Ivoire (CI)"),
    ]

    public static let endpointSchemes: [NormRef] = [
        NormRef("0225", "SIREN (0225)"),
        NormRef("0183", "SIRET (0183)"),
        NormRef("0193", "Code RNA (0193)"),
        NormRef("0200", "Numéro TVA (0200)"),
    ]
}
