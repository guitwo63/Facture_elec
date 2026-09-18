import Foundation

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
        case .b1: return "Facturation papier (B1)"
        case .s1: return "Portail public de facturation (S1)"
        case .m1: return "Dématérialisation (M1)"
        case .b2: return "Facturation papier (B2)"
        case .s2: return "Portail public (S2)"
        case .m2: return "Dématérialisation (M2)"
        case .s3: return "Portail public (S3)"
        case .b4: return "Facturation papier (B4)"
        case .s4: return "Portail public (S4)"
        case .m4: return "Dématérialisation (M4)"
        case .s5: return "Portail public (S5)"
        case .s6: return "Portail public (S6)"
        case .b7: return "Facturation papier (B7)"
        case .s7: return "Portail public (S7)"
        case .b8: return "Facturation papier (B8)"
        case .s8: return "Portail public (S8)"
        case .m8: return "Dématérialisation (M8)"
        case .b9: return "Facturation papier (B9)"
        case .s9: return "Portail public (S9)"
        case .m9: return "Dématérialisation (M9)"
        }
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

public enum OptionalFieldCatalogue {
    public static let header: [OptionalFieldTemplate] = [
        OptionalFieldTemplate("BT-10", "Ref. acheteur", "ram:BuyerReference", .header, "BT-10 - Reference acheteur (BuyerReference). Reference de routage/traitement attribuee par l'acheteur (ex. Leitweg-ID), distincte du numero de commande."),
        OptionalFieldTemplate("BT-11", "Ref. projet", "ram:SpecifiedProcuringProject/ram:ID", .header, "BT-11 - Reference du projet d'achat (SpecifiedProcuringProject/ID)."),
        OptionalFieldTemplate("BT-17", "Ref. contrat", "ram:ContractReferencedDocument/ram:IssuerAssignedID", .header, "BT-17 - Reference du contrat."),
        OptionalFieldTemplate("BT-18", "Ref. appel d'offres", "ram:TendererReferencedDocument/ram:IssuerAssignedID", .header, "BT-18 - Reference de l'appel d'offres."),
        OptionalFieldTemplate("BT-19", "Ref. bon de reception", "ram:ReceivingAdviceReferencedDocument/ram:IssuerAssignedID", .header, "BT-19 - Reference de l'avis de reception."),
        OptionalFieldTemplate("BT-20", "Ref. bon de livraison", "ram:DespatchAdviceReferencedDocument/ram:IssuerAssignedID", .header, "BT-20 - Reference de l'avis d'expedition."),
    ]
    public static let line: [OptionalFieldTemplate] = [
        OptionalFieldTemplate("BT-133", "Ref. contrat ligne", "ram:ContractReferencedDocument/ram:IssuerAssignedID", .line, "BT-133 - Reference de contrat au niveau de la ligne."),
        OptionalFieldTemplate("BT-134", "Ref. commande ligne", "ram:BuyerOrderReferencedDocument/ram:IssuerAssignedID", .line, "BT-134 - Reference de commande au niveau de la ligne."),
        OptionalFieldTemplate("BT-155", "ID produit vendeur", "ram:GlobalID", .line, "BT-155 - Identifiant produit (GlobalID) attribue par le vendeur. schemeID GTIN 0160 ajoute automatiquement."),
        OptionalFieldTemplate("BT-156", "ID produit acheteur", "ram:BuyerAssignedID", .line, "BT-156 - Identifiant produit attribue par l'acheteur (BuyerAssignedID)."),
    ]
    public static func templates(for location: OptionalFieldLocation) -> [OptionalFieldTemplate] {
        location == .header ? header : line
    }
    public static func template(forTag tagName: String, location: OptionalFieldLocation) -> OptionalFieldTemplate? {
        templates(for: location).first(where: { $0.tagName == tagName })
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

    /// BR-E-05/BR-AE-05/BR-G-05/BR-K-05/BR-O-05 (EN16931) : un motif
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

public enum FacturXProfile: String, Codable, CaseIterable {
    case minimum = "MINIMUM"
    case basicWL = "BASIC WL"
    case basic = "BASIC"
    case en16931 = "EN 16931"
    case extended = "EXTENDED"

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
}

/// Cycle de vie d'une facture, aligné sur les codes officiels `fr:2XX` de la réforme de
/// facturation électronique française (table "Meaning of fr:* statuses", documentation
/// SUPER PDP — https://superpdp.tech/openapi). `draft`/`issued` n'ont pas d'équivalent
/// réforme (purement locaux, avant tout dépôt). `sentToPDP` correspond à fr:200 (Déposée),
/// posé par le dépôt lui-même — jamais envoyé séparément via `sendInvoiceEvent` (voir
/// `InvoiceStatusStore.reformCode`). `sentToRecipient`/`receivedByRecipient`/`madeAvailable`
/// (fr:201/202/203) et `rejectedByRecipient` (fr:213) sont des statuts réseau, rapportés
/// automatiquement par SUPER PDP — l'API ne permet pas de les créer soi-même
/// (`status_code_create` ne les liste pas), donc ils ne sont atteignables qu'en réception
/// (synchronisation du statut PDP), jamais via un bouton de transition manuelle.
///
/// `accepted` (fr:207) et `rejected` (fr:206) restent, pour l'instant, sur les codes déjà
/// utilisés en production avant cette évolution — ces codes correspondent en réalité à
/// "Contestée"/"Partiellement acceptée" dans la table officielle, pas "Acceptée"/"Rejetée" ;
/// la correction (vers fr:205/fr:210) est un chantier séparé, volontairement pas fait ici
/// pour ne pas mélanger "compléter la table" et "corriger un mauvais code déjà en usage".
public enum InvoiceStatus: String, Codable, CaseIterable {
    case draft
    case issued
    case sentToPDP
    case sentToRecipient
    case receivedByRecipient
    case madeAvailable
    case acknowledged
    case onHold
    case accepted
    case rejected
    case rejectedByRecipient
    case completed
    case paymentSent
    case paid
    case cancelled

    public var label: String {
        switch self {
        case .draft: return "Brouillon"
        case .issued: return "Validée (non envoyée)"
        case .sentToPDP: return "Transmise au PDP"
        case .sentToRecipient: return "Envoyée au destinataire"
        case .receivedByRecipient: return "Reçue par le destinataire"
        case .madeAvailable: return "Mise à disposition"
        case .acknowledged: return "Accusé de réception"
        case .onHold: return "En attente"
        case .accepted: return "Acceptée par le PDP"
        case .rejected: return "Rejetée par le PDP"
        case .rejectedByRecipient: return "Rejetée par le destinataire"
        case .completed: return "Complétée"
        case .paymentSent: return "Paiement envoyé"
        case .paid: return "Payée"
        case .cancelled: return "Annulée"
        }
    }

    public var systemImage: String {
        switch self {
        case .draft: return "doc"
        case .issued: return "doc.fill"
        case .sentToPDP: return "paperplane.fill"
        case .sentToRecipient: return "paperplane.circle.fill"
        case .receivedByRecipient: return "tray.and.arrow.down.fill"
        case .madeAvailable: return "envelope.open.fill"
        case .acknowledged: return "checkmark.message.fill"
        case .onHold: return "pause.circle.fill"
        case .accepted: return "checkmark.seal.fill"
        case .rejected: return "xmark.octagon.fill"
        case .rejectedByRecipient: return "hand.thumbsdown.fill"
        case .completed: return "flag.checkered"
        case .paymentSent: return "arrow.up.circle.fill"
        case .paid: return "checkmark.circle.fill"
        case .cancelled: return "minus.circle.fill"
        }
    }

    public var hexColor: String {
        switch self {
        case .draft: return "6E6E73"
        case .issued: return "2A6EBB"
        case .sentToPDP: return "B07A2A"
        case .sentToRecipient: return "C08A3A"
        case .receivedByRecipient: return "A98B4A"
        case .madeAvailable: return "8FA23A"
        case .acknowledged: return "5B9BD5"
        case .onHold: return "D4A017"
        case .accepted: return "2E8B57"
        case .rejected: return "C0392B"
        case .rejectedByRecipient: return "A93226"
        case .completed: return "1E7E34"
        case .paymentSent: return "3A7DC9"
        case .paid: return "1E7E34"
        case .cancelled: return "8C8C8C"
        }
    }

    public var locksInvoice: Bool {
        switch self {
        case .draft, .rejected: return false
        case .issued, .sentToPDP, .sentToRecipient, .receivedByRecipient, .madeAvailable,
             .acknowledged, .onHold, .accepted, .rejectedByRecipient, .completed,
             .paymentSent, .paid, .cancelled:
            return true
        }
    }

    /// Ordre du cycle de vie (pour empêcher tout rapatriement rétrograde depuis la PDP).
    /// Des statuts alternatifs à un même point du cycle (ex. accepted/rejected/
    /// rejectedByRecipient après acknowledged) partagent le même rang : aucun n'est une
    /// "régression" par rapport à l'autre, ce sont des issues différentes.
    public var lifecycleRank: Int {
        switch self {
        case .draft: return 0
        case .issued: return 1
        case .sentToPDP: return 2
        case .sentToRecipient: return 3
        case .receivedByRecipient: return 4
        case .madeAvailable: return 5
        case .acknowledged: return 6
        case .onHold: return 7
        case .accepted: return 8
        case .rejected: return 8
        case .rejectedByRecipient: return 8
        case .completed: return 9
        case .paymentSent: return 10
        case .paid: return 11
        case .cancelled: return 11
        }
    }

    /// Transitions par défaut (personnalisables ensuite dans Réglages > Tables > Statuts des
    /// factures). Les statuts réseau non créables via l'API (`sentToRecipient`,
    /// `receivedByRecipient`, `madeAvailable`, `rejectedByRecipient` — voir la doc de
    /// l'enum) n'apparaissent dans aucune liste de transition manuelle : ils ne
    /// s'atteignent qu'en recevant le statut réel depuis SUPER PDP.
    public func allowedTransitions() -> [InvoiceStatus] {
        switch self {
        case .draft:
            return [.issued]
        case .issued:
            return [.sentToPDP, .rejected]
        case .sentToPDP:
            return [.acknowledged, .accepted, .rejected]
        case .sentToRecipient:
            return []
        case .receivedByRecipient:
            return []
        case .madeAvailable:
            return []
        case .acknowledged:
            return [.accepted, .onHold, .rejected]
        case .onHold:
            return [.accepted, .rejected]
        case .accepted:
            return [.completed, .paid, .rejected]
        case .rejected:
            return []
        case .rejectedByRecipient:
            return []
        case .completed:
            return [.paymentSent, .paid]
        case .paymentSent:
            return [.paid]
        case .paid:
            return []
        case .cancelled:
            return []
        }
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
        lastEmailSentAt: Date? = nil
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
    public var tenderRef: String? {
        get { referenceField("ram:TendererReferencedDocument/ram:IssuerAssignedID") }
        set { setReferenceField("ram:TendererReferencedDocument/ram:IssuerAssignedID", newValue) }
    }
    public var receivingAdviceRef: String? {
        get { referenceField("ram:ReceivingAdviceReferencedDocument/ram:IssuerAssignedID") }
        set { setReferenceField("ram:ReceivingAdviceReferencedDocument/ram:IssuerAssignedID", newValue) }
    }
    public var despatchAdviceRef: String? {
        get { referenceField("ram:DespatchAdviceReferencedDocument/ram:IssuerAssignedID") }
        set { setReferenceField("ram:DespatchAdviceReferencedDocument/ram:IssuerAssignedID", newValue) }
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
        case attachments, internalComment, lastEmailSentAt
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
        migrateReference("ram:BuyerReference", legacyBuyerReference)
        migrateReference("ram:ContractReferencedDocument/ram:IssuerAssignedID", try? lc.decodeIfPresent(String.self, forKey: .contractRef))
        migrateReference("ram:TendererReferencedDocument/ram:IssuerAssignedID", try? lc.decodeIfPresent(String.self, forKey: .tenderRef))
        migrateReference("ram:ReceivingAdviceReferencedDocument/ram:IssuerAssignedID", try? lc.decodeIfPresent(String.self, forKey: .receivingAdviceRef))
        migrateReference("ram:DespatchAdviceReferencedDocument/ram:IssuerAssignedID", try? lc.decodeIfPresent(String.self, forKey: .despatchAdviceRef))
    }

    private mutating func migrateReference(_ tagName: String, _ value: String?) {
        guard let value, !value.trimmingCharacters(in: .whitespaces).isEmpty,
              !optionalFields.contains(where: { $0.tagName == tagName }) else { return }
        optionalFields.append(OptionalField(tagName: tagName, value: value))
    }

    public var netToPay: Double {
        (grandTotal - prepaidAmount).rounded(toPlaces: 2)
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

    /// Un groupe par combinaison (taux, catégorie) : deux lignes à 0 % peuvent
    /// relever de catégories différentes (zéro-rated, autoliquidation,
    /// exportation…) et doivent apparaître comme des sous-totaux distincts
    /// (BG-23), chacun avec son propre motif d'exonération le cas échéant.
    public var vatBreakdown: [(rate: Double, category: VATCategory, exemptionReason: String?, basis: Double, amount: Double)] {
        struct Key: Hashable { let rate: Double; let category: VATCategory }
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
        return basisByKey.map { (key, basis) in
            let basisR = basis.rounded(toPlaces: 2)
            let amount = (basisR * key.rate / 100).rounded(toPlaces: 2)
            return (key.rate, key.category, reasonByKey[key], basisR, amount)
        }.sorted { $0.rate < $1.rate }
    }

    public var taxTotal: Double {
        vatBreakdown.reduce(0) { $0 + $1.amount }.rounded(toPlaces: 2)
    }

    public var grandTotal: Double {
        (lineTotal + taxTotal).rounded(toPlaces: 2)
    }
}

public extension Double {
    func rounded(toPlaces places: Int = 2) -> Double {
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
